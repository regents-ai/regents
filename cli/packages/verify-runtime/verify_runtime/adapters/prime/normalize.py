"""Bounded, private-first normalization of pinned Prime v1 wire records.

Failure-fidelity mapping (provider state -> Verify terminal status):
completed -> completed; deadline_timeout -> timeout; harness_timeout -> timeout;
task_invalid -> invalid; operator_cancelled -> invalid; harness_error ->
agent_failure; provider_error, sandbox_error, toolset_error, user_error,
interception_error, tunnel_error, rollout_error, and infrastructure_error ->
infrastructure_failure; every unknown state -> infrastructure_failure.
"""

from __future__ import annotations

import base64
import binascii
import os
import tempfile
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, BinaryIO

from verify_runtime.capsule.resolution import ResolvedRuntimeIdentity
from verify_runtime.model import (
    MAX_RECORD_INTEGER,
    TaskInstance,
    TerminalStatus,
    canonical_json_bytes,
    require_bounded_int,
    require_exact_keys,
    require_record,
    require_string,
    require_type,
    sha256_bytes,
    strict_json_loads,
)
from verify_runtime.runner import MAX_CAPTURE_BYTES, ExecutionResult

from .packaging import PRIME_SDK_VERSION, PRIME_TASKSET_FORMAT

FAILURE_FIDELITY_MAPPING: tuple[tuple[str, TerminalStatus, str], ...] = (
    ("completed", "completed", "Prime completed and scored the task"),
    ("deadline_timeout", "timeout", "The adapter-enforced wall deadline fired and cancelled the rollout"),
    ("harness_timeout", "timeout", "The locked harness wall limit expired"),
    ("task_invalid", "invalid", "Task setup, finalization, or scoring was invalid"),
    ("operator_cancelled", "invalid", "An operator cancelled the rollout outside the wall deadline"),
    ("harness_error", "agent_failure", "The Hermes harness or agent process failed"),
    ("provider_error", "infrastructure_failure", "The model provider or its transport failed"),
    ("sandbox_error", "infrastructure_failure", "The Prime runtime or sandbox failed"),
    ("toolset_error", "infrastructure_failure", "The tool substrate failed"),
    ("user_error", "infrastructure_failure", "The user-simulator substrate failed"),
    ("interception_error", "infrastructure_failure", "The interception service failed"),
    ("tunnel_error", "infrastructure_failure", "The Prime tunnel failed"),
    ("rollout_error", "infrastructure_failure", "An unclassified Prime rollout boundary failed"),
    ("infrastructure_error", "infrastructure_failure", "The live SDK boundary failed outside a rollout"),
    ("unknown / unrecognized", "infrastructure_failure", "Fail-safe for every provider state absent from this table"),
)
PRIME_TERMINAL_STATUS_MAP = {provider: status for provider, status, _ in FAILURE_FIDELITY_MAPPING[:-1]}

_WIRE_KEYS = {"schema_version", "run_id", "state", "identity", "task", "taskset", "trace", "artifacts", "cost", "retry_count"}
_TRACE_KEYS = {
    "id", "task", "runtime", "version", "verifiers", "run", "agent", "nodes", "tools", "calls",
    "rewards", "metrics", "info", "extra_usage", "is_completed", "stop_condition", "errors", "timing",
}
_TIMING_PHASES = ("boot", "setup", "generation", "finalize", "scoring")
_USAGE_FIELDS = ("prompt_tokens", "completion_tokens", "cached_input_tokens", "reasoning_tokens")
_REWARD_FIELDS = {"deterministic_contract_drift"}
_METRIC_FIELDS = {"contract_valid", "files_changed"}
_RUNTIME_IDENTITY_FIELDS = ("provider", "model", "hermes_version", "hermes_digest")
_TASK_IDENTITY_FIELDS = ("family_id", "task_id", "role_id")


def terminal_status(provider_state: str) -> TerminalStatus:
    """Map explicit states and fail every unrecognized state toward infrastructure."""

    return PRIME_TERMINAL_STATUS_MAP.get(provider_state, "infrastructure_failure")


def _record(value: Any, path: str) -> dict[str, Any]:
    return require_record(value, path)


def _list(value: Any, path: str) -> list[Any]:
    return require_type(value, list, path)


def _exact(value: dict[str, Any], expected: set[str], path: str) -> None:
    require_exact_keys(value, expected, path)


def _string(value: Any, path: str, *, empty: bool = False) -> str:
    return require_string(value, path, allow_empty=empty)


def _sha256(value: Any, path: str) -> str:
    digest = _string(value, path)
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise ValueError(f"{path} must be a lowercase SHA-256 digest")
    return digest


