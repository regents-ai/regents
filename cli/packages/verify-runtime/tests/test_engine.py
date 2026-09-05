from __future__ import annotations

import json
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event

import pytest

from verify_runtime.model import EvaluationReceipt, canonical_json_bytes
from verify_runtime.receipts import show_receipt
from verify_runtime.runner import ComparisonBusyError, ComparisonSpendExhaustedError, FixtureExecutor, run_builtin_comparison, show_comparison_status
from verify_runtime.runner.executors import ExecutionResult


def test_offline_builtin_e2e_completes_with_a_verified_receipt_set_under_two_minutes(tmp_path: Path) -> None:
    started = time.monotonic()
    result = run_builtin_comparison(tmp_path, FixtureExecutor())
    elapsed = time.monotonic() - started

    assert elapsed <= 120
    assert result["status"] == "completed"
    assert result["summary"] == {
        "comparison_result": "positive",
        "baseline_completed": 11,
        "candidate_completed": 11,
        "task_count": 11,
        "total_cost_usd_cents": 0,
    }
    assert len(result["receipts"]) == 11
    for pointer in result["receipts"]:
        shown = show_receipt(tmp_path, pointer["digest"])
        assert shown["verified"] is True
        receipt = EvaluationReceipt.from_dict(shown["receipt"])
        assert receipt.baseline_run.task_id == receipt.candidate_run.task_id
        assert receipt.protocol.policy.infrastructure_failure_treatment.endswith("not-scored")
        assert receipt.baseline_capsule.resolved.provider == "fixture"
        assert dict(receipt.baseline_capsule.observed.provider_facts) == {
            "reported_provider": "fixture",
            "reported_model": "contract-drift-fixture-v1",
        }
        assert "wall_time_ms" in dict(receipt.baseline_capsule.observed.runtime_facts)
        assert dict(receipt.baseline_capsule.observed.tool_facts)["network"] == "disabled"


def test_status_reads_without_mutating_state(tmp_path: Path) -> None:
    result = run_builtin_comparison(tmp_path, FixtureExecutor())
    path = tmp_path / "verify" / "comparisons" / f"{result['comparison_id']}.json"
    before = path.read_bytes()
    assert show_comparison_status(tmp_path, result["comparison_id"]) == result
    assert path.read_bytes() == before


def test_fixture_receipts_keep_deterministic_evidence_with_distinct_store_bindings(tmp_path: Path) -> None:
    first = run_builtin_comparison(tmp_path / "first", FixtureExecutor())
    second = run_builtin_comparison(tmp_path / "second", FixtureExecutor())
    first_records = [json.loads(Path(pointer["path"]).read_bytes()) for pointer in first["receipts"]]
    second_records = [json.loads(Path(pointer["path"]).read_bytes()) for pointer in second["receipts"]]
    assert [pointer["digest"] for pointer in first["receipts"]] != [pointer["digest"] for pointer in second["receipts"]]
    assert {record.pop("store_id") for record in first_records} != {record.pop("store_id") for record in second_records}
    assert first_records == second_records


@pytest.mark.parametrize("status", ["timeout", "invalid", "agent_failure", "infrastructure_failure"])
def test_terminal_fixture_outcomes_remain_distinct_and_unscored(tmp_path: Path, status: str) -> None:
    result = run_builtin_comparison(tmp_path, FixtureExecutor(status))  # type: ignore[arg-type]
    assert result["status"] == status
    shown = show_receipt(tmp_path, result["receipts"][0]["digest"])
    receipt = shown["receipt"]
    assert receipt["runs"]["baseline"]["status"] == status
    assert receipt["runs"]["baseline"]["outcome"]["score_millis"] is None
    assert receipt["outcome"]["comparison_result"] == status


