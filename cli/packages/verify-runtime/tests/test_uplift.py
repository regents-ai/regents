from __future__ import annotations

import json
import os
import shutil
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from pathlib import Path
from threading import Barrier

import pytest
import verify_runtime.receipts as receipts_api
import verify_runtime.receipts.store as public_receipt_store
import verify_runtime.uplift.store as uplift_store

from verify_runtime.model import (
    ArmIdentity,
    DecisionRule,
    EvaluationReceipt,
    EvaluationProtocol,
    ModelValidationError,
    ReproductionPackage,
    UpliftReport,
    content_id,
    sha256_bytes,
    canonical_json_bytes,
    render_decision_sentence,
)
from verify_runtime.receipts import show_receipt
from verify_runtime.receipts._store import _emit_receipt
from verify_runtime.runner import FixtureExecutor, run_builtin_comparison
from verify_runtime.uplift import (
    UpliftInputError,
    UpliftReportConflictError,
    UpliftReceiptNotFound,
    compare_receipts,
    generate_uplift_report,
    show_reproduction_package,
)


def _source_receipts(state_dir: Path) -> tuple[EvaluationReceipt, ...]:
    comparison = run_builtin_comparison(state_dir, FixtureExecutor())
    return tuple(
        EvaluationReceipt.from_dict(show_receipt(state_dir, pointer["digest"])["receipt"])
        for pointer in comparison["receipts"]
    )


def _comparison_result(baseline_status: str, candidate_status: str, baseline_score: int | None, candidate_score: int | None) -> str:
    if baseline_status != "completed":
        return baseline_status
    if candidate_status != "completed":
        return candidate_status
    if baseline_score is None or candidate_score is None:
        return "invalid"
    return "positive" if candidate_score > baseline_score else "negative" if candidate_score < baseline_score else "null"


def _receipt_set(
    state_dir: Path,
    *,
    validation_scores: tuple[int | None, int | None] = (0, 1_000),
    validation_statuses: tuple[str, str] = ("completed", "completed"),
    threshold: int | None = None,
    provenance: str | None = None,
    decision_rule: DecisionRule | None = None,
    archive: bool = True,
) -> tuple[str, ...]:
    source = _source_receipts(state_dir)
    source_protocol = source[0].protocol
    protocol = source_protocol
    if threshold is not None:
        decision_rule = replace(source_protocol.decision_rule, positive_threshold_millis=threshold, negative_threshold_millis=-threshold)
    if decision_rule is not None or provenance is not None:
        selections = tuple(replace(selection, provenance=provenance) if provenance is not None else selection for selection in source_protocol.selections)
        protocol = replace(
            source_protocol,
            protocol_id="pending",
            selections=selections,
            decision_rule=decision_rule if decision_rule is not None else source_protocol.decision_rule,
        )
        protocol = replace(protocol, protocol_id=protocol.expected_protocol_id())
    pointers = []
    for receipt in source:
        if receipt.task_id.endswith("validation-1"):
            baseline_score, candidate_score = validation_scores
            baseline_status, candidate_status = validation_statuses
        else:
            baseline_score, candidate_score = (0, 1_000)
            baseline_status, candidate_status = ("completed", "completed")
        run_provenance = provenance if provenance is not None else receipt.baseline_run.provenance
        contamination = "possible-contamination" if run_provenance == "public_reference" else None
        baseline_run = replace(
            receipt.baseline_run,
            run_id="",
            protocol_id=protocol.protocol_id,
            status=baseline_status,
            score_millis=baseline_score,
            detail="synthetic fixture",
            provenance=run_provenance,
            possible_contamination=contamination,
        )
        baseline_run = replace(baseline_run, run_id=baseline_run.expected_run_id())
        candidate_run = replace(
            receipt.candidate_run,
            run_id="",
            protocol_id=protocol.protocol_id,
            status=candidate_status,
            score_millis=candidate_score,
            detail="synthetic fixture",
            provenance=run_provenance,
            possible_contamination=contamination,
        )
        candidate_run = replace(candidate_run, run_id=candidate_run.expected_run_id())
        rewritten = replace(
            receipt,
            receipt_id=content_id("receipt", {"protocol_id": protocol.protocol_id, "task_id": receipt.task_id}),
            protocol=protocol,
            baseline_run=baseline_run,
            candidate_run=candidate_run,
            comparison_result=_comparison_result(baseline_status, candidate_status, baseline_score, candidate_score),
            baseline_score_millis=baseline_score,
            candidate_score_millis=candidate_score,
            baseline_run_digest=baseline_run.content_digest(),
            candidate_run_digest=candidate_run.content_digest(),
        )
        pointers.append(_emit_receipt(state_dir, rewritten)["digest"] if archive else rewritten.content_digest())
    return tuple(sorted(pointers))