def _untrusted_digest(value: str) -> str:
    return sha256_bytes(value.encode("utf-8"))


def _identity_mismatches(
    wire_values: dict[str, str],
    locked_values: dict[str, str],
    *,
    prefix: str,
) -> list[dict[str, str]]:
    return [
        {"field": f"{prefix}.{name}", "wire_value_digest": _untrusted_digest(wire_values[name])}
        for name in locked_values
        if not wire_values[name] or wire_values[name] != locked_values[name]
    ]


def _optional_identity_values(value: Any, expected: tuple[str, ...], path: str) -> dict[str, str]:
    record = _record(value, path)
    unexpected = set(record) - set(expected)
    if unexpected:
        raise ValueError(f"{path} has unexpected fields: {', '.join(sorted(unexpected))}")
    result = {}
    for name in expected:
        wire_value = record.get(name, "")
        if type(wire_value) is not str:
            raise ValueError(f"{path}.{name} must be a string")
        result[name] = wire_value
    return result


def _integer(value: Any, path: str, *, minimum: int = 0) -> int:
    return require_bounded_int(value, path, minimum=minimum)


def _decimal(value: Any, path: str) -> Decimal:
    if isinstance(value, bool) or not isinstance(value, int | float | Decimal):
        raise ValueError(f"{path} must be numeric")
    try:
        result = Decimal(str(value))
    except InvalidOperation as error:
        raise ValueError(f"{path} must be finite") from error
    if not result.is_finite():
        raise ValueError(f"{path} must be finite")
    return result


def _millis(value: Any, path: str) -> tuple[str, int]:
    decimal = _decimal(value, path)
    scaled = decimal * 1_000
    if scaled != scaled.to_integral_value() or abs(scaled) > MAX_RECORD_INTEGER:
        raise ValueError(f"{path} cannot be represented losslessly in millis")
    return str(decimal), int(scaled)


def _signals(value: Any, path: str, expected: set[str]) -> list[dict[str, Any]]:
    record = _record(value, path)
    if set(record) != expected:
        raise ValueError(f"{path} does not match the allow-listed signal vocabulary")
    result = []
    for name in sorted(record):
        text, millis = _millis(record[name], f"{path}.{name}")
        result.append({"name": _string(name, f"{path}.name"), "value_decimal": text, "value_millis": millis})
    return result


def _artifact_summaries(value: Any) -> tuple[list[dict[str, Any]], int]:
    artifacts = _list(value, "prime.artifacts")
    declared_total = 0
    checked: list[tuple[dict[str, Any], str, int, str]] = []
    for index, item in enumerate(artifacts):
        artifact = _record(item, f"prime.artifacts[{index}]")
        _exact(artifact, {"name", "digest", "size_bytes", "content_base64"}, f"prime.artifacts[{index}]")
        size = _integer(artifact["size_bytes"], f"prime.artifacts[{index}].size_bytes")
        declared_total += size
        if declared_total > MAX_CAPTURE_BYTES:
            raise ValueError("Prime artifact declarations exceed the 4MiB capture limit")
        content_text = _string(artifact["content_base64"], f"prime.artifacts[{index}].content_base64", empty=True)
        if len(content_text) > ((size + 2) // 3) * 4:
            raise ValueError(f"prime.artifacts[{index}] encoded content exceeds its declared size")
        checked.append((artifact, _sha256(artifact["digest"], f"prime.artifacts[{index}].digest"), size, content_text))

    summaries = []
    for index, (artifact, digest, size, content_text) in enumerate(checked):
        try:
            content = base64.b64decode(content_text, validate=True)
        except (binascii.Error, ValueError) as error:
            raise ValueError(f"prime.artifacts[{index}] content is not valid base64") from error
        if len(content) != size or sha256_bytes(content) != digest:
            raise ValueError(f"prime.artifacts[{index}] content does not match its digest and size")
        summaries.append({"digest": digest, "size_bytes": size})
    return summaries, declared_total


def _timing_summary(value: Any) -> tuple[list[dict[str, Any]], int]:
    timing = _record(value, "prime.trace.timing")
    starts: list[Decimal] = []
    ends: list[Decimal] = []
    phases = []
    for name in _TIMING_PHASES:
        span = _record(timing[name], f"prime.trace.timing.{name}")
        start = _decimal(span["start"], f"prime.trace.timing.{name}.start")
        end = _decimal(span["end"], f"prime.trace.timing.{name}.end")
        if end < start:
            raise ValueError(f"prime.trace.timing.{name} ends before it starts")
        duration = (end - start) * 1_000
        if duration != duration.to_integral_value() or duration > MAX_RECORD_INTEGER:
            raise ValueError(f"prime.trace.timing.{name} cannot be represented losslessly")
        phases.append({"phase": name, "duration_ms": int(duration)})
        starts.append(start)
        ends.append(end)
    wall = (max(ends) - min(starts)) * 1_000
    if wall < 0 or wall != wall.to_integral_value() or wall > MAX_RECORD_INTEGER:
        raise ValueError("Prime trace timing cannot be represented as wall milliseconds")
    return phases, int(wall)


def _usage_summary(calls: list[Any]) -> dict[str, Any]:
    totals = {name: 0 for name in _USAGE_FIELDS}
    cost = Decimal(0)
    for index, item in enumerate(calls):
        call = _record(item, f"prime.trace.calls[{index}]")
        usage = _record(call["usage"], f"prime.trace.calls[{index}].usage")
        for name in _USAGE_FIELDS:
            totals[name] += _integer(usage[name], f"prime.trace.calls[{index}].usage.{name}")
        cost += _decimal(usage["cost"], f"prime.trace.calls[{index}].usage.cost")
    cost_text, cost_millis = _millis(cost, "prime.trace.calls.usage.cost")
    return totals | {"cost_decimal": cost_text, "cost_millis": cost_millis}


def _private_store(private_state_dir: Path, raw: bytes, digest: str) -> None:
    directory = private_state_dir / "verify" / "private" / "prime"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    path = directory / f"{digest}.json"
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{digest}.", dir=directory)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            os.chmod(temporary, 0o600)
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path)
        except FileExistsError:
            if path.read_bytes() != raw:
                raise ValueError("Prime private artifact digest collision")
        else:
            directory_descriptor = os.open(directory, os.O_RDONLY)
            try:
                os.fsync(directory_descriptor)
            finally:
                os.close(directory_descriptor)
    finally:
        temporary.unlink(missing_ok=True)


