from __future__ import annotations

import ast
import importlib
import importlib.util
import inspect
import io
import subprocess
import sys
import tomllib
from concurrent.futures import Future
from copy import deepcopy
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import call, patch

import pytest

from verify_runtime.adapters.prime import (
    FAILURE_FIDELITY_MAPPING,
    PRIME_SDK_VERSION,
    PRIME_TASKSET_FORMAT,
    PrimeExecutor,
    RolloutConfig,
    hermes_rollout_config,
    normalize_prime_payload,
    new_verifier_handle,
    package_taskset,
    run_lifecycle,
    taskset_bytes,
    terminal_status,
)
from verify_runtime.capsule.resolution import ResolvedRuntimeIdentity
from verify_runtime.families import BASELINE_SKILL, CANDIDATE_SKILL, FAMILY, GRADER_SOURCE, TASK_INPUTS, TASKS
from verify_runtime.families.contract_drift import _BUILTIN_PUBLICATION_BINDINGS
from verify_runtime.model import MatchedSelection, canonical_json_bytes, sha256_bytes, strict_json_loads
from verify_runtime.receipts import show_receipt
from verify_runtime.runner import MAX_CAPTURE_BYTES, run_builtin_comparison

FIXTURES = Path(__file__).parents[1] / "fixtures" / "prime"
RUNTIME_ROOT = Path(__file__).parents[2]


def _fixture(name: str):
    return strict_json_loads((FIXTURES / name).read_bytes())


def _identity() -> ResolvedRuntimeIdentity:
    return ResolvedRuntimeIdentity(
        executor="prime", provider="prime", model_identifier="hermes-fixture-model-v1", model_version="recorded-v1",
        behavioral_fingerprint=None, model_mutability="mutable-hosted", hermes_version="hermes-fixture-v1",
        hermes_digest="81d05e6cfde7bd33247f06f4e8b450f7fc9aaf431160594f4b688f3f9be6601b",
        hermes_mutability="content-pinned", tool_components=(), config_components=(),
    )


def _task(task_id: str = "contract-drift-validation-1"):
    return next(task for task in TASKS if task.task_id == task_id)


def _package(side: str = "candidate", skill_bytes: bytes = CANDIDATE_SKILL, grader: bytes = GRADER_SOURCE):
    task = _task()
    return package_taskset(
        family=FAMILY, selection=MatchedSelection(task.task_id, task.partition, 0), task=task, side=side,
        skill_bytes=skill_bytes, task_input=TASK_INPUTS[task.task_id], grader_source=grader,
        max_spend_usd_cents=1_000,
    )


def _normalize(value, state_dir: Path, *, identity: ResolvedRuntimeIdentity | None = None):
    return normalize_prime_payload(
        canonical_json_bytes(value), private_state_dir=state_dir,
        expected_identity=identity or _identity(), expected_task=_task(),
    )


def _harness() -> RolloutConfig:
    identity = _identity()
    return hermes_rollout_config(
        hermes_version=identity.hermes_version, hermes_digest=identity.hermes_digest or "",
        provider=identity.provider, model=identity.model_identifier,
    )


class _FakeLiveRollout:
    phase = SimpleNamespace(value="done")
    trace = None

    def __init__(self) -> None:
        self.started_runs = 0

    async def run(self):
        self.started_runs += 1


def _assert_live_start_failure_cleanup(factory, expected_exception, match, *, scheduling_failure=None) -> None:
    if importlib.util.find_spec("verifiers") is None:
        pytest.skip("Prime adapter dependency group is not installed")

    from verify_runtime.adapters.prime.live import LivePrimeClient

    with patch("verify_runtime.adapters.prime.live.Rollout", _FakeLiveRollout):
        client = LivePrimeClient(factory, lambda sealed_packet, opaque_handle: opaque_handle)
        try:
            package = _package()
            handle = client.prepare_verifier(package.sealed_verifier_packet)
            sealed_buffer = client.verifier_packets[handle]
            if scheduling_failure is None:
                with pytest.raises(expected_exception, match=match):
                    client.start(package.agent_taskset, _harness(), handle)
            else:
                with patch(
                    "verify_runtime.adapters.prime.live.asyncio.run_coroutine_threadsafe",
                    side_effect=scheduling_failure,
                ):
                    with pytest.raises(expected_exception, match=match):
                        client.start(package.agent_taskset, _harness(), handle)
            assert handle not in client.verifier_packets
            assert not any(sealed_buffer)
            assert client.runs == {}
        finally:
            client.close()


