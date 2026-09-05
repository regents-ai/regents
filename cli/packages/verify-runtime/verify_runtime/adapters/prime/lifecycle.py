"""Prime run lifecycle implemented behind Verify's existing executor contract."""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, BinaryIO, Mapping, Protocol

from verify_runtime.capsule.resolution import ResolvedRuntimeIdentity
from verify_runtime.model import EnvironmentFamily, MatchedSelection, TaskInstance, strict_json_loads

from .harness import RolloutConfig, hermes_rollout_config, require_rollout_config
from .normalize import normalize_prime_payload
from .packaging import package_taskset

ACTIVE_PRIME_STATES = {"pending", "boot", "setup", "running", "finalize", "scoring", "cancelling"}


class PrimeRunClient(Protocol):
    """The separated verifier and rollout boundaries implemented by live.py."""

    def prepare_verifier(self, sealed_packet: bytes) -> str: ...
    def destroy_verifier(self, verifier_handle: str) -> None: ...
    def start(self, agent_taskset: dict[str, Any], rollout_config: RolloutConfig, verifier_handle: str) -> str: ...
    def monitor(self, run_id: str) -> dict[str, Any]: ...
    def cancel(self, run_id: str, *, reason: str) -> dict[str, Any]: ...
    def finalize(self, run_id: str) -> bytes | BinaryIO: ...


@dataclass(frozen=True)
class PrimeLifecyclePayload:
    source: bytes | BinaryIO
    run_id: str
    terminal_state: str


def run_lifecycle(
    client: PrimeRunClient,
    *,
    agent_taskset: dict[str, Any],
    rollout_config: RolloutConfig,
    verifier_handle: str,
    timeout_seconds: int,
    poll_interval_seconds: float = 0.05,
) -> PrimeLifecyclePayload:
    """Start, monitor, deadline-cancel if needed, and finalize one Prime run."""

    try:
        validated_config = require_rollout_config(rollout_config)
        run_id = client.start(agent_taskset, validated_config, verifier_handle)
        if type(run_id) is not str or not run_id:
            raise ValueError("Prime start did not return a run identifier")
        deadline = time.monotonic() + timeout_seconds
        while True:
            update = client.monitor(run_id)
            if type(update) is not dict or update.get("run_id") != run_id or type(update.get("state")) is not str:
                raise ValueError("Prime monitor returned an invalid lifecycle record")
            if update["state"] not in ACTIVE_PRIME_STATES:
                return PrimeLifecyclePayload(client.finalize(run_id), run_id, update["state"])
            if time.monotonic() >= deadline:
                cancelled = client.cancel(run_id, reason="deadline")
                if type(cancelled) is not dict or cancelled.get("run_id") != run_id or cancelled.get("state") != "cancelling":
                    raise ValueError("Prime deadline cancellation returned an invalid lifecycle record")
                return PrimeLifecyclePayload(client.finalize(run_id), run_id, "deadline_timeout")
            if poll_interval_seconds > 0:
                time.sleep(poll_interval_seconds)
    finally:
        client.destroy_verifier(verifier_handle)