def _bounded_payload(source: bytes | BinaryIO) -> tuple[bytes, bool]:
    if type(source) is bytes:
        return source[: MAX_CAPTURE_BYTES + 1], len(source) > MAX_CAPTURE_BYTES
    captured = bytearray()
    remaining = MAX_CAPTURE_BYTES + 1
    while remaining:
        chunk = source.read(min(64 * 1024, remaining))
        if not chunk:
            break
        if type(chunk) is not bytes:
            raise ValueError("Prime payload stream must produce bytes")
        captured.extend(chunk[:remaining])
        if len(chunk) > remaining:
            return bytes(captured), True
        remaining -= len(chunk)
    raw = bytes(captured)
    return raw, len(raw) > MAX_CAPTURE_BYTES


def _coded_result(code: str, digest: str, *, captured_bytes: int) -> ExecutionResult:
    digest_name = "captured_sha256" if code == "payload_oversized" else "wire_sha256"
    public = canonical_json_bytes({"schema_version": 1, "terminal": {"status": "invalid", "reason_code": code}, "wire": {digest_name: digest, "captured_bytes": captured_bytes}})
    return ExecutionResult(
        status="invalid", score_millis=None,
        detail=f"prime.{code};{digest_name}={digest};captured_bytes={captured_bytes}",
        artifact_bytes=public, cost_usd_cents=0, wall_time_ms=0, process_exit_code=None,
        structured_completion=False,
    )