class RecordedPrimeClient:
    def __init__(self, wire_mutator=None, state_dir: Path | None = None) -> None:
        self.base = _fixture("completed.json")
        self.lifecycle = _fixture("lifecycle.json")
        self.runs: dict[str, dict] = {}
        self.verifiers: dict[str, bytearray] = {}
        self.rollout_inputs: list[dict] = []
        self.sealed_disk_hits: list[list[Path]] = []
        self.wire_mutator = wire_mutator
        self.state_dir = state_dir

    def prepare_verifier(self, sealed_packet: bytes) -> str:
        verifier_handle = new_verifier_handle()
        self.verifiers[verifier_handle] = bytearray(sealed_packet)
        return verifier_handle

    def destroy_verifier(self, verifier_handle: str) -> None:
        packet = self.verifiers.pop(verifier_handle, None)
        if packet is not None:
            packet[:] = b"\x00" * len(packet)

    def start(self, agent_taskset, rollout_config, verifier_handle):
        assert verifier_handle in self.verifiers
        self._observe_disk(verifier_handle)
        self.rollout_inputs.append({
            "agent_taskset": deepcopy(agent_taskset),
            "opaque_handle": verifier_handle,
            "rollout_config": rollout_config.to_dict(),
        })
        run_id = f"prime-{agent_taskset['matched_selection']['side']}-{agent_taskset['matched_selection']['task_id']}"
        self.runs[run_id] = {"taskset": agent_taskset, "rollout_config": rollout_config, "verifier_handle": verifier_handle, "monitor": 0, "cancel_reason": None}
        return run_id

    def monitor(self, run_id):
        run = self.runs[run_id]
        states = self.lifecycle["monitor_states"]
        if run["cancel_reason"] is not None:
            state = "deadline_timeout" if run["cancel_reason"] == "deadline" else "operator_cancelled"
        else:
            state = states[min(run["monitor"], len(states) - 1)]
        run["monitor"] += 1
        return {"run_id": run_id, "state": state}

    def cancel(self, run_id, *, reason):
        self.runs[run_id]["cancel_reason"] = reason
        return {"run_id": run_id, "state": "cancelling"}

    def finalize(self, run_id):
        run = self.runs.pop(run_id)
        self._observe_disk(run["verifier_handle"])
        taskset = run["taskset"]
        result = deepcopy(self.base)
        result["run_id"] = run_id
        reason = run["cancel_reason"]
        if reason == "deadline":
            result["state"] = "deadline_timeout"
        elif reason == "operator":
            result["state"] = "operator_cancelled"
        else:
            result["state"] = "completed"
        result["identity"] = run["rollout_config"].to_dict()
        result["task"] = strict_json_loads(bytes(self.verifiers[run["verifier_handle"]]))["task"]
        result["taskset"] = {"format": taskset["format"], "digest": sha256_bytes(canonical_json_bytes(taskset))}
        result["trace"]["id"] = f"trace-{run_id}"
        result["trace"]["task"]["data"]["name"] = result["task"]["task_id"]
        result["trace"]["task"]["data"]["prompt"] = taskset["task"]["input"]["content"].strip()
        reward = 1.0 if taskset["matched_selection"]["side"] == "candidate" else 0.0
        result["trace"]["rewards"] = {"deterministic_contract_drift": reward}
        if self.wire_mutator is not None:
            self.wire_mutator(result)
        return canonical_json_bytes(result)

    def _observe_disk(self, verifier_handle: str) -> None:
        if self.state_dir is None:
            return
        sealed_packet = bytes(self.verifiers[verifier_handle])
        self.sealed_disk_hits.append([
            path for path in self.state_dir.rglob("*")
            if path.is_file() and sealed_packet in path.read_bytes()
        ])


def _prepare(client: RecordedPrimeClient, package) -> str:
    return client.prepare_verifier(package.sealed_verifier_packet)


def _executor(state_dir: Path, client: RecordedPrimeClient | None = None) -> PrimeExecutor:
    recorded_client = client or RecordedPrimeClient()
    recorded_client.state_dir = state_dir
    return PrimeExecutor(
        recorded_client, _identity(), family=FAMILY, tasks=TASKS, task_inputs=TASK_INPUTS,
        verifier_payloads={task.task_id: GRADER_SOURCE for task in TASKS}, private_state_dir=state_dir,
        publication_bindings=_BUILTIN_PUBLICATION_BINDINGS,
        poll_interval_seconds=0,
    )


def _run_recorded(state_dir: Path, client: RecordedPrimeClient | None = None):
    return run_builtin_comparison(state_dir, _executor(state_dir, client))


def test_environment_identity(tmp_path: Path) -> None:
    """Conformance 1: the sole family is byte-stable and split into agent and verifier artifacts."""

    package = _package()
    assert package.agent_taskset == _fixture("taskset.json")
    sealed = strict_json_loads(package.sealed_verifier_packet)
    assert sealed["family"] == FAMILY.to_dict()
    assert sealed["task"] == _task().to_dict()
    assert sealed["grader"]["digest"] == _task().grader_digest
    result = _normalize(_fixture("completed.json"), tmp_path)
    public = strict_json_loads(result.artifact_bytes)
    assert public["task"]["family_id"] == FAMILY.family_id
    assert public["taskset"]["format"] == PRIME_TASKSET_FORMAT

    oversized = normalize_prime_payload(io.BytesIO(b"{" + b"x" * MAX_CAPTURE_BYTES), private_state_dir=tmp_path, expected_identity=_identity())
    assert oversized.status == "invalid"
    assert "payload_oversized" in oversized.detail