def _rekey_report(value: dict) -> dict:
    report = dict(value)
    report["report_id"] = UpliftReport.expected_report_id(report)
    action = dict(report["action_receipt"])
    package = report["reproduction_package"]
    package_digest = package["digest"] if package is not None else None
    action["resource_id"] = report["report_id"]
    action["action_id"] = content_id("action", {"report_id": report["report_id"], "package_digest": package_digest})
    action["idempotency_key"] = content_id("uplift-action", {"receipt_digests": report["comparison"]["receipt_digests"]})
    report["action_receipt"] = action
    return report


@pytest.mark.parametrize(
    ("name", "scores", "statuses", "threshold", "expected"),
    [
        ("positive", (0, 1_000), ("completed", "completed"), None, "positive"),
        ("null", (500, 500), ("completed", "completed"), None, "null"),
        ("negative", (1_000, 0), ("completed", "completed"), None, "negative"),
        ("inconclusive", (500, 550), ("completed", "completed"), 100, "inconclusive"),
        ("invalid", (None, None), ("timeout", "timeout"), None, "invalid"),
    ],
)
def test_outcome_matrix_is_partitioned_and_byte_stable(tmp_path: Path, name: str, scores, statuses, threshold, expected: str) -> None:
    first_state = tmp_path / f"{name}-first"
    first_set = _receipt_set(first_state, validation_scores=scores, validation_statuses=statuses, threshold=threshold)
    first = generate_uplift_report(first_state, first_set)
    report = first["report"]
    assert report["outcome"] == expected
    assert report["evidence_class"] == "single_run"
    assert report["reproduction_status"] == "none"
    assert report["reproduction_package_status"] == "available"
    assert report["decision_sentence"].endswith(".")
    assert report["scored_evaluation"]["provenance"] == "held_out"
    assert report["scored_evaluation"]["task_count"] == 1
    assert report["calibration"]["provenance"] == "public_reference"
    assert report["calibration"]["task_count"] == 10
    assert report["calibration"]["possible_contamination"] == "possible-contamination"
    assert report["calibration"]["claim_eligible"] is False
    assert report["calibration"]["task_scores"][0]["possible_contamination"] == "possible-contamination"
    assert report["scored_evaluation"]["task_scores"][0]["possible_contamination"] is None
    assert first["reproduction_package"]["digest"] == report["reproduction_package"]["digest"]

    second = generate_uplift_report(first_state, first_set)
    assert first["report_pointer"]["digest"] == second["report_pointer"]["digest"]
    assert first["reproduction_package"]["digest"] == second["reproduction_package"]["digest"]
    assert first["report"]["action_receipt"] == second["report"]["action_receipt"]


def test_zero_held_out_is_inconclusive_and_claim_path_excludes_reference(tmp_path: Path) -> None:
    state = tmp_path / "reference-only"
    receipt_set = _receipt_set(state, provenance="public_reference")
    result = generate_uplift_report(state, receipt_set)
    assert result["report"]["outcome"] == "inconclusive"
    assert result["report"]["scored_evaluation"] == {
        "baseline_mean_millis": None,
        "candidate_mean_millis": None,
        "claim_eligible": False,
        "delta_millis": None,
        "family_differences": [],
        "possible_contamination": None,
        "provenance": "held_out",
        "score_distributions": {
            "baseline": {"values": [], "count": 0, "total": 0, "minimum": None, "maximum": None, "mean": None},
            "candidate": {"values": [], "count": 0, "total": 0, "minimum": None, "maximum": None, "mean": None},
        },
        "task_count": 0,
        "task_scores": [],
    }
    assert result["report"]["calibration"]["task_count"] == 11
    assert all(score["possible_contamination"] == "possible-contamination" for score in result["report"]["calibration"]["task_scores"])


