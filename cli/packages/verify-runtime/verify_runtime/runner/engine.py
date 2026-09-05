"""Portable local Verify comparison engine."""

from __future__ import annotations

import fcntl
import os
import secrets
import tempfile
import time
from contextlib import contextmanager
from dataclasses import replace
from pathlib import Path
from typing import Any, Iterator

from verify_runtime.capsule import declared_capsule, resolve_capsule
from verify_runtime.capsule.resolution import ResolvedRuntimeIdentity, with_observed_execution
from verify_runtime.families import BASELINE_SKILL, CANDIDATE_SKILL, FAMILY, TASKS
from verify_runtime.model import TERMINAL_STATUSES, EvaluationReceipt, RunRecord, TerminalStatus, canonical_json_bytes, content_id, strict_json_loads
from verify_runtime.protocol import lock_builtin_protocol
from verify_runtime.receipts._store import _emit_receipt, _receipt_store_id

from .executors import MAX_CAPTURE_BYTES, MAX_DETAIL_CHARACTERS, MAX_FACTS, MAX_FACT_CHARACTERS, MAX_RESULT_INTEGER, ExecutionResult, Executor, FixtureExecutor, artifact_record

_SPEND_VIOLATION = "executor violated the hard remaining spend allowance"
_CAP_EXHAUSTED_BEFORE_LAUNCH = "comparison spend reached the locked cap before launch"


class ComparisonBusyError(RuntimeError):
    """The deterministic comparison already has an active writer."""


class ComparisonSpendExhaustedError(RuntimeError):
    """The deterministic comparison has no persisted spend allowance left."""


class ComparisonStateError(RuntimeError):
    """Persisted comparison accounting failed integrity validation."""


def _task(task_id: str):
    return next(task for task in TASKS if task.task_id == task_id)


def _comparison_directory(state_dir: Path) -> Path:
    return state_dir / "verify" / "comparisons"


@contextmanager
def _comparison_lock(state_dir: Path, comparison_id: str) -> Iterator[Path]:
    directory = _comparison_directory(state_dir)
    directory.mkdir(parents=True, exist_ok=True)
    anchor = directory / ".locks" / comparison_id
    anchor.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(anchor, os.O_RDONLY)
    lock_path = directory / f"{comparison_id}.lock"
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        os.close(descriptor)
        raise ComparisonBusyError(
            f"comparison is already running: {comparison_id}. "
            f"Operator recovery: inspect {lock_path} for the recorded pid and nonce, then wait for or terminate "
            "the owning invocation; deleting the lock file does not release the held lock"
        ) from error
    nonce = secrets.token_hex(16)
    owner = {"schema_version": 1, "comparison_id": comparison_id, "pid": os.getpid(), "nonce": nonce}
    try:
        lock_path.write_bytes(canonical_json_bytes(owner))
        yield directory
    finally:
        try:
            recorded_owner = strict_json_loads(lock_path.read_bytes())
        except (OSError, ValueError, MemoryError, RecursionError):
            recorded_owner = None
        if type(recorded_owner) is dict and recorded_owner.get("nonce") == nonce:
            lock_path.unlink(missing_ok=True)
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def _ledger_path(directory: Path, comparison_id: str) -> Path:
    return directory / f"{comparison_id}.spend.json"


def _read_spent(directory: Path, comparison_id: str, cap: int) -> int:
    path = _ledger_path(directory, comparison_id)
    try:
        value = strict_json_loads(path.read_bytes())
    except FileNotFoundError:
        return 0
    except (OSError, UnicodeDecodeError, ValueError, MemoryError, RecursionError) as error:
        raise ComparisonStateError(f"comparison spend ledger is unreadable: {comparison_id}") from error
    if type(value) is not dict or set(value) != {"schema_version", "comparison_id", "spent_usd_cents"}:
        raise ComparisonStateError(f"comparison spend ledger has an invalid shape: {comparison_id}")
    spent = value["spent_usd_cents"]
    if value["schema_version"] != 1 or value["comparison_id"] != comparison_id or type(spent) is not int or isinstance(spent, bool) or not 0 <= spent <= cap:
        raise ComparisonStateError(f"comparison spend ledger has invalid values: {comparison_id}")
    return spent


def _write_spent(directory: Path, comparison_id: str, spent: int) -> None:
    path = _ledger_path(directory, comparison_id)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{comparison_id}.spend.", dir=directory)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes({"schema_version": 1, "comparison_id": comparison_id, "spent_usd_cents": spent}))
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
        directory_descriptor = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        temporary.unlink(missing_ok=True)