def test_hermes_identity(tmp_path: Path) -> None:
    """Conformance 2: locked identities are reported; every wire-identity mismatch is redacted."""

    fixture = _fixture("completed.json")
    result = _normalize(fixture, tmp_path)
    facts = dict(result.provider_facts)
    assert facts["reported_hermes_version"] == _identity().hermes_version
    assert facts["reported_hermes_digest"] == _identity().hermes_digest
    mismatch_paths = (
        ("identity", "provider", "SEALED-UNTRUSTED-PROVIDER"),
        ("identity", "model", "SEALED-UNTRUSTED-MODEL"),
        ("identity", "hermes_version", "SEALED-UNTRUSTED-HERMES-VERSION"),
        ("identity", "hermes_digest", "f" * 64),
        ("task", "family_id", "SEALED-UNTRUSTED-FAMILY"),
        ("task", "task_id", "SEALED-UNTRUSTED-TASK"),
        ("task", "role_id", "SEALED-UNTRUSTED-ROLE"),
    )
    for path_index, (section, field, untrusted_value) in enumerate(mismatch_paths):
        cases = [("nonempty", untrusted_value), ("empty", ""), ("absent", None), ("whitespace", " \t")]
        if field == "hermes_digest":
            cases.append(("invalid-syntax", "not-a-sha256-digest"))
        for case, replacement in cases:
            mismatched = deepcopy(fixture)
            if replacement is None:
                mismatched[section].pop(field)
            else:
                mismatched[section][field] = replacement
            invalid = _normalize(mismatched, tmp_path / f"direct-{path_index}-{case}")
            assert invalid.status == "invalid"
            assert invalid.score_millis is None
            expected_code = "hermes_identity_mismatch" if section == "identity" else "task_identity_mismatch"
            assert invalid.detail.startswith(f"prime.{expected_code};")
            wire_value = replacement or ""
            digest = sha256_bytes(wire_value.encode())
            mismatch = {
                "field": f"{'runtime' if section == 'identity' else 'task'}.{field}",
                "wire_value_digest": digest,
            }
            assert mismatch in strict_json_loads(invalid.artifact_bytes)["identity_mismatches"]
            direct_visible = invalid.artifact_bytes + invalid.detail.encode() + canonical_json_bytes({
                "provider": invalid.provider_facts,
                "runtime": invalid.runtime_facts,
                "tools": invalid.tool_facts,
            })
            if wire_value:
                assert wire_value.encode() not in direct_visible
            assert digest.encode() in direct_visible

            def mutate(wire, *, section=section, field=field, replacement=replacement):
                if replacement is None:
                    wire[section].pop(field)
                else:
                    wire[section][field] = replacement

            comparison = _run_recorded(
                tmp_path / f"receipt-{path_index}-{case}",
                RecordedPrimeClient(mutate),
            )
            receipt_bytes = b"".join(Path(pointer["path"]).read_bytes() for pointer in comparison["receipts"])
            receipt_visible = canonical_json_bytes(comparison) + receipt_bytes
            if wire_value:
                assert wire_value.encode() not in receipt_visible
            assert digest.encode() in receipt_visible

    for digest_index, field in enumerate(("input_digest", "grader_digest")):
        for case, replacement in (("nonempty", "f" * 64), ("whitespace", " \t"), ("invalid-syntax", "not-a-sha256-digest")):
            mismatched = deepcopy(fixture)
            mismatched["task"][field] = replacement
            invalid = _normalize(mismatched, tmp_path / f"task-digest-{digest_index}-{case}")
            digest = sha256_bytes(replacement.encode())
            assert invalid.status == "invalid"
            assert invalid.detail.startswith("prime.task_identity_mismatch;")
            assert {"field": f"task.{field}", "wire_value_digest": digest} in strict_json_loads(
                invalid.artifact_bytes
            )["identity_mismatches"]
            assert replacement.encode() not in invalid.artifact_bytes + invalid.detail.encode()