class ExpensiveExecutor:
    name = "fixture-expensive"

    def __init__(self) -> None:
        self.allowances: list[int] = []

    def resolve_identity(self):
        return FixtureExecutor().resolve_identity()

    def execute(self, *, side: str, task_id: str, workspace: Path, timeout_seconds: int, max_spend_usd_cents: int) -> ExecutionResult:
        del side, task_id, workspace, timeout_seconds
        self.allowances.append(max_spend_usd_cents)
        return ExecutionResult("completed", 1, "completed before budget accounting", b"{}\n", 600, 1, 0)


def test_budget_guard_halts_and_uses_infrastructure_status(tmp_path: Path) -> None:
    executor = ExpensiveExecutor()
    result = run_builtin_comparison(tmp_path, executor)
    assert result["status"] == "infrastructure_failure"
    assert len(result["receipts"]) == 1
    assert executor.allowances == [1_000, 400]
    assert result["summary"]["total_cost_usd_cents"] <= 1_000
    shown = show_receipt(tmp_path, result["receipts"][0]["digest"])
    assert shown["receipt"]["runs"]["candidate"]["status"] == "infrastructure_failure"
    assert shown["receipt"]["runs"]["candidate"]["outcome"]["score_millis"] is None
    ledger_path = next((tmp_path / "verify" / "comparisons").glob("*.spend.json"))
    assert json.loads(ledger_path.read_bytes())["spent_usd_cents"] == 1_000
    with pytest.raises(ComparisonSpendExhaustedError, match="allowance is exhausted"):
        run_builtin_comparison(tmp_path, executor)
    assert executor.allowances == [1_000, 400]


class BlockingExecutor:
    name = "fixture-blocking"

    def __init__(self, entered: Event, release: Event) -> None:
        self.entered = entered
        self.release = release

    def resolve_identity(self):
        return FixtureExecutor().resolve_identity()

    def execute(self, *, side: str, task_id: str, workspace: Path, timeout_seconds: int, max_spend_usd_cents: int) -> ExecutionResult:
        del side, task_id, workspace, timeout_seconds, max_spend_usd_cents
        self.entered.set()
        assert self.release.wait(timeout=5)
        return ExecutionResult("completed", 1, "released", b"{}\n", 0, 1, 0)


def test_concurrent_comparison_fails_fast_as_busy(tmp_path: Path) -> None:
    entered = Event()
    release = Event()
    executor = BlockingExecutor(entered, release)
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(run_builtin_comparison, tmp_path, executor)
        assert entered.wait(timeout=5)
        with pytest.raises(ComparisonBusyError, match="already running"):
            run_builtin_comparison(tmp_path, executor)
        release.set()
        assert first.result(timeout=5)["status"] == "completed"


def test_deleting_lock_metadata_cannot_admit_a_second_invocation(tmp_path: Path) -> None:
    entered = Event()
    release = Event()
    executor = BlockingExecutor(entered, release)
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(run_builtin_comparison, tmp_path, executor)
        assert entered.wait(timeout=5)
        lock_path = next((tmp_path / "verify" / "comparisons").glob("*.lock"))
        owner = json.loads(lock_path.read_bytes())
        assert owner["pid"] > 0
        assert len(owner["nonce"]) == 32
        lock_path.unlink()
        with pytest.raises(ComparisonBusyError, match="Operator recovery"):
            run_builtin_comparison(tmp_path, executor)
        replacement_owner = owner | {"nonce": "replacement-owner"}
        lock_path.write_bytes(canonical_json_bytes(replacement_owner))
        release.set()
        assert first.result(timeout=5)["status"] == "completed"
        assert json.loads(lock_path.read_bytes()) == replacement_owner


class SimulatedProcessCrash(BaseException):
    pass


class CrashAfterReservationExecutor:
    name = "crash-after-reservation"

    def __init__(self, state_dir: Path) -> None:
        self.state_dir = state_dir

    def resolve_identity(self):
        return FixtureExecutor().resolve_identity()

    def execute(self, **kwargs):
        del kwargs
        ledger_path = next((self.state_dir / "verify" / "comparisons").glob("*.spend.json"))
        assert json.loads(ledger_path.read_bytes())["spent_usd_cents"] == 1_000
        raise SimulatedProcessCrash()