def test_regressions_are_classified_per_task(tmp_path: Path) -> None:
    severe_state = tmp_path / "severe"
    severe = generate_uplift_report(severe_state, _receipt_set(severe_state, validation_scores=(1_000, 0)))
    assert severe["report"]["regressions"]["severe"] == ["contract-drift-validation-1"]
    assert severe["report"]["regressions"]["non_severe"] == []

    non_severe_state = tmp_path / "non-severe"
    non_severe = generate_uplift_report(
        non_severe_state,
        _receipt_set(non_severe_state, validation_scores=(500, 450), threshold=100),
    )
    assert non_severe["report"]["regressions"]["severe"] == []
    assert non_severe["report"]["regressions"]["non_severe"] == ["contract-drift-validation-1"]

    declared_rule_state = tmp_path / "declared-rule"
    declared_rule_source = _source_receipts(declared_rule_state)[0].protocol.decision_rule
    declared_rule = replace(
        declared_rule_source,
        severe_regression_rule=replace(
            declared_rule_source.severe_regression_rule,
            threshold_millis=600,
        ),
    )
    declared_rule_result = generate_uplift_report(
        declared_rule_state,
        _receipt_set(declared_rule_state, validation_scores=(500, 450), decision_rule=declared_rule),
    )
    assert declared_rule_result["report"]["regressions"]["severe"] == []
    assert declared_rule_result["report"]["regressions"]["non_severe"] == ["contract-drift-validation-1"]


def test_declared_decision_rule_controls_minimum_and_null_band(tmp_path: Path) -> None:
    minimum_state = tmp_path / "minimum"
    source_rule = _source_receipts(minimum_state)[0].protocol.decision_rule
    minimum_result = generate_uplift_report(
        minimum_state,
        _receipt_set(minimum_state, decision_rule=replace(source_rule, minimum_valid_task_count=2, positive_threshold_millis=1, negative_threshold_millis=-1)),
    )
    assert minimum_result["report"]["outcome"] == "inconclusive"
    assert minimum_result["report"]["decision_rule"]["minimum_valid_task_count"] == 2

    null_band_state = tmp_path / "null-band"
    null_rule = replace(source_rule, positive_threshold_millis=1_000, negative_threshold_millis=-1_000, null_band_millis=100)
    null_band_result = generate_uplift_report(
        null_band_state,
        _receipt_set(null_band_state, validation_scores=(500, 550), decision_rule=null_rule),
    )
    assert null_band_result["report"]["outcome"] == "null"


def test_report_consumes_only_verified_receipts_and_does_not_write_on_missing_input(tmp_path: Path) -> None:
    state = tmp_path / "missing"
    receipt_set = _receipt_set(state)
    missing = "f" * 64
    with pytest.raises(UpliftReceiptNotFound):
        generate_uplift_report(state, (*receipt_set[:-1], missing))
    assert not (state / "verify" / "uplift").exists()
    with pytest.raises(UpliftInputError):
        generate_uplift_report(state, (receipt_set[0], receipt_set[0]))


def test_report_truth_anchor_rejects_recomputed_unarchived_receipt_chains(tmp_path: Path) -> None:
    score_state = tmp_path / "unarchived-score-chain"
    score_chain = _receipt_set(score_state, validation_scores=(500, 900), archive=False)
    with pytest.raises(UpliftReceiptNotFound, match=score_chain[0]):
        compare_receipts(score_state, score_chain)
    with pytest.raises(UpliftReceiptNotFound, match=score_chain[0]):
        generate_uplift_report(score_state, score_chain)

    provenance_state = tmp_path / "unarchived-provenance-chain"
    provenance_chain = _receipt_set(provenance_state, provenance="public_reference", archive=False)
    with pytest.raises(UpliftReceiptNotFound, match=provenance_chain[0]):
        generate_uplift_report(provenance_state, provenance_chain)

    present_state = tmp_path / "archived-set"
    present_set = _receipt_set(present_state)
    assert compare_receipts(present_state, present_set).receipt_digests == present_set
    present = generate_uplift_report(present_state, present_set)
    assert present["report"]["comparison"]["receipt_digests"] == list(present_set)