def test_matched_comparison(tmp_path: Path) -> None:
    """Conformance 3: matched runs share one task through completed and deadline lifecycles."""

    baseline = _package("baseline", BASELINE_SKILL).agent_taskset
    candidate = _package().agent_taskset
    assert baseline["task"] == candidate["task"]
    assert baseline["family_id"] == candidate["family_id"]
    client = RecordedPrimeClient()
    package = _package()
    verifier_handle = _prepare(client, package)
    payload = run_lifecycle(
        client, agent_taskset=candidate,
        rollout_config=_harness(),
        verifier_handle=verifier_handle, timeout_seconds=10, poll_interval_seconds=0,
    )
    assert _normalize(strict_json_loads(payload.source), tmp_path).status == "completed"

    deadline_client = RecordedPrimeClient()
    deadline_client.lifecycle["monitor_states"] = ["running"]
    deadline_handle = _prepare(deadline_client, package)
    timed_payload = run_lifecycle(
        deadline_client, agent_taskset=candidate,
        rollout_config=_harness(),
        verifier_handle=deadline_handle, timeout_seconds=0, poll_interval_seconds=0,
    )
    assert _normalize(strict_json_loads(timed_payload.source), tmp_path / "timeout").status == "timeout"

    config = _harness()
    invalid_configs = (
        config.to_dict() | {"state_dir": str(tmp_path)},
        config.to_dict() | {"future_option": "unexpected"},
        config.to_dict(),
    )
    for index, invalid_config in enumerate(invalid_configs):
        rejected_client = RecordedPrimeClient()
        rejected_handle = _prepare(rejected_client, package)
        expected_error = "unsupported fields" if index < 2 else "validated RolloutConfig"
        with pytest.raises((TypeError, ValueError), match=expected_error):
            run_lifecycle(
                rejected_client,
                agent_taskset=candidate,
                rollout_config=invalid_config,  # type: ignore[arg-type]
                verifier_handle=rejected_handle,
                timeout_seconds=10,
                poll_interval_seconds=0,
            )
        assert rejected_client.rollout_inputs == []
        assert rejected_client.verifiers == {}

    mutated_config = _harness()
    mutated_config.__dict__["model"] = str(tmp_path)
    rejected_client = RecordedPrimeClient()
    rejected_handle = _prepare(rejected_client, package)
    with pytest.raises(ValueError, match="model must be a path-free identifier"):
        run_lifecycle(
            rejected_client,
            agent_taskset=candidate,
            rollout_config=mutated_config,
            verifier_handle=rejected_handle,
            timeout_seconds=10,
            poll_interval_seconds=0,
        )
    assert rejected_client.rollout_inputs == []
    assert rejected_client.verifiers == {}

    with pytest.raises(ValueError, match="model must be a path-free identifier"):
        RolloutConfig(config.provider, str(tmp_path), config.hermes_version, config.hermes_digest)
    with pytest.raises(ValueError, match="provider must be a path-free identifier"):
        RolloutConfig("prime/runtime", config.model, config.hermes_version, config.hermes_digest)
    with pytest.raises(ValueError, match="model must be a path-free identifier"):
        RolloutConfig(config.provider, "C:relative-path", config.hermes_version, config.hermes_digest)


def test_trace_completeness(tmp_path: Path) -> None:
    """Conformance 4: private bytes are lossless and every documented trace channel is committed by count/digest."""

    fixture = _fixture("completed.json")
    raw = canonical_json_bytes(fixture)
    result = normalize_prime_payload(raw, private_state_dir=tmp_path, expected_identity=_identity(), expected_task=_task())
    public = strict_json_loads(result.artifact_bytes)
    trace = fixture["trace"]
    assert public["trace"]["counts"] == {"nodes": 3, "calls": 2, "tools": 1, "errors": 0, "extra_usage": 0}
    for channel, value in (("task_data", trace["task"]["data"]), ("nodes", trace["nodes"]), ("calls", trace["calls"]), ("tools", trace["tools"]), ("info", trace["info"]), ("errors", trace["errors"])):
        assert public["trace"]["channel_digests"][channel] == sha256_bytes(canonical_json_bytes(value))
    private = tmp_path / "verify" / "private" / "prime" / f"{sha256_bytes(raw)}.json"
    assert private.read_bytes() == raw
    assert public["trace"]["digest"] == sha256_bytes(canonical_json_bytes(trace))


def test_metric_fidelity(tmp_path: Path) -> None:
    """Conformance 5: rewards, metrics, usage, timing, artifact commitments, and cost stay exact."""

    fixture = _fixture("completed.json")
    result = _normalize(fixture, tmp_path)
    public = strict_json_loads(result.artifact_bytes)
    assert result.score_millis == 1_000
    assert result.cost_usd_cents == 12
    assert result.wall_time_ms == 1_250
    assert public["trace"]["rewards"] == [{"name": "deterministic_contract_drift", "value_decimal": "1.0", "value_millis": 1_000}]
    assert public["trace"]["metrics"] == [
        {"name": "contract_valid", "value_decimal": "1.0", "value_millis": 1_000},
        {"name": "files_changed", "value_decimal": "1.0", "value_millis": 1_000},
    ]
    assert public["trace"]["usage"] == {"prompt_tokens": 180, "completion_tokens": 50, "cached_input_tokens": 20, "reasoning_tokens": 10, "cost_decimal": "0.12", "cost_millis": 120}
    assert public["trace"]["timing"] == [{"phase": "boot", "duration_ms": 100}, {"phase": "setup", "duration_ms": 100}, {"phase": "generation", "duration_ms": 800}, {"phase": "finalize", "duration_ms": 100}, {"phase": "scoring", "duration_ms": 150}]
    assert public["artifacts"] == {"count": 1, "bytes": 44, "items": [{"digest": fixture["artifacts"][0]["digest"], "size_bytes": 44}]}