def test_reservation_is_persisted_before_launch_and_survives_process_crash(tmp_path: Path) -> None:
    executor = CrashAfterReservationExecutor(tmp_path)
    with pytest.raises(SimulatedProcessCrash):
        run_builtin_comparison(tmp_path, executor)
    ledger_path = next((tmp_path / "verify" / "comparisons").glob("*.spend.json"))
    assert json.loads(ledger_path.read_bytes())["spent_usd_cents"] == 1_000
    with pytest.raises(ComparisonSpendExhaustedError, match="allowance is exhausted"):
        run_builtin_comparison(tmp_path, executor)


def test_unstructured_executor_death_consumes_the_full_reservation(tmp_path: Path) -> None:
    class DyingExecutor:
        name = "unstructured-death"

        def resolve_identity(self):
            return FixtureExecutor().resolve_identity()

        def execute(self, **kwargs):
            del kwargs
            raise RuntimeError("child died without a structured result")

    result = run_builtin_comparison(tmp_path, DyingExecutor())
    assert result["status"] == "infrastructure_failure"
    assert result["summary"]["total_cost_usd_cents"] == 1_000
    assert result["receipts"]
    with pytest.raises(ComparisonSpendExhaustedError, match="allowance is exhausted"):
        run_builtin_comparison(tmp_path, DyingExecutor())


@pytest.mark.parametrize(
    ("raised", "expected_status"),
    [(ValueError("bad parse"), "invalid"), (RuntimeError("substrate"), "infrastructure_failure")],
)
def test_executor_exceptions_are_receipted(tmp_path: Path, raised: Exception, expected_status: str) -> None:
    class RaisingExecutor:
        name = f"raising-{expected_status}"

        def resolve_identity(self):
            return FixtureExecutor().resolve_identity()

        def execute(self, **kwargs):
            del kwargs
            raise raised

    result = run_builtin_comparison(tmp_path, RaisingExecutor())
    assert result["status"] == expected_status
    assert result["receipts"]


class MissingScoreExecutor:
    name = "missing-score"

    def resolve_identity(self):
        return FixtureExecutor().resolve_identity()

    def execute(self, *, side: str, task_id: str, workspace: Path, timeout_seconds: int, max_spend_usd_cents: int) -> ExecutionResult:
        del side, task_id, workspace, timeout_seconds, max_spend_usd_cents
        artifact = b'{"status":"completed","score_millis":null,"cost_usd_cents":0,"detail":"accepted executor response with no score"}\n'
        return ExecutionResult("completed", None, "accepted executor response with no score", artifact, 0, 1, 0)


def test_completed_null_score_applies_locked_invalid_policy_and_emits_receipt(tmp_path: Path) -> None:
    result = run_builtin_comparison(tmp_path, MissingScoreExecutor())
    assert result["status"] == "invalid"
    assert result["receipts"]
    receipt = show_receipt(tmp_path, result["receipts"][0]["digest"])["receipt"]
    assert receipt["runs"]["baseline"]["status"] == "invalid"
    assert receipt["runs"]["baseline"]["outcome"]["score_millis"] is None
    assert "terminal-invalid-not-scored" in receipt["runs"]["baseline"]["outcome"]["detail"]


def test_immutable_receipt_collision_is_rejected(tmp_path: Path) -> None:
    result = run_builtin_comparison(tmp_path, FixtureExecutor())
    pointer = result["receipts"][0]
    path = Path(pointer["path"])
    path.write_bytes(canonical_json_bytes({"tampered": True}))
    with pytest.raises(RuntimeError, match="immutable receipt collision"):
        run_builtin_comparison(tmp_path, FixtureExecutor())


def test_receipt_show_rejects_tampering(tmp_path: Path) -> None:
    result = run_builtin_comparison(tmp_path, FixtureExecutor())
    pointer = result["receipts"][0]
    Path(pointer["path"]).write_bytes(json.dumps({"tampered": True}).encode())
    with pytest.raises(ValueError, match="digest mismatch"):
        show_receipt(tmp_path, pointer["digest"])