def _remaining_allowance(directory: Path, comparison_id: str, cap: int) -> int:
    return cap - _read_spent(directory, comparison_id, cap)


def _reserve_allowance(directory: Path, comparison_id: str, cap: int) -> tuple[int, int]:
    spent = _read_spent(directory, comparison_id, cap)
    allowance = cap - spent
    if allowance <= 0:
        raise ComparisonSpendExhaustedError(f"comparison spend allowance is exhausted: {comparison_id}")
    _write_spent(directory, comparison_id, cap)
    return spent, allowance


def _reconcile_reservation(directory: Path, comparison_id: str, spent_before: int, result: ExecutionResult) -> None:
    if result.structured_completion:
        _write_spent(directory, comparison_id, spent_before + result.cost_usd_cents)


def _fact_records_are_valid(facts: object) -> bool:
    if type(facts) is not tuple or len(facts) > MAX_FACTS:
        return False
    valid = all(
        type(fact) is tuple
        and len(fact) == 2
        and type(fact[0]) is str
        and type(fact[1]) is str
        and 0 < len(fact[0]) <= MAX_FACT_CHARACTERS
        and len(fact[1]) <= MAX_FACT_CHARACTERS
        for fact in facts
    )
    return valid and len({fact[0] for fact in facts}) == len(facts)


def _sanitize_text(value: str) -> str:
    return value.encode("utf-8", "replace").decode("utf-8")


def _sanitize_facts(facts: tuple[tuple[str, str], ...]) -> tuple[tuple[str, str], ...]:
    sanitized = tuple((_sanitize_text(name), _sanitize_text(value)) for name, value in facts)
    if len({name for name, _ in sanitized}) != len(sanitized):
        raise ValueError("executor returned duplicate observed facts after sanitization")
    return sanitized


def _validated_result(value: object) -> ExecutionResult:
    if type(value) is not ExecutionResult:
        raise TypeError("executor did not return an ExecutionResult")
    if type(value.status) is not str or value.status not in TERMINAL_STATUSES:
        raise ValueError("executor returned an invalid terminal status")
    if value.score_millis is not None and (type(value.score_millis) is not int or isinstance(value.score_millis, bool) or abs(value.score_millis) > MAX_RESULT_INTEGER):
        raise ValueError("executor returned an invalid score")
    if type(value.cost_usd_cents) is not int or isinstance(value.cost_usd_cents, bool) or not 0 <= value.cost_usd_cents <= MAX_RESULT_INTEGER:
        raise ValueError("executor returned an invalid cost")
    if type(value.wall_time_ms) is not int or isinstance(value.wall_time_ms, bool) or not 0 <= value.wall_time_ms <= MAX_RESULT_INTEGER:
        raise ValueError("executor returned an invalid wall time")
    if value.process_exit_code is not None and (type(value.process_exit_code) is not int or isinstance(value.process_exit_code, bool) or abs(value.process_exit_code) > MAX_RESULT_INTEGER):
        raise ValueError("executor returned an invalid process exit code")
    if type(value.detail) is not str or len(value.detail) > MAX_DETAIL_CHARACTERS:
        raise ValueError("executor returned invalid detail")
    if type(value.artifact_bytes) is not bytes or len(value.artifact_bytes) > MAX_CAPTURE_BYTES:
        raise ValueError("executor returned an oversized or invalid artifact")
    if not _fact_records_are_valid(value.provider_facts) or not _fact_records_are_valid(value.runtime_facts) or not _fact_records_are_valid(value.tool_facts):
        raise ValueError("executor returned invalid observed facts")
    if type(value.retry_count) is not int or isinstance(value.retry_count, bool) or not 0 <= value.retry_count <= MAX_RESULT_INTEGER:
        raise ValueError("executor returned an invalid retry count")
    if type(value.structured_completion) is not bool:
        raise ValueError("executor returned an invalid completion classification")
    return replace(
        value,
        detail=_sanitize_text(value.detail),
        provider_facts=_sanitize_facts(value.provider_facts),
        runtime_facts=_sanitize_facts(value.runtime_facts),
        tool_facts=_sanitize_facts(value.tool_facts),
    )


def _execution_failure(status: TerminalStatus, detail: str) -> ExecutionResult:
    return ExecutionResult(
        status=status,
        score_millis=None,
        detail=detail,
        artifact_bytes=b"",
        cost_usd_cents=0,
        wall_time_ms=0,
        process_exit_code=None,
        structured_completion=False,
    )