def test_failure_fidelity(tmp_path: Path) -> None:
    """Conformance 6: the mapping table, cancellation semantics, and unknown fail-safe are exhaustive."""

    recorded = _fixture("failure-states.json")
    table = [(provider, status) for provider, status, _ in FAILURE_FIDELITY_MAPPING[:-1]]
    assert [(row["provider_state"], row["terminal_status"]) for row in recorded] == table
    for index, row in enumerate(recorded):
        wire = _fixture("completed.json")
        wire["state"] = row["provider_state"]
        if row["provider_state"] != "completed":
            wire["trace"]["errors"] = [{"type": "RecordedFailure", "message": f"private-{row['provider_state']}", "status_code": None, "traceback": None}]
        result = _normalize(wire, tmp_path / str(index))
        assert result.status == row["terminal_status"]
        assert "private-" not in result.detail
    assert terminal_status("future-provider-state") == "infrastructure_failure"
    assert terminal_status("future-provider-state") not in {"completed", "agent_failure"}


def test_privacy_fidelity(tmp_path: Path) -> None:
    """Conformance 7: six raw trace channels and artifact bytes remain private; rollout sees no verifier data."""

    sentinels = [f"SEALED-CHANNEL-{index}" for index in range(7)]
    wire = _fixture("completed.json")
    wire["trace"]["task"]["data"]["answer_key"] = sentinels[0]
    wire["trace"]["info"]["private"] = sentinels[1]
    wire["trace"]["nodes"][0]["message"]["content"] = sentinels[2]
    wire["trace"]["calls"][0]["output"] = sentinels[3]
    wire["trace"]["tools"][0]["description"] = sentinels[4]
    wire["trace"]["errors"] = [{"type": "PrivateError", "message": sentinels[5], "status_code": None, "traceback": sentinels[5]}]
    artifact = sentinels[6].encode()
    import base64
    wire["artifacts"] = [{"name": "private-artifact", "digest": sha256_bytes(artifact), "size_bytes": len(artifact), "content_base64": base64.b64encode(artifact).decode()}]
    raw = canonical_json_bytes(wire)
    result = normalize_prime_payload(raw, private_state_dir=tmp_path, expected_identity=_identity(), expected_task=_task())
    public_material = result.artifact_bytes + result.detail.encode() + canonical_json_bytes({"provider": result.provider_facts, "runtime": result.runtime_facts, "tools": result.tool_facts})
    private = tmp_path / "verify" / "private" / "prime" / f"{sha256_bytes(raw)}.json"
    assert private.read_bytes() == raw
    stored_private = strict_json_loads(private.read_bytes())
    assert base64.b64decode(stored_private["artifacts"][0]["content_base64"], validate=True) == artifact
    for sentinel in sentinels[:6]:
        assert sentinel.encode() in raw
        assert sentinel.encode() not in public_material
    assert sentinels[6].encode() == artifact
    assert sentinels[6].encode() not in public_material

    grader = b"SEALED-VERIFIER-GRADER\n"
    task = _task()
    sealed_task = replace(task, grader_digest=sha256_bytes(grader))
    package = package_taskset(family=FAMILY, selection=MatchedSelection(task.task_id, task.partition, 0), task=sealed_task, side="candidate", skill_bytes=CANDIDATE_SKILL, task_input=TASK_INPUTS[task.task_id], grader_source=grader, max_spend_usd_cents=1_000)
    client = RecordedPrimeClient(state_dir=tmp_path / "private-verifier")
    verifier_handle = _prepare(client, package)
    run_lifecycle(
        client,
        agent_taskset=package.agent_taskset,
        rollout_config=_harness(),
        verifier_handle=verifier_handle,
        timeout_seconds=10,
        poll_interval_seconds=0,
    )
    rollout_bytes = canonical_json_bytes(client.rollout_inputs)
    assert grader.strip() not in rollout_bytes
    assert b"grader" not in rollout_bytes and b"answer" not in rollout_bytes and b"rubric" not in rollout_bytes
    assert str(client.state_dir).encode() not in rollout_bytes
    assert all(not hits for hits in client.sealed_disk_hits)
    assert client.verifiers == {}
    assert not list(client.state_dir.rglob("verifiers"))

    low_entropy_graders = (b"0", b"1")
    low_entropy_packages = []
    for candidate in low_entropy_graders:
        candidate_task = replace(task, grader_digest=sha256_bytes(candidate))
        low_entropy_packages.append(package_taskset(
            family=FAMILY, selection=MatchedSelection(task.task_id, task.partition, 0), task=candidate_task,
            side="candidate", skill_bytes=CANDIDATE_SKILL, task_input=TASK_INPUTS[task.task_id],
            grader_source=candidate, max_spend_usd_cents=1_000,
        ))
    assert taskset_bytes(low_entropy_packages[0]) == taskset_bytes(low_entropy_packages[1])
    independent_tokens = ("A" * 43, "B" * 43)
    handle_client = RecordedPrimeClient(state_dir=tmp_path / "independent-handles")
    with patch("verify_runtime.adapters.prime.packaging.secrets.token_urlsafe", side_effect=independent_tokens) as token_source:
        handles = tuple(handle_client.prepare_verifier(candidate.sealed_verifier_packet) for candidate in low_entropy_packages)
    assert token_source.call_args_list == [call(32), call(32)]
    assert handles == independent_tokens
    for handle, candidate, grader_candidate in zip(handles, low_entropy_packages, low_entropy_graders, strict=True):
        assert bytes(handle_client.verifiers[handle]) == candidate.sealed_verifier_packet
        assert grader_candidate not in handle.encode()
        assert sha256_bytes(candidate.sealed_verifier_packet).encode() not in handle.encode()
        handle_client.destroy_verifier(handle)
    assert handle_client.verifiers == {}
    assert not any(path.is_file() for path in handle_client.state_dir.rglob("*"))

    receipt_client = RecordedPrimeClient()
    receipt_client.base = wire
    comparison = _run_recorded(tmp_path / "comparison", receipt_client)
    receipt_bytes = b"".join(Path(pointer["path"]).read_bytes() for pointer in comparison["receipts"])
    for sentinel in sentinels:
        assert sentinel.encode() not in receipt_bytes