def normalize_prime_payload(
    source: bytes | BinaryIO,
    *,
    private_state_dir: Path,
    expected_identity: ResolvedRuntimeIdentity,
    expected_task: TaskInstance | None = None,
    expected_run_id: str | None = None,
    expected_state: str | None = None,
) -> ExecutionResult:
    """Bound ingestion, retain raw evidence privately, and expose only allow-listed facts."""

    raw, overflow = _bounded_payload(source)
    digest = sha256_bytes(raw)
    if overflow:
        return _coded_result("payload_oversized", digest, captured_bytes=len(raw))
    _private_store(private_state_dir, raw, digest)
    try:
        wire = _record(strict_json_loads(raw), "prime")
        _exact(wire, _WIRE_KEYS, "prime")
        if wire["schema_version"] != 1:
            raise ValueError("prime.schema_version must equal 1")
        run_id = _string(wire["run_id"], "prime.run_id")
        run_id_digest = sha256_bytes(run_id.encode("utf-8"))
        provider_state = _string(wire["state"], "prime.state")
        status = terminal_status(provider_state)
        state_code = provider_state if provider_state in PRIME_TERMINAL_STATUS_MAP else "unknown"

        if expected_task is None:
            raise ValueError("Prime normalization requires the expected canonical task")
        taskset = _record(wire["taskset"], "prime.taskset")
        _exact(taskset, {"format", "digest"}, "prime.taskset")
        taskset_format = _string(taskset["format"], "prime.taskset.format")
        taskset_digest = _sha256(taskset["digest"], "prime.taskset.digest")
        wire_identity = _optional_identity_values(wire["identity"], _RUNTIME_IDENTITY_FIELDS, "prime.identity")
        locked_identity = {
            "provider": expected_identity.provider,
            "model": expected_identity.model_identifier,
            "hermes_version": expected_identity.hermes_version,
            "hermes_digest": expected_identity.hermes_digest or "",
        }
        runtime_identity_mismatches = _identity_mismatches(wire_identity, locked_identity, prefix="runtime")
        if not runtime_identity_mismatches:
            _sha256(wire_identity["hermes_digest"], "prime.identity.hermes_digest")
        locked_task = expected_task.to_dict()
        wire_task = _record(wire["task"], "prime.task")
        required_task_fields = set(locked_task) - set(_TASK_IDENTITY_FIELDS) - {"provenance"}
        if set(wire_task) - set(locked_task) or required_task_fields - set(wire_task):
            raise ValueError("prime.task does not match the canonical task shape")
        wire_task_identity = _optional_identity_values(
            {name: wire_task[name] for name in _TASK_IDENTITY_FIELDS if name in wire_task},
            _TASK_IDENTITY_FIELDS,
            "prime.task.identity",
        )
        wire_task_values = {name: str(wire_task[name]) for name in locked_task if name in wire_task}
        wire_task_values.update(wire_task_identity)
        wire_task_values.setdefault("provenance", str(locked_task["provenance"]))
        task_identity_mismatches = _identity_mismatches(
            wire_task_values,
            {name: str(locked_task[name]) for name in locked_task},
            prefix="task",
        )
        if not task_identity_mismatches:
            TaskInstance.from_dict({"provenance": locked_task["provenance"], **wire_task})

        trace = _record(wire["trace"], "prime.trace")
        _exact(trace, _TRACE_KEYS, "prime.trace")
        trace_task = _record(trace["task"], "prime.trace.task")
        _exact(trace_task, {"type", "data"}, "prime.trace.task")
        nodes = _list(trace["nodes"], "prime.trace.nodes")
        calls = _list(trace["calls"], "prime.trace.calls")
        tools = [] if trace["tools"] is None else _list(trace["tools"], "prime.trace.tools")
        errors = _list(trace["errors"], "prime.trace.errors")
        extra_usage = _list(trace["extra_usage"], "prime.trace.extra_usage")
        trace_info = _record(trace["info"], "prime.trace.info")
        trace_version = _integer(trace["version"], "prime.trace.version", minimum=1)
        is_completed = trace["is_completed"]
        if type(is_completed) is not bool:
            raise ValueError("prime.trace.is_completed must be a boolean")
        rewards = _signals(trace["rewards"], "prime.trace.rewards", _REWARD_FIELDS)
        metrics = _signals(trace["metrics"], "prime.trace.metrics", _METRIC_FIELDS)
        artifacts, artifact_bytes_count = _artifact_summaries(wire["artifacts"])
        timing, wall_time_ms = _timing_summary(trace["timing"])
        usage = _usage_summary(calls)
        cost = _record(wire["cost"], "prime.cost")
        _exact(cost, {"usd_cents"}, "prime.cost")
        cost_usd_cents = _integer(cost["usd_cents"], "prime.cost.usd_cents")
        retry_count = _integer(wire["retry_count"], "prime.retry_count")
        verifiers_info = _record(trace["verifiers"], "prime.trace.verifiers")
        verifiers_version = _string(verifiers_info["version"], "prime.trace.verifiers.version")
        if verifiers_version != PRIME_SDK_VERSION:
            raise ValueError("Prime trace reported a different Verifiers version")
        if taskset_format != PRIME_TASKSET_FORMAT:
            raise ValueError("Prime result reported a different taskset format")

        error_digests = []
        for index, error in enumerate(errors):
            error_record = _record(error, f"prime.trace.errors[{index}]")
            message = _string(error_record.get("message"), f"prime.trace.errors[{index}].message", empty=True)
            error_digests.append(sha256_bytes(message.encode("utf-8")))

        lifecycle_mismatches = []
        if expected_run_id is not None and run_id != expected_run_id:
            lifecycle_mismatches.append({"field": "lifecycle.run_id", "wire_value_digest": run_id_digest})
        if expected_state is not None and provider_state != expected_state:
            lifecycle_mismatches.append({"field": "lifecycle.state", "wire_value_digest": _untrusted_digest(provider_state)})
        identity_mismatches = lifecycle_mismatches + runtime_identity_mismatches + task_identity_mismatches
        if lifecycle_mismatches:
            status = "invalid"
            reason_code = "lifecycle_identity_mismatch"
        elif runtime_identity_mismatches:
            status = "invalid"
            reason_code = "hermes_identity_mismatch"
        elif task_identity_mismatches:
            status = "invalid"
            reason_code = "task_identity_mismatch"
        elif provider_state == "operator_cancelled":
            reason_code = "operator_cancelled"
        elif provider_state not in PRIME_TERMINAL_STATUS_MAP:
            reason_code = "unknown_provider_state"
        elif errors:
            reason_code = f"terminal_{state_code}_with_error"
        else:
            reason_code = f"terminal_{state_code}"

        public = {
            "schema_version": 1,
            "run_id_digest": run_id_digest,
            "terminal": {"provider_state_code": state_code, "status": status, "reason_code": reason_code},
            "task": locked_task,
            "taskset": {"format": PRIME_TASKSET_FORMAT, "digest": taskset_digest},
            "identity": locked_identity,
            "identity_mismatches": identity_mismatches,
            "trace": {
                "digest": sha256_bytes(canonical_json_bytes(trace)),
                "version": trace_version,
                "verifiers_version": PRIME_SDK_VERSION,
                "counts": {"nodes": len(nodes), "calls": len(calls), "tools": len(tools), "errors": len(errors), "extra_usage": len(extra_usage)},
                "channel_digests": {
                    "task_data": sha256_bytes(canonical_json_bytes(trace_task["data"])),
                    "nodes": sha256_bytes(canonical_json_bytes(nodes)),
                    "calls": sha256_bytes(canonical_json_bytes(calls)),
                    "tools": sha256_bytes(canonical_json_bytes(tools)),
                    "info": sha256_bytes(canonical_json_bytes(trace_info)),
                    "errors": sha256_bytes(canonical_json_bytes(errors)),
                    "reproduction": sha256_bytes(canonical_json_bytes(trace_info.get("reproduction"))),
                    "evidence": sha256_bytes(canonical_json_bytes(trace_info.get("evidence"))),
                },
                "is_completed": is_completed,
                "rewards": rewards,
                "metrics": metrics,
                "usage": usage,
                "timing": timing,
                "error_message_digests": error_digests,
            },
            "artifacts": {"count": len(artifacts), "bytes": artifact_bytes_count, "items": artifacts},
            "cost": {"usd_cents": cost_usd_cents},
            "wire": {"sha256": digest, "bytes": len(raw)},
        }
        artifact_bytes = canonical_json_bytes(public)
        if len(artifact_bytes) > MAX_CAPTURE_BYTES:
            raise ValueError("Prime public evidence exceeds the 4MiB capture limit")
        score_millis = sum(signal["value_millis"] for signal in rewards) if status == "completed" else None
        mismatch_digests = ",".join(value["wire_value_digest"] for value in identity_mismatches)
        mismatch_detail = f";identity_mismatch_digests={mismatch_digests}" if mismatch_digests else ""
        detail = f"prime.{reason_code};wire_sha256={digest};errors={len(errors)};artifacts={len(artifacts)}{mismatch_detail}"
        return ExecutionResult(
            status=status,
            score_millis=score_millis,
            detail=detail,
            artifact_bytes=artifact_bytes,
            cost_usd_cents=cost_usd_cents,
            wall_time_ms=wall_time_ms,
            process_exit_code=None,
            provider_facts=(
                ("reported_provider", locked_identity["provider"]),
                ("reported_model", locked_identity["model"]),
                ("reported_hermes_version", locked_identity["hermes_version"]),
                ("reported_hermes_digest", locked_identity["hermes_digest"]),
            ),
            runtime_facts=(
                ("prime_run_id_digest", run_id_digest),
                ("prime_state_code", state_code),
                ("prime_state_digest", sha256_bytes(provider_state.encode("utf-8"))),
                ("taskset_format", public["taskset"]["format"]),
                ("trace_version", str(public["trace"]["version"])),
                ("verifiers_version", verifiers_version),
                ("private_wire_digest", digest),
            ) + tuple(
                (f"{mismatch['field'].replace('.', '_')}_wire_value_digest", mismatch["wire_value_digest"])
                for mismatch in identity_mismatches
            ),
            tool_facts=(("advertised_tool_count", str(len(tools))),),
            retry_count=retry_count,
        )
    except (KeyError, TypeError, ValueError, UnicodeDecodeError, OverflowError, RecursionError):
        return _coded_result("payload_invalid", digest, captured_bytes=len(raw))
