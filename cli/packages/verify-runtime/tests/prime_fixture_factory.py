"""Recorded Prime executor factory used only by the subprocess reachability test."""

from __future__ import annotations

from copy import deepcopy
from pathlib import Path

from verify_runtime.adapters.prime import PrimeExecutor, new_verifier_handle
from verify_runtime.capsule.resolution import ResolvedRuntimeIdentity
from verify_runtime.families import FAMILY, GRADER_SOURCE, TASK_INPUTS, TASKS
from verify_runtime.families.contract_drift import _BUILTIN_PUBLICATION_BINDINGS
from verify_runtime.model import canonical_json_bytes, sha256_bytes, strict_json_loads

FIXTURES = Path(__file__).parent / "fixtures" / "prime"


def _fixture(name: str):
    return strict_json_loads((FIXTURES / name).read_bytes())


def _identity() -> ResolvedRuntimeIdentity:
    return ResolvedRuntimeIdentity(
        executor="prime",
        provider="prime",
        model_identifier="hermes-fixture-model-v1",
        model_version="recorded-v1",
        behavioral_fingerprint=None,
        model_mutability="mutable-hosted",
        hermes_version="hermes-fixture-v1",
        hermes_digest="81d05e6cfde7bd33247f06f4e8b450f7fc9aaf431160594f4b688f3f9be6601b",
        hermes_mutability="content-pinned",
        tool_components=(),
        config_components=(),
    )


class RecordedPrimeClient:
    def __init__(self) -> None:
        self.base = _fixture("completed.json")
        self.runs: dict[str, dict] = {}
        self.verifiers: dict[str, bytearray] = {}

    def prepare_verifier(self, sealed_packet: bytes) -> str:
        verifier_handle = new_verifier_handle()
        self.verifiers[verifier_handle] = bytearray(sealed_packet)
        return verifier_handle

    def destroy_verifier(self, verifier_handle: str) -> None:
        packet = self.verifiers.pop(verifier_handle, None)
        if packet is not None:
            packet[:] = b"\x00" * len(packet)

    def start(self, agent_taskset, rollout_config, verifier_handle):
        run_id = f"prime-{agent_taskset['matched_selection']['side']}-{agent_taskset['matched_selection']['task_id']}"
        self.runs[run_id] = {
            "taskset": agent_taskset,
            "rollout_config": rollout_config,
            "verifier_handle": verifier_handle,
        }
        return run_id

    def monitor(self, run_id):
        return {"run_id": run_id, "state": "completed"}

    def cancel(self, run_id, *, reason):
        return {"run_id": run_id, "state": "cancelling"}

    def finalize(self, run_id):
        run = self.runs.pop(run_id)
        taskset = run["taskset"]
        result = deepcopy(self.base)
        result["run_id"] = run_id
        result["state"] = "completed"
        result["identity"] = run["rollout_config"].to_dict()
        result["task"] = strict_json_loads(bytes(self.verifiers[run["verifier_handle"]]))["task"]
        result["taskset"] = {
            "format": taskset["format"],
            "digest": sha256_bytes(canonical_json_bytes(taskset)),
        }
        result["trace"]["id"] = f"trace-{run_id}"
        result["trace"]["task"]["data"]["name"] = result["task"]["task_id"]
        result["trace"]["task"]["data"]["prompt"] = taskset["task"]["input"]["content"].strip()
        result["trace"]["rewards"] = {
            "deterministic_contract_drift": 1.0 if taskset["matched_selection"]["side"] == "candidate" else 0.0
        }
        return canonical_json_bytes(result)


def create_executor(state_dir: Path) -> PrimeExecutor:
    """Construct the single recorded-family Prime executor for a subprocess check."""

    return PrimeExecutor(
        RecordedPrimeClient(),
        _identity(),
        family=FAMILY,
        tasks=TASKS,
        task_inputs=TASK_INPUTS,
        verifier_payloads={task.task_id: GRADER_SOURCE for task in TASKS},
        publication_bindings=_BUILTIN_PUBLICATION_BINDINGS,
        private_state_dir=state_dir,
        poll_interval_seconds=0,
    )