def test_reproduction_fidelity(tmp_path: Path) -> None:
    """Conformance 8: package, private wire, public manifest, and receipts reproduce byte-for-byte."""

    values = dict(family=FAMILY, selection=MatchedSelection(_task().task_id, _task().partition, 0), task=_task(), side="candidate", skill_bytes=CANDIDATE_SKILL, task_input=TASK_INPUTS[_task().task_id], grader_source=GRADER_SOURCE, max_spend_usd_cents=1_000)
    first_package = package_taskset(**values)
    second_package = package_taskset(**values)
    assert taskset_bytes(first_package) == taskset_bytes(second_package)
    assert strict_json_loads(taskset_bytes(first_package)) == _fixture("taskset.json")
    assert first_package.sealed_verifier_packet == second_package.sealed_verifier_packet
    fixture = _fixture("completed.json")
    first_normalized = _normalize(fixture, tmp_path / "normalized-first")
    second_normalized = _normalize(fixture, tmp_path / "normalized-second")
    assert first_normalized == second_normalized
    first = _run_recorded(tmp_path / "first")
    second = _run_recorded(tmp_path / "second")
    assert first["summary"]["comparison_result"] == "positive"
    first_receipts = [strict_json_loads(Path(pointer["path"]).read_bytes()) for pointer in first["receipts"]]
    second_receipts = [strict_json_loads(Path(pointer["path"]).read_bytes()) for pointer in second["receipts"]]
    assert {receipt.pop("store_id") for receipt in first_receipts} != {receipt.pop("store_id") for receipt in second_receipts}
    assert first_receipts == second_receipts
    assert all(show_receipt(tmp_path / "first", pointer["digest"])["verified"] for pointer in first["receipts"])


def test_evidence_neutrality(tmp_path: Path) -> None:
    """Conformance 9: authorship commitments remain stable without exposing author text or score direction."""

    positive = _fixture("completed.json")
    null = deepcopy(positive)
    null["trace"]["rewards"] = {"deterministic_contract_drift": 0.0}
    positive_public = strict_json_loads(_normalize(positive, tmp_path / "positive").artifact_bytes)
    null_public = strict_json_loads(_normalize(null, tmp_path / "null").artifact_bytes)
    assert positive_public["trace"]["channel_digests"]["evidence"] == null_public["trace"]["channel_digests"]["evidence"]
    public_bytes = canonical_json_bytes(positive_public)
    for author in positive["trace"]["info"]["evidence"].values():
        assert author.encode() not in public_bytes
    assert positive_public["trace"]["rewards"] != null_public["trace"]["rewards"]