def test_receipt_set_permutations_are_byte_idempotent(tmp_path: Path) -> None:
    state = tmp_path / "permutation"
    receipt_set = _receipt_set(state)
    first = generate_uplift_report(state, receipt_set)
    second = generate_uplift_report(state, tuple(reversed(receipt_set)))

    assert second == first
    assert Path(first["report_pointer"]["path"]).read_bytes() == Path(second["report_pointer"]["path"]).read_bytes()
    assert Path(first["reproduction_package"]["path"]).read_bytes() == Path(second["reproduction_package"]["path"]).read_bytes()
    assert first["report"]["report_id"] == second["report"]["report_id"]
    assert first["report"]["action_receipt"]["action_id"] == second["report"]["action_receipt"]["action_id"]
    assert len(list((state / "verify" / "uplift" / "sets" / "sha256").glob("*.json"))) == 1


def test_reordered_report_set_fields_are_rejected_after_rekeying(tmp_path: Path) -> None:
    state = tmp_path / "reorder-attack"
    receipt_set = _receipt_set(state)
    result = generate_uplift_report(state, receipt_set)

    reordered_comparison = dict(result["report"]["comparison"])
    reordered_comparison["receipt_digests"] = list(reversed(reordered_comparison["receipt_digests"]))
    reordered_digests = _rekey_report({**result["report"], "comparison": reordered_comparison})
    with pytest.raises(ModelValidationError, match="canonical lexical order"):
        UpliftReport.from_dict(reordered_digests)

    reordered_bindings = _rekey_report({
        **result["report"],
        "receipt_bindings": list(reversed(result["report"]["receipt_bindings"])),
    })
    reordered_report = UpliftReport.from_dict(reordered_bindings)
    receipts = tuple(EvaluationReceipt.from_dict(show_receipt(state, digest)["receipt"]) for digest in receipt_set)
    with pytest.raises(ModelValidationError, match="bindings"):
        reordered_report.validate_against_receipts(receipts)


def test_partial_duplicate_missing_extra_and_tampered_sets_create_no_uplift_lineage(tmp_path: Path) -> None:
    partial_state = tmp_path / "partial"
    partial_set = _receipt_set(partial_state)
    with pytest.raises(UpliftInputError, match="exactly cover"):
        generate_uplift_report(partial_state, partial_set[:-1])
    assert not (partial_state / "verify" / "uplift").exists()

    duplicate_state = tmp_path / "duplicate"
    duplicate_set = _receipt_set(duplicate_state)
    with pytest.raises(UpliftInputError, match="distinct"):
        generate_uplift_report(duplicate_state, (*duplicate_set[:-1], duplicate_set[0]))
    assert not (duplicate_state / "verify" / "uplift").exists()

    missing_state = tmp_path / "missing-set"
    missing_set = _receipt_set(missing_state)
    with pytest.raises(UpliftReceiptNotFound):
        generate_uplift_report(missing_state, (*missing_set[:-1], "f" * 64))
    assert not (missing_state / "verify" / "uplift").exists()

    extra_state = tmp_path / "extra"
    extra_set = _receipt_set(extra_state)
    foreign_state = tmp_path / "foreign"
    foreign_set = _receipt_set(foreign_state)
    shutil.copyfile(
        foreign_state / "verify" / "receipts" / "sha256" / f"{foreign_set[0]}.json",
        extra_state / "verify" / "receipts" / "sha256" / f"{foreign_set[0]}.json",
    )
    with pytest.raises(UpliftInputError, match="receipt cannot be verified"):
        generate_uplift_report(extra_state, (*extra_set, foreign_set[0]))
    assert not (extra_state / "verify" / "uplift").exists()

    tampered_state = tmp_path / "tampered"
    tampered_set = _receipt_set(tampered_state)
    tampered_path = tampered_state / "verify" / "receipts" / "sha256" / f"{tampered_set[0]}.json"
    tampered_record = json.loads(tampered_path.read_bytes())
    tampered_record["cost"]["total_usd_cents"] += 1
    tampered_path.write_bytes(canonical_json_bytes(tampered_record))
    with pytest.raises(UpliftInputError, match="receipt cannot be verified"):
        generate_uplift_report(tampered_state, tampered_set)
    assert not (tampered_state / "verify" / "uplift").exists()