class PrimeExecutor:
    """Run one supplied family/taskset through Prime without bypassing the engine."""

    name = "prime"
    supplies_observed_identity = True

    def __init__(
        self,
        client: PrimeRunClient,
        identity: ResolvedRuntimeIdentity,
        *,
        family: EnvironmentFamily,
        tasks: tuple[TaskInstance, ...],
        task_inputs: Mapping[str, bytes],
        verifier_payloads: Mapping[str, bytes],
        private_state_dir: Path,
        answer_keys: Mapping[str, Any] | None = None,
        publication_bindings: Mapping[str, Mapping[str, Any]] | None = None,
        poll_interval_seconds: float = 0.05,
    ) -> None:
        if identity.executor != self.name:
            raise ValueError("Prime executor identity must name the prime executor")
        if not tasks or any(task.family_id != family.family_id for task in tasks):
            raise ValueError("Prime tasks must belong to the supplied family")
        if set(task_inputs) != {task.task_id for task in tasks} or set(verifier_payloads) != {task.task_id for task in tasks}:
            raise ValueError("Prime inputs and verifier payloads must exactly cover the supplied taskset")
        if answer_keys is not None and set(answer_keys) != {task.task_id for task in tasks}:
            raise ValueError("Prime answer keys must exactly cover the supplied taskset")
        committed_held_out = {
            task.task_id
            for task in tasks
            if task.provenance == "held_out" and task.answer_key_commitment is not None
        }
        if publication_bindings is not None and set(publication_bindings) != committed_held_out:
            raise ValueError("Prime publication bindings must exactly cover committed held-out tasks")
        if committed_held_out and publication_bindings is None:
            raise ValueError("Prime committed held-out tasks require publication bindings")
        self.client = client
        self.identity = identity
        self.family = family
        self.tasks = tasks
        self.task_inputs = dict(task_inputs)
        self.verifier_payloads = dict(verifier_payloads)
        self.answer_keys = dict(answer_keys or {})
        self.publication_bindings = {
            task_id: dict(binding)
            for task_id, binding in (publication_bindings or {}).items()
        }
        self.private_state_dir = private_state_dir
        self.poll_interval_seconds = poll_interval_seconds

    def resolve_identity(self) -> ResolvedRuntimeIdentity:
        return self.identity

    def execute(
        self,
        *,
        side: str,
        task_id: str,
        workspace: Path,
        timeout_seconds: int,
        max_spend_usd_cents: int,
    ):
        task = TaskInstance.from_dict(strict_json_loads((workspace / "task.json").read_bytes()))
        canonical_task = next((value for value in self.tasks if value.task_id == task_id), None)
        if task.task_id != task_id or canonical_task is None:
            raise ValueError("Prime workspace task does not match the engine task")
        if task.to_dict() != canonical_task.to_dict():
            raise ValueError("Prime workspace task does not match the locked task")
        matched_tasks = [value for value in self.tasks if value.partition != "development"]
        matched_order = next((index for index, value in enumerate(matched_tasks) if value.task_id == task_id), None)
        if matched_order is None:
            raise ValueError("Prime executor received a task outside the supplied matched selection")
        selection = MatchedSelection(
            task.task_id,
            task.partition,
            matched_order,
            task.provenance,
            canonical_task.answer_key_commitment,
        )
        package = package_taskset(
            family=self.family,
            selection=selection,
            task=task,
            side=side,
            skill_bytes=(workspace / "SKILL.md").read_bytes(),
            task_input=self.task_inputs[task_id],
            grader_source=self.verifier_payloads[task_id],
            max_spend_usd_cents=max_spend_usd_cents,
            answer_key=self.answer_keys.get(task_id),
            blinding_nonce=canonical_task.answer_key_blinding_nonce,
            publication_binding=self.publication_bindings.get(task_id),
        )
        verifier_handle = self.client.prepare_verifier(package.sealed_verifier_packet)
        rollout_config = hermes_rollout_config(
            hermes_version=self.identity.hermes_version,
            hermes_digest=self.identity.hermes_digest or "not-reported",
            provider=self.identity.provider,
            model=self.identity.model_identifier,
        )
        lifecycle = run_lifecycle(
            self.client,
            agent_taskset=package.agent_taskset,
            rollout_config=rollout_config,
            verifier_handle=verifier_handle,
            timeout_seconds=timeout_seconds,
            poll_interval_seconds=self.poll_interval_seconds,
        )
        return normalize_prime_payload(
            lifecycle.source,
            private_state_dir=self.private_state_dir,
            expected_identity=self.identity,
            expected_task=task,
            expected_run_id=lifecycle.run_id,
            expected_state=lifecycle.terminal_state,
        )