def _normalize_result(result: ExecutionResult, *, timeout_seconds: int, observed_wall_ms: int, max_spend_usd_cents: int) -> ExecutionResult:
    wall_time_ms = result.wall_time_ms if result.wall_time_ms > 0 else observed_wall_ms
    normalized = replace(result, wall_time_ms=wall_time_ms)
    if wall_time_ms > timeout_seconds * 1_000 and normalized.status != "timeout":
        normalized = replace(normalized, status="timeout", score_millis=None, detail="task exceeded the locked wall cap")
    if normalized.status == "completed" and normalized.score_millis is None:
        normalized = replace(normalized, status="invalid", detail="completed result omitted a score; terminal-invalid-not-scored policy applied")
    elif normalized.status != "completed" and normalized.score_millis is not None:
        normalized = replace(normalized, score_millis=None)
    if normalized.cost_usd_cents > max_spend_usd_cents:
        normalized = replace(
            normalized,
            status="infrastructure_failure",
            score_millis=None,
            detail=f"{_SPEND_VIOLATION}: reported {normalized.cost_usd_cents} cents above ceiling {max_spend_usd_cents}",
            cost_usd_cents=max_spend_usd_cents,
            runtime_facts=(*normalized.runtime_facts, ("reported_cost_usd_cents", str(normalized.cost_usd_cents)), ("spend_ceiling_usd_cents", str(max_spend_usd_cents))),
            spend_violation=True,
        )
    return normalized


def _enforce_matched_identity(
    result: ExecutionResult,
    *,
    executor: Executor,
    identity: ResolvedRuntimeIdentity,
) -> ExecutionResult:
    facts = dict(result.provider_facts)
    provider = facts.get("reported_provider")
    model = facts.get("reported_model")
    identity_required = result.structured_completion and bool(getattr(executor, "supplies_observed_identity", False))
    identity_incomplete = (provider is None) != (model is None)
    identity_mismatch = provider is not None and (provider != identity.provider or model != identity.model_identifier)
    if identity_incomplete or identity_mismatch or (identity_required and provider is None):
        return replace(
            result,
            status="invalid",
            score_millis=None,
            detail="matched-comparison violation: observed provider/model did not match the resolved capsule identity",
        )
    return result