def test_receipt_emission_is_not_public_and_store_binding_rejects_copied_receipts(tmp_path: Path) -> None:
    assert receipts_api.__all__ == ["show_receipt"]
    assert not hasattr(receipts_api, "emit_receipt")
    assert not hasattr(public_receipt_store, "emit_receipt")

    source = tmp_path / "source"
    source_set = _receipt_set(source)
    target = tmp_path / "target"
    run_builtin_comparison(target, FixtureExecutor())
    target_receipts = target / "verify" / "receipts" / "sha256"
    for digest in source_set:
        shutil.copyfile(source / "verify" / "receipts" / "sha256" / f"{digest}.json", target_receipts / f"{digest}.json")

    with pytest.raises(ValueError, match="receipt store identity mismatch"):
        show_receipt(target, source_set[0])
    with pytest.raises(UpliftInputError, match="receipt cannot be verified"):
        generate_uplift_report(target, source_set)


def test_receipt_loading_rejects_symlinked_store_directories(tmp_path: Path) -> None:
    source = tmp_path / "source"
    receipt_set = _receipt_set(source)

    linked_state = tmp_path / "linked-state"
    linked_state.symlink_to(source, target_is_directory=True)
    with pytest.raises(ValueError, match="must not be a symlink"):
        show_receipt(linked_state, receipt_set[0])

    linked_receipts_state = tmp_path / "linked-receipts-state"
    (linked_receipts_state / "verify").mkdir(parents=True)
    (linked_receipts_state / "verify" / "receipts").symlink_to(source / "verify" / "receipts", target_is_directory=True)
    with pytest.raises(ValueError, match="must not be a symlink"):
        show_receipt(linked_receipts_state, receipt_set[0])


@pytest.mark.parametrize("boundary", ("reservation", "winner-link", "package", "report"))
def test_set_reservation_retries_complete_every_archive_boundary(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, boundary: str) -> None:
    state = tmp_path / f"recover-{boundary}"
    receipt_set = _receipt_set(state)
    winner_bytes = None
    winner_temporary = None
    if boundary == "reservation":
        original_reserve = uplift_store._reserve_set_index

        def crash_after_reservation(*args, **kwargs):
            result = original_reserve(*args, **kwargs)
            raise RuntimeError("simulated reservation crash")

        monkeypatch.setattr(uplift_store, "_reserve_set_index", crash_after_reservation)
    elif boundary == "winner-link":
        def crash_after_winner_link(path: Path, payload: bytes):
            nonlocal winner_temporary
            path.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
            winner_temporary = Path(temporary_name)
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            os.link(winner_temporary, path)
            raise RuntimeError("simulated winner crash after link")

        monkeypatch.setattr(uplift_store, "_reserve_set_index", crash_after_winner_link)
    else:
        original_emit = uplift_store._emit
        target_call = 1 if boundary == "package" else 2
        calls = 0

        def crash_after_archive(*args, **kwargs):
            nonlocal calls
            calls += 1
            result = original_emit(*args, **kwargs)
            if calls == target_call:
                raise RuntimeError(f"simulated {boundary} archive crash")
            return result

        monkeypatch.setattr(uplift_store, "_emit", crash_after_archive)

    with pytest.raises(RuntimeError, match="simulated"):
        generate_uplift_report(state, receipt_set)

    if boundary == "winner-link":
        index_path = next((state / "verify" / "uplift" / "sets" / "sha256").glob("*.json"))
        winner_bytes = index_path.read_bytes()
        assert index_path.stat().st_nlink == 2
        assert winner_temporary is not None and winner_temporary.exists()

    monkeypatch.undo()
    recovered = generate_uplift_report(state, receipt_set)
    repeated = generate_uplift_report(state, receipt_set)
    assert repeated["report_pointer"] == recovered["report_pointer"]
    assert repeated["reproduction_package"] == recovered["reproduction_package"]
    assert len(list((state / "verify" / "uplift" / "reports" / "sha256").glob("*.json"))) == 1
    assert len(list((state / "verify" / "uplift" / "packages" / "sha256").glob("*.json"))) == 1
    set_directory = state / "verify" / "uplift" / "sets" / "sha256"
    index_path = next(set_directory.glob("*.json"))
    assert len(list(set_directory.glob("*.json"))) == 1
    assert not list(set_directory.glob(".*.tmp"))
    if boundary == "winner-link":
        assert index_path.read_bytes() == winner_bytes
        assert index_path.stat().st_nlink == 1