def test_version_isolation(tmp_path: Path) -> None:
    """Conformance 10: the pin is optional and, when installed, its v1 API/state vocabulary matches."""

    project = tomllib.loads((RUNTIME_ROOT / "pyproject.toml").read_text())
    assert project["project"]["dependencies"] == []
    assert project["dependency-groups"]["adapters-prime"] == [f"verifiers=={PRIME_SDK_VERSION}"]
    model_dir = RUNTIME_ROOT / "verify_runtime" / "model"
    adapter_dir = RUNTIME_ROOT / "verify_runtime" / "adapters" / "prime"
    for path in model_dir.glob("*.py"):
        assert "verify_runtime.adapters" not in path.read_text()
    provider_importers = []
    for path in adapter_dir.glob("*.py"):
        source = path.read_text()
        imports = [node.module for node in ast.walk(ast.parse(source, filename=str(path))) if isinstance(node, ast.ImportFrom) and node.module]
        assert not any(name.startswith("verify_runtime.model.") for name in imports)
        if "import verifiers" in source or "from verifiers" in source:
            provider_importers.append(path.name)
    assert provider_importers == ["live.py"]

    if importlib.util.find_spec("verifiers") is None:
        guarded = subprocess.run([sys.executable, "-S", "-c", "import verify_runtime.adapters.prime.live"], cwd=RUNTIME_ROOT, capture_output=True, text=True, check=False)
        assert guarded.returncode != 0
        assert "optional adapters-prime dependency group" in guarded.stderr
    else:
        import verifiers
        from verifiers.v1 import Harness, Rollout, Taskset, Trace
        from verifiers.v1 import errors as sdk_errors
        from verifiers.v1.rollout import Phase
        from verify_runtime.adapters.prime.live import LivePrimeClient, SDK_ERROR_STATE_MAP, SDK_PHASE_STATES
        assert verifiers.__version__ == PRIME_SDK_VERSION
        assert all(value is not None for value in (Harness, Rollout, Taskset, Trace))
        assert {phase.value for phase in Phase} == SDK_PHASE_STATES
        assert {getattr(sdk_errors, name).__name__ for name in SDK_ERROR_STATE_MAP} == set(SDK_ERROR_STATE_MAP)
        assert set(SDK_ERROR_STATE_MAP.values()) <= {provider for provider, _, _ in FAILURE_FIDELITY_MAPPING}
        derivations = _fixture("live-derivation.json")
        for row in derivations:
            error = row["trace"]["error"]
            trace = SimpleNamespace(
                stop_condition=row["trace"]["stop_condition"],
                error=None if error is None else SimpleNamespace(type=error["type"]),
            )
            assert LivePrimeClient._state(trace) == row["provider_state"]
        cyclic: dict = {}
        cyclic["self"] = cyclic
        LivePrimeClient._enforce_trace_bound(cyclic)  # type: ignore[arg-type]
        with pytest.raises(ValueError, match="4MiB ingestion boundary"):
            LivePrimeClient._enforce_trace_bound({"private": "x" * MAX_CAPTURE_BYTES})  # type: ignore[arg-type]

        factory_calls = []

        class FakeTrace:
            stop_condition = None
            error = None
            errors = []
            usage = None
            info = {"artifacts": []}

            def to_record(self):
                return deepcopy(_fixture("completed.json")["trace"])

        class FakeRollout:
            phase = SimpleNamespace(value="done")
            trace = None

            async def run(self):
                self.trace = FakeTrace()
                return self.trace

        def rollout_factory(agent_taskset, opaque_handle, rollout_config):
            assert isinstance(rollout_config, RolloutConfig)
            factory_calls.append((deepcopy(agent_taskset), opaque_handle, rollout_config))
            return FakeRollout()

        assert tuple(inspect.signature(rollout_factory).parameters) == (
            "agent_taskset",
            "opaque_handle",
            "rollout_config",
        )
        with patch("verify_runtime.adapters.prime.live.Rollout", FakeRollout):
            live_client = LivePrimeClient(rollout_factory, lambda sealed_packet, opaque_handle: opaque_handle)
            try:
                package = _package()
                handle = live_client.prepare_verifier(package.sealed_verifier_packet)
                sealed_buffer = live_client.verifier_packets[handle]
                invalid_handle = live_client.prepare_verifier(package.sealed_verifier_packet)
                with pytest.raises(ValueError, match="unsupported fields: state_dir"):
                    live_client.start(
                        package.agent_taskset,
                        _harness().to_dict() | {"state_dir": str(tmp_path)},  # type: ignore[arg-type]
                        invalid_handle,
                    )
                assert factory_calls == []
                assert invalid_handle not in live_client.verifier_packets
                mutated_handle = live_client.prepare_verifier(package.sealed_verifier_packet)
                mutated_config = _harness()
                mutated_config.__dict__["model"] = str(tmp_path)
                with pytest.raises(ValueError, match="model must be a path-free identifier"):
                    live_client.start(package.agent_taskset, mutated_config, mutated_handle)
                assert factory_calls == []
                assert mutated_handle not in live_client.verifier_packets
                run_id = live_client.start(package.agent_taskset, _harness(), handle)
                payload = live_client.finalize(run_id)
                assert strict_json_loads(payload)["task"] == _task().to_dict()
                assert len(factory_calls) == 1
                factory_bytes = canonical_json_bytes([
                    (taskset, opaque_handle, rollout_config.to_dict())
                    for taskset, opaque_handle, rollout_config in factory_calls
                ])
                assert package.sealed_verifier_packet not in factory_bytes
                assert str(tmp_path).encode() not in factory_bytes
                assert b"grader" not in factory_bytes and b"answer" not in factory_bytes and b"rubric" not in factory_bytes
                assert handle not in live_client.verifier_packets
                assert not any(sealed_buffer)
                assert not any(path.is_file() for path in tmp_path.rglob("*"))
            finally:
                live_client.close()