def _run_one(
    *,
    state_dir: Path,
    executor: Executor,
    protocol_id: str,
    capsule_id: str,
    side: str,
    task_id: str,
    provenance: str,
    skill_bytes: bytes,
    timeout_seconds: int,
    max_spend_usd_cents: int,
    runtime_identity: ResolvedRuntimeIdentity,
) -> tuple[RunRecord, ExecutionResult]:
    if max_spend_usd_cents <= 0:
        result = ExecutionResult(status="infrastructure_failure", score_millis=None, detail=_CAP_EXHAUSTED_BEFORE_LAUNCH, artifact_bytes=b"", cost_usd_cents=0, wall_time_ms=0, process_exit_code=None)
    else:
        workspace_root = state_dir / "verify" / "workspaces"
        workspace_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="run-", dir=workspace_root) as temporary:
            workspace = Path(temporary)
            (workspace / "SKILL.md").write_bytes(skill_bytes)
            (workspace / "task.json").write_bytes(canonical_json_bytes(_task(task_id).to_dict()))
            started = time.monotonic_ns()
            try:
                result = _validated_result(executor.execute(
                    side=side,
                    task_id=task_id,
                    workspace=workspace,
                    timeout_seconds=timeout_seconds,
                    max_spend_usd_cents=max_spend_usd_cents,
                ))
            except (TypeError, ValueError, OverflowError, RecursionError):
                result = _execution_failure("invalid", "executor result parsing or validation failed")
            except Exception:
                result = _execution_failure("infrastructure_failure", "executor failed unexpectedly before producing a valid result")
            observed_wall_ms = max(0, (time.monotonic_ns() - started) // 1_000_000)
        result = _normalize_result(
            result,
            timeout_seconds=timeout_seconds,
            observed_wall_ms=observed_wall_ms,
            max_spend_usd_cents=max_spend_usd_cents,
        )
        result = _enforce_matched_identity(result, executor=executor, identity=runtime_identity)
    artifacts = artifact_record(result)
    run = RunRecord(
        schema_version=1,
        run_id="",
        protocol_id=protocol_id,
        capsule_id=capsule_id,
        side=side,
        task_id=task_id,
        provenance=provenance,  # type: ignore[arg-type]
        attempt=1,
        status=result.status,
        score_millis=result.score_millis,
        detail=result.detail,
        artifacts=artifacts,
        cost_usd_cents=result.cost_usd_cents,
        wall_time_ms=result.wall_time_ms,
        executor=executor.name,
        process_exit_code=result.process_exit_code,
        possible_contamination="possible-contamination" if provenance == "public_reference" else None,
    )
    run = replace(run, run_id=run.expected_run_id())
    return RunRecord.from_dict(run.to_dict()), result


def _run_reserved(
    *,
    comparison_directory: Path,
    comparison_id: str,
    cap: int,
    state_dir: Path,
    executor: Executor,
    protocol_id: str,
    capsule_id: str,
    side: str,
    task_id: str,
    provenance: str,
    skill_bytes: bytes,
    timeout_seconds: int,
    runtime_identity: ResolvedRuntimeIdentity,
) -> tuple[RunRecord, ExecutionResult]:
    try:
        spent_before, allowance = _reserve_allowance(comparison_directory, comparison_id, cap)
    except ComparisonSpendExhaustedError:
        return _run_one(
            state_dir=state_dir,
            executor=executor,
            protocol_id=protocol_id,
            capsule_id=capsule_id,
            side=side,
            task_id=task_id,
            provenance=provenance,
            skill_bytes=skill_bytes,
            timeout_seconds=timeout_seconds,
            max_spend_usd_cents=0,
            runtime_identity=runtime_identity,
        )
    run, result = _run_one(
        state_dir=state_dir,
        executor=executor,
        protocol_id=protocol_id,
        capsule_id=capsule_id,
        side=side,
        task_id=task_id,
        provenance=provenance,
        skill_bytes=skill_bytes,
        timeout_seconds=timeout_seconds,
        max_spend_usd_cents=allowance,
        runtime_identity=runtime_identity,
    )
    _reconcile_reservation(comparison_directory, comparison_id, spent_before, result)
    return run, result


def _comparison_result(baseline: RunRecord, candidate: RunRecord) -> str:
    if baseline.status != "completed":
        return baseline.status
    if candidate.status != "completed":
        return candidate.status
    if baseline.score_millis is None or candidate.score_millis is None:
        return "invalid"
    if candidate.score_millis > baseline.score_millis:
        return "positive"
    if candidate.score_millis < baseline.score_millis:
        return "negative"
    return "null"


def _comparison_status(runs: list[RunRecord]) -> str:
    launched_runs = [run for run in runs if run.detail != _CAP_EXHAUSTED_BEFORE_LAUNCH]
    considered_runs = launched_runs or runs
    for status in ("infrastructure_failure", "timeout", "invalid", "agent_failure"):
        if any(run.status == status for run in considered_runs):
            return status
    return "completed"


def _write_status(state_dir: Path, comparison_id: str, value: dict[str, Any]) -> None:
    directory = _comparison_directory(state_dir)
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / f"{comparison_id}.json"
    temporary = directory / f".{comparison_id}.tmp"
    temporary.write_bytes(canonical_json_bytes(value))
    temporary.replace(target)


def _observed_capsule(capsule, executor: Executor, result: ExecutionResult):
    return with_observed_execution(
        capsule,
        executor=executor.name,
        status=result.status,
        provider_facts=result.provider_facts,
        runtime_facts=(*result.runtime_facts, ("wall_time_ms", str(result.wall_time_ms))),
        tool_facts=result.tool_facts,
        retry_count=result.retry_count,
    )


def run_builtin_comparison(state_dir: Path, executor: Executor | None = None) -> dict[str, Any]:
    selected_executor = executor or FixtureExecutor()
    runtime_identity = selected_executor.resolve_identity()
    baseline = resolve_capsule(
        declared_capsule("builtin://baseline/SKILL.md", executor=selected_executor.name),
        BASELINE_SKILL,
        identity=runtime_identity,
    )
    candidate = resolve_capsule(
        declared_capsule("builtin://candidate/SKILL.md", executor=selected_executor.name),
        CANDIDATE_SKILL,
        identity=runtime_identity,
    )
    protocol = lock_builtin_protocol(baseline, candidate)
    store_id = _receipt_store_id(state_dir)
    comparison_id = content_id("comparison", {"protocol_id": protocol.protocol_id, "executor": selected_executor.name})
    cap = protocol.policy.max_comparison_spend_usd_cents
    with _comparison_lock(state_dir, comparison_id) as comparison_directory:
        if _remaining_allowance(comparison_directory, comparison_id, cap) <= 0:
            raise ComparisonSpendExhaustedError(f"comparison spend allowance is exhausted: {comparison_id}")

        runs: list[RunRecord] = []
        receipt_pointers: list[dict[str, Any]] = []
        receipt_results: list[str] = []

        for selection in protocol.selections:
            baseline_run, baseline_result = _run_reserved(comparison_directory=comparison_directory, comparison_id=comparison_id, cap=cap, state_dir=state_dir, executor=selected_executor, protocol_id=protocol.protocol_id, capsule_id=baseline.capsule_id, side="baseline", task_id=selection.task_id, provenance=selection.provenance, skill_bytes=BASELINE_SKILL, timeout_seconds=protocol.policy.max_task_wall_seconds, runtime_identity=runtime_identity)
            candidate_run, candidate_result = _run_reserved(comparison_directory=comparison_directory, comparison_id=comparison_id, cap=cap, state_dir=state_dir, executor=selected_executor, protocol_id=protocol.protocol_id, capsule_id=candidate.capsule_id, side="candidate", task_id=selection.task_id, provenance=selection.provenance, skill_bytes=CANDIDATE_SKILL, timeout_seconds=protocol.policy.max_task_wall_seconds, runtime_identity=runtime_identity)

            runs.extend((baseline_run, candidate_run))
            receipt_identity = {"protocol_id": protocol.protocol_id, "task_id": selection.task_id}
            receipt = EvaluationReceipt(
                schema_version=1,
                store_id=store_id,
                receipt_id=content_id("receipt", receipt_identity),
                task_id=selection.task_id,
                protocol=protocol,
                baseline_capsule=_observed_capsule(baseline, selected_executor, baseline_result),
                candidate_capsule=_observed_capsule(candidate, selected_executor, candidate_result),
                baseline_run=baseline_run,
                candidate_run=candidate_run,
                comparison_result=_comparison_result(baseline_run, candidate_run),
                baseline_score_millis=baseline_run.score_millis,
                candidate_score_millis=candidate_run.score_millis,
                total_cost_usd_cents=baseline_run.cost_usd_cents + candidate_run.cost_usd_cents,
                baseline_run_digest=baseline_run.content_digest(),
                candidate_run_digest=candidate_run.content_digest(),
            )
            receipt_pointers.append(_emit_receipt(state_dir, receipt))
            receipt_results.append(receipt.comparison_result)
            if baseline_result.spend_violation or candidate_result.spend_violation or _remaining_allowance(comparison_directory, comparison_id, cap) <= 0:
                break

        status = _comparison_status(runs)
        completed_result = receipt_results[0] if receipt_results and all(result == receipt_results[0] for result in receipt_results) else "mixed"
        summary = {
            "comparison_result": completed_result if status == "completed" else status,
            "baseline_completed": sum(run.status == "completed" for run in runs if run.side == "baseline"),
            "candidate_completed": sum(run.status == "completed" for run in runs if run.side == "candidate"),
            "task_count": len(protocol.selections),
            "total_cost_usd_cents": _read_spent(comparison_directory, comparison_id, cap),
        }
        result = {
            "schema_version": 1,
            "comparison_id": comparison_id,
            "status": status,
            "family_id": FAMILY.family_id,
            "protocol_id": protocol.protocol_id,
            "capsule_ids": {"baseline": baseline.capsule_id, "candidate": candidate.capsule_id},
            "run_ids": [run.run_id for run in runs],
            "receipts": receipt_pointers,
            "summary": summary,
            "policy": protocol.policy.to_dict(),
        }
        _write_status(state_dir, comparison_id, result)
        return result


def show_comparison_status(state_dir: Path, comparison_id: str) -> dict[str, Any]:
    if not comparison_id or any(character not in "abcdefghijklmnopqrstuvwxyz0123456789-" for character in comparison_id):
        raise ValueError("comparison_id has an invalid format")
    path = state_dir / "verify" / "comparisons" / f"{comparison_id}.json"
    if not path.is_file():
        raise FileNotFoundError(f"comparison not found: {comparison_id}")
    value = strict_json_loads(path.read_bytes())
    if type(value) is not dict or value.get("comparison_id") != comparison_id:
        raise ValueError("comparison state is invalid")
    return value