def test_incomplete_set_reservation_conflicts_on_different_tolerance(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    state = tmp_path / "incomplete-tolerance"
    receipt_set = _receipt_set(state)
    original_emit = uplift_store._emit
    calls = 0

    def crash_after_package(*args, **kwargs):
        nonlocal calls
        calls += 1
        result = original_emit(*args, **kwargs)
        if calls == 1:
            raise RuntimeError("simulated package archive crash")
        return result

    monkeypatch.setattr(uplift_store, "_emit", crash_after_package)
    with pytest.raises(RuntimeError, match="simulated package archive crash"):
        generate_uplift_report(state, receipt_set)
    monkeypatch.undo()

    index_path = next((state / "verify" / "uplift" / "sets" / "sha256").glob("*.json"))
    reserved_report_id = uplift_store._read_set_index(index_path)["report"]["id"]
    with pytest.raises(UpliftReportConflictError, match=reserved_report_id):
        generate_uplift_report(state, receipt_set, {"score_millis": 25})


def test_concurrent_different_tolerance_writers_have_one_verified_winner(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    state = tmp_path / "concurrent-tolerance"
    receipt_set = _receipt_set(state)
    barrier = Barrier(2)
    original_reserve = uplift_store._reserve_set_index

    def synchronized_reserve(*args, **kwargs):
        barrier.wait(timeout=5)
        return original_reserve(*args, **kwargs)

    monkeypatch.setattr(uplift_store, "_reserve_set_index", synchronized_reserve)
    tolerances = ({"score_millis": 25}, {"score_millis": 50})
    successes = []
    failures = []
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(generate_uplift_report, state, receipt_set, tolerance) for tolerance in tolerances]
        for future in futures:
            try:
                successes.append(future.result())
            except Exception as error:
                failures.append(error)

    assert len(successes) == 1
    assert len(failures) == 1
    assert isinstance(failures[0], UpliftReportConflictError)
    winner = successes[0]
    index_path = next((state / "verify" / "uplift" / "sets" / "sha256").glob("*.json"))
    expected_index = {
        "schema_version": 1,
        "receipt_digests": list(receipt_set),
        "report": {"id": winner["report"]["report_id"], "digest": winner["report_pointer"]["digest"]},
        "package": {"digest": winner["reproduction_package"]["digest"]},
    }
    assert index_path.read_bytes() == canonical_json_bytes(expected_index)
    assert index_path.stat().st_nlink == 1
    assert not list(index_path.parent.glob(".*.tmp"))


def test_structural_honesty_and_evidence_only_arm_are_canonical(tmp_path: Path) -> None:
    state = tmp_path / "honesty"
    result = generate_uplift_report(state, _receipt_set(state))
    report = UpliftReport.from_dict(result["report"])
    package = ReproductionPackage.from_dict(show_reproduction_package(state, result["reproduction_package"]["digest"])["package"])
    assert package.assembly_status == "assembled"
    assert package.executed is False
    assert report.evidence_class == "single_run"
    assert report.reproduction_status == "none"
    assert report.reproduction_package_status == "available"
    assert report.decision_sentence == "This skill improved held-out performance by 100 percentage points, ending at 100%, with no severe regressions."
    evidence_arm = ArmIdentity(
        "evidence-only-model",
        "reference",
        report.arms[0].model,
        report.arms[0].capsule_id,
        False,
        True,
    )
    with_evidence = dict(result["report"])
    with_evidence["arms"] = [*with_evidence["arms"], evidence_arm.to_dict()]
    with_evidence = _rekey_report(with_evidence)
    assert len(UpliftReport.from_dict(with_evidence).arms) == 3
    tampered = dict(result["report"])
    tampered["evidence_class"] = "independently_reproduced"
    with pytest.raises(ModelValidationError):
        UpliftReport.from_dict(tampered)
    sentence_tampered = dict(result["report"])
    sentence_tampered["decision_sentence"] = "two sentences. Another sentence."
    with pytest.raises(ModelValidationError):
        UpliftReport.from_dict(sentence_tampered)
    unlabeled = dict(result["report"])
    unlabeled["calibration"] = dict(unlabeled["calibration"])
    unlabeled["calibration"]["possible_contamination"] = None
    with pytest.raises(ModelValidationError):
        UpliftReport.from_dict(unlabeled)

    absent = dict(result["report"])
    absent["reproduction_package_status"] = "absent"
    absent["reproduction_package"] = None
    absent = _rekey_report(absent)
    assert UpliftReport.from_dict(absent).reproduction_package_digest is None


@pytest.mark.parametrize("status", ["not_run", "attempted", "reproduced", "failed_to_reproduce"])
def test_reproduction_status_hard_cut_rejects_unbound_vocabularies(tmp_path: Path, status: str) -> None:
    state = tmp_path / status
    result = generate_uplift_report(state, _receipt_set(state))
    tampered = _rekey_report({**result["report"], "reproduction_status": status})
    with pytest.raises(ModelValidationError, match="must be none"):
        UpliftReport.from_dict(tampered)


def test_reproduction_tolerance_is_nullable_package_data(tmp_path: Path) -> None:
    state = tmp_path / "tolerance"
    result = generate_uplift_report(state, _receipt_set(state), {"score_millis": 25})
    package = show_reproduction_package(state, result["reproduction_package"]["digest"])["package"]
    assert package["reproduction_tolerance"] == {"score_millis": 25}
    assert all("No reproduction tolerance was supplied" not in limitation for limitation in result["report"]["limitations"])


def test_run_identity_and_receipt_digest_reject_score_tampering(tmp_path: Path) -> None:
    state = tmp_path / "run-tamper"
    receipt_set = _receipt_set(state, validation_scores=(500, 600))
    raw = show_receipt(state, receipt_set[0])["receipt"]
    raw["runs"]["baseline"]["outcome"]["score_millis"] = 900
    recomputed_receipt_digest = sha256_bytes(canonical_json_bytes(raw))
    assert len(recomputed_receipt_digest) == 64
    with pytest.raises(ModelValidationError, match="run_id|run digest"):
        EvaluationReceipt.from_dict(raw)


def test_receipt_provenance_relabel_is_tamper_detected(tmp_path: Path) -> None:
    state = tmp_path / "provenance-tamper"
    receipt_set = _receipt_set(state)
    raw = next(
        show_receipt(state, digest)["receipt"]
        for digest in receipt_set
        if show_receipt(state, digest)["receipt"]["runs"]["baseline"]["provenance"] == "held_out"
    )
    raw["runs"]["baseline"]["provenance"] = "public_reference"
    raw["runs"]["baseline"]["possible_contamination"] = "possible-contamination"
    with pytest.raises(ModelValidationError, match="run_id|run digest|provenance"):
        EvaluationReceipt.from_dict(raw)


def test_calibration_presence_is_conditional_on_receipt_provenance(tmp_path: Path) -> None:
    zero_reference_state = tmp_path / "zero-reference"
    zero_reference = generate_uplift_report(zero_reference_state, _receipt_set(zero_reference_state, provenance="held_out"))
    zero_report = UpliftReport.from_dict(zero_reference["report"])
    assert zero_report.calibration is None

    reference_state = tmp_path / "has-reference"
    reference = generate_uplift_report(reference_state, _receipt_set(reference_state))
    absent = _rekey_report({**reference["report"], "calibration": None})
    with pytest.raises(ModelValidationError, match="calibration"):
        UpliftReport.from_dict(absent)

    fabricated = dict(reference["report"]["calibration"])
    fabricated["score_distributions"] = {
        "baseline": {"values": [], "count": 0, "total": 0, "minimum": None, "maximum": None, "mean": None},
        "candidate": {"values": [], "count": 0, "total": 0, "minimum": None, "maximum": None, "mean": None},
    }
    fabricated["task_scores"] = []
    fabricated["family_differences"] = []
    fabricated["task_count"] = 0
    fabricated["baseline_mean_millis"] = None
    fabricated["candidate_mean_millis"] = None
    fabricated["delta_millis"] = None
    fabricated_report = _rekey_report({**reference["report"], "calibration": fabricated})
    with pytest.raises(ModelValidationError, match="calibration"):
        UpliftReport.from_dict(fabricated_report)


def test_report_relationships_are_derived_and_forged_report_is_rejected(tmp_path: Path) -> None:
    state = tmp_path / "forged-report"
    result = generate_uplift_report(state, _receipt_set(state))
    forged = _rekey_report({
        **result["report"],
        "outcome": "negative",
        "decision_sentence": "The forged claim is acceptable.",
        "final_capability_level": {"scale": "score_millis", "baseline": None, "candidate": None},
    })
    with pytest.raises(ModelValidationError, match="outcome|decision_sentence|final capability"):
        UpliftReport.from_dict(forged)


def test_protocol_lock_rejects_unknown_decision_rule_condition(tmp_path: Path) -> None:
    protocol = _source_receipts(tmp_path / "closed-vocabulary")[0].protocol
    record = protocol.to_dict()
    record["decision_rule"]["inconclusive_conditions"] = ["unknown_condition"]
    with pytest.raises(ValueError, match="unknown condition"):
        EvaluationProtocol.from_dict(record)


def test_report_generation_is_set_idempotent_and_conflicts_on_auxiliary_changes(tmp_path: Path) -> None:
    state = tmp_path / "idempotent"
    receipt_set = _receipt_set(state)
    tolerance = {"score_millis": 10}
    first = generate_uplift_report(state, receipt_set, tolerance)
    second = generate_uplift_report(state, receipt_set, {"score_millis": 10})
    assert second["report_pointer"] == first["report_pointer"]
    assert second["reproduction_package"] == first["reproduction_package"]
    assert second["report"] == first["report"]
    with pytest.raises(UpliftReportConflictError, match=first["report"]["report_id"]):
        generate_uplift_report(state, receipt_set, {"score_millis": 25})
    assert len(list((state / "verify" / "uplift" / "reports" / "sha256").glob("*.json"))) == 1
    assert len(list((state / "verify" / "uplift" / "packages" / "sha256").glob("*.json"))) == 1
    assert len(list((state / "verify" / "uplift" / "sets" / "sha256").glob("*.json"))) == 1


def test_relative_error_reduction_and_singular_decision_sentence_are_canonical(tmp_path: Path) -> None:
    state = tmp_path / "relative-error"
    result = generate_uplift_report(state, _receipt_set(state, validation_scores=(400, 500)))
    assert result["report"]["measured_change"]["relative_error_reduction_millis"] == 167

    source_rule = _source_receipts(tmp_path / "singular-rule")[0].protocol.decision_rule
    singular_rule = replace(source_rule, positive_threshold_millis=10, negative_threshold_millis=-10, null_band_millis=0)
    singular_state = tmp_path / "singular"
    singular = generate_uplift_report(
        singular_state,
        _receipt_set(singular_state, validation_scores=(500, 510), decision_rule=singular_rule),
    )
    assert singular["report"]["decision_sentence"] == "This skill improved held-out performance by 1 percentage point, ending at 51%, with no severe regressions."
    assert "1 percentage points" not in singular["report"]["decision_sentence"]
    assert render_decision_sentence("positive", 510, 10, UpliftReport.from_dict(singular["report"]).regressions) == singular["report"]["decision_sentence"]