def test_live_start_destroys_verifier_when_factory_raises_value_error() -> None:
    factory_calls = []

    def factory(*args):
        factory_calls.append(args)
        raise ValueError("factory value failure")

    _assert_live_start_failure_cleanup(factory, ValueError, "factory value failure")
    assert len(factory_calls) == 1


def test_live_start_destroys_verifier_when_factory_raises_type_error() -> None:
    factory_calls = []

    def factory(*args):
        factory_calls.append(args)
        raise TypeError("factory type failure")

    _assert_live_start_failure_cleanup(factory, TypeError, "factory type failure")
    assert len(factory_calls) == 1


def test_live_start_destroys_verifier_when_factory_raises_runtime_error() -> None:
    factory_calls = []

    def factory(*args):
        factory_calls.append(args)
        raise RuntimeError("factory runtime failure")

    _assert_live_start_failure_cleanup(factory, RuntimeError, "factory runtime failure")
    assert len(factory_calls) == 1


def test_live_start_destroys_verifier_when_factory_returns_wrong_type() -> None:
    factory_calls = []

    def factory(*args):
        factory_calls.append(args)
        return object()

    _assert_live_start_failure_cleanup(factory, TypeError, "factory must return")
    assert len(factory_calls) == 1


def test_live_start_destroys_verifier_when_scheduling_fails() -> None:
    rollout = _FakeLiveRollout()
    factory_calls = []

    def factory(*args):
        factory_calls.append(args)
        return rollout

    def reject_scheduling(coroutine, _loop):
        coroutine.close()
        raise RuntimeError("scheduling failure")

    _assert_live_start_failure_cleanup(
        factory,
        RuntimeError,
        "scheduling failure",
        scheduling_failure=reject_scheduling,
    )
    assert len(factory_calls) == 1
    assert rollout.started_runs == 0


def test_live_start_destroys_verifier_when_factory_raises_keyboard_interrupt() -> None:
    if importlib.util.find_spec("verifiers") is None:
        pytest.skip("Prime adapter dependency group is not installed")

    factory_calls = []

    def factory(*args):
        factory_calls.append(args)
        raise KeyboardInterrupt("factory interrupted")

    with patch("verify_runtime.adapters.prime.live.asyncio.run_coroutine_threadsafe") as schedule:
        _assert_live_start_failure_cleanup(factory, KeyboardInterrupt, "factory interrupted")
    assert len(factory_calls) == 1
    schedule.assert_not_called()


def test_live_start_cancels_future_when_registration_is_interrupted() -> None:
    if importlib.util.find_spec("verifiers") is None:
        pytest.skip("Prime adapter dependency group is not installed")

    from verify_runtime.adapters.prime.live import LivePrimeClient

    rollout = _FakeLiveRollout()
    scheduled_future = Future()

    def schedule(coroutine, _loop):
        coroutine.close()
        return scheduled_future

    with (
        patch("verify_runtime.adapters.prime.live.Rollout", _FakeLiveRollout),
        patch("verify_runtime.adapters.prime.live.asyncio.run_coroutine_threadsafe", side_effect=schedule),
        patch(
            "verify_runtime.adapters.prime.live._LiveRun",
            side_effect=KeyboardInterrupt("registration interrupted"),
        ),
    ):
        client = LivePrimeClient(lambda *_: rollout, lambda sealed_packet, opaque_handle: opaque_handle)
        try:
            package = _package()
            handle = client.prepare_verifier(package.sealed_verifier_packet)
            sealed_buffer = client.verifier_packets[handle]
            with pytest.raises(KeyboardInterrupt, match="registration interrupted"):
                client.start(package.agent_taskset, _harness(), handle)
            assert handle not in client.verifier_packets
            assert not any(sealed_buffer)
            assert client.runs == {}
            assert scheduled_future.cancelled()
            assert rollout.started_runs == 0
        finally:
            client.close()
