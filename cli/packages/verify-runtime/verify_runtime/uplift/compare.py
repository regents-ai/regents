"""Store-anchored comparison of immutable evaluation receipts.

The public comparison entry point accepts only receipt digests and loads the
archived-at-emission bytes.  The private record comparator retains internal
consistency checks as defense in depth after that store anchor is established.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Sequence

from verify_runtime.model import (
    ActionReceipt,
    ArmIdentity,
    Capsule,
    Distribution,
    EvaluationProtocol,
    EvaluationReceipt,
    EvaluationSection,
    FamilyDifference,
    Freshness,
    ModelIdentity,
    ReceiptTaskBinding,
    RegressionSummary,
    TaskDifference,
    UpliftReport,
    Uncertainty,
    canonical_json_bytes,
    content_id,
    derive_outcome,
    relative_error_reduction_millis,
    render_decision_sentence,
    sha256_bytes,
)
from verify_runtime.receipts import show_receipt

from .errors import UpliftInputError, UpliftReceiptNotFound


@dataclass(frozen=True)
class ComparisonData:
    """The deterministic, non-persisted result used by report and package builders."""

    receipt_digests: tuple[str, ...]
    receipts: tuple[EvaluationReceipt, ...]
    protocol: EvaluationProtocol
    baseline_capsule: Capsule
    candidate_capsule: Capsule
    arms: tuple[ArmIdentity, ...]
    task_differences: tuple[TaskDifference, ...]
    receipt_bindings: tuple[ReceiptTaskBinding, ...]
    scored_evaluation: EvaluationSection
    calibration: EvaluationSection | None
    outcome: str
    point_delta_millis: int | None
    regressions: RegressionSummary
    cost_latency: dict[str, dict[str, Distribution]]
    disclosures: dict[str, Any]
    limitations: tuple[str, ...]
    freshness: Freshness


def _fail(message: str) -> None:
    raise UpliftInputError(message)


def _digest(value: Any, path: str) -> str:
    if type(value) is not str or len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        _fail(f"{path} must be a lowercase SHA-256 digest")
    return value


def _mean(values: list[int]) -> int | None:
    return sum(values) // len(values) if values else None


def _static_capsule(capsule: Capsule) -> dict[str, Any]:
    return {
        "schema_version": capsule.schema_version,
        "capsule_id": capsule.capsule_id,
        "declared": capsule.declared.to_dict(),
        "resolved": capsule.resolved.to_dict(),
    }


def _expected_comparison(baseline_status: str, candidate_status: str, baseline_score: int | None, candidate_score: int | None) -> str:
    if baseline_status != "completed":
        return baseline_status
    if candidate_status != "completed":
        return candidate_status
    if baseline_score is None or candidate_score is None:
        return "invalid"
    if candidate_score > baseline_score:
        return "positive"
    if candidate_score < baseline_score:
        return "negative"
    return "null"


def _validate_receipt(receipt: EvaluationReceipt, protocol: EvaluationProtocol) -> None:
    if receipt.task_id not in {selection.task_id for selection in protocol.selections}:
        _fail(f"receipt task is not in the locked matched selections: {receipt.task_id}")
    if receipt.baseline_capsule.capsule_id != protocol.baseline_capsule_id or receipt.candidate_capsule.capsule_id != protocol.candidate_capsule_id:
        _fail(f"receipt capsules do not match the locked protocol: {receipt.task_id}")
    for run, side, capsule_id in (
        (receipt.baseline_run, "baseline", protocol.baseline_capsule_id),
        (receipt.candidate_run, "candidate", protocol.candidate_capsule_id),
    ):
        if run.protocol_id != protocol.protocol_id or run.capsule_id != capsule_id or run.side != side or run.task_id != receipt.task_id:
            _fail(f"receipt run identity is unmatched for task: {receipt.task_id}")
    if receipt.baseline_score_millis != receipt.baseline_run.score_millis or receipt.candidate_score_millis != receipt.candidate_run.score_millis:
        _fail(f"receipt score summary does not match its runs: {receipt.task_id}")
    expected = _expected_comparison(
        receipt.baseline_run.status,
        receipt.candidate_run.status,
        receipt.baseline_run.score_millis,
        receipt.candidate_run.score_millis,
    )
    if receipt.comparison_result != expected:
        _fail(f"receipt comparison result does not match its runs: {receipt.task_id}")
    if receipt.total_cost_usd_cents != receipt.baseline_run.cost_usd_cents + receipt.candidate_run.cost_usd_cents:
        _fail(f"receipt cost summary does not match its runs: {receipt.task_id}")
    expected_receipt_id = content_id("receipt", {"protocol_id": protocol.protocol_id, "task_id": receipt.task_id})
    if receipt.receipt_id != expected_receipt_id:
        _fail(f"receipt identity is not canonical for task: {receipt.task_id}")


def _task_difference(receipt: EvaluationReceipt, selection, protocol: EvaluationProtocol) -> TaskDifference:
    baseline = receipt.baseline_run
    candidate = receipt.candidate_run
    if baseline.provenance != candidate.provenance or baseline.provenance != selection.provenance:
        _fail(f"receipt run provenance is unmatched for task: {receipt.task_id}")
    valid = baseline.status == "completed" and candidate.status == "completed" and baseline.score_millis is not None and candidate.score_millis is not None
    delta = candidate.score_millis - baseline.score_millis if valid else None
    if delta is None:
        classification = "invalid"
        severity = "invalid"
    elif delta > 0:
        classification = "improved"
        severity = "none"
    elif delta < 0:
        classification = "regressed"
        severe_rule = protocol.decision_rule.severe_regression_rule
        severity = "severe" if severe_rule.kind == "delta_at_or_below" and delta <= -severe_rule.threshold_millis else "non-severe"
    else:
        classification = "unchanged"
        severity = "none"
    return TaskDifference(
        task_id=receipt.task_id,
        family_id=protocol.family_id,
        provenance=baseline.provenance,
        baseline_status=baseline.status,
        candidate_status=candidate.status,
        baseline_score_millis=baseline.score_millis,
        candidate_score_millis=candidate.score_millis,
        delta_millis=delta,
        classification=classification,
        regression_severity=severity,
        possible_contamination=baseline.possible_contamination,
    )


def _section(provenance: str, scores: tuple[TaskDifference, ...], minimum_valid_task_count: int) -> EvaluationSection:
    valid = [score for score in scores if score.delta_millis is not None and score.baseline_score_millis is not None and score.candidate_score_millis is not None]
    baseline_mean = _mean([score.baseline_score_millis for score in valid if score.baseline_score_millis is not None])
    candidate_mean = _mean([score.candidate_score_millis for score in valid if score.candidate_score_millis is not None])
    delta = candidate_mean - baseline_mean if baseline_mean is not None and candidate_mean is not None else None
    return EvaluationSection(
        provenance=provenance,
        possible_contamination="possible-contamination" if provenance == "public_reference" else None,
        baseline_distribution=Distribution.from_values(tuple(score.baseline_score_millis for score in scores if score.baseline_score_millis is not None and score.delta_millis is not None)),
        candidate_distribution=Distribution.from_values(tuple(score.candidate_score_millis for score in scores if score.candidate_score_millis is not None and score.delta_millis is not None)),
        task_scores=scores,
        family_differences=(
            (FamilyDifference(
                family_id=scores[0].family_id,
                provenance=provenance,
                task_count=len(scores),
                baseline_mean_millis=baseline_mean,
                candidate_mean_millis=candidate_mean,
                delta_millis=delta,
                possible_contamination="possible-contamination" if provenance == "public_reference" else None,
            ),)
            if scores
            else ()
        ),
        task_count=len(scores),
        claim_eligible=provenance == "held_out" and bool(scores) and len(valid) == len(scores) and len(valid) >= minimum_valid_task_count,
        baseline_mean_millis=baseline_mean,
        candidate_mean_millis=candidate_mean,
        delta_millis=delta,
    )


def _model_identity(capsule: Capsule) -> ModelIdentity:
    resolved = capsule.resolved
    return ModelIdentity(
        provider=resolved.provider,
        identifier=resolved.model_identifier,
        version=resolved.model_version,
        behavioral_fingerprint=resolved.behavioral_fingerprint,
        mutability=resolved.model_mutability,
    )


def _facts(capsules: tuple[Capsule, ...], field: str) -> list[str]:
    values: set[str] = set()
    for capsule in capsules:
        values.update(f"{name}={value}" for name, value in getattr(capsule.observed, field))
    return sorted(values)


def _disclosures(protocol: EvaluationProtocol, baseline: Capsule, candidate: Capsule, receipts: tuple[EvaluationReceipt, ...]) -> dict[str, Any]:
    return {
        "model_identity": {
            "baseline": _model_identity(baseline).to_dict(),
            "candidate": _model_identity(candidate).to_dict(),
        },
        "permissions": {
            "baseline": list(baseline.declared.runtime_permissions),
            "candidate": list(candidate.declared.runtime_permissions),
        },
        "tool_policy": {
            "baseline": _facts(tuple(receipt.baseline_capsule for receipt in receipts), "tool_facts"),
            "candidate": _facts(tuple(receipt.candidate_capsule for receipt in receipts), "tool_facts"),
        },
        "search_optimizer": {
            "method": protocol.optimizer_method,
            "candidate_count": protocol.optimizer_candidate_count,
            "rejected_candidate_ids": list(protocol.rejected_candidate_ids),
        },
        "execution": {
            "adapter": {"baseline": baseline.observed.executor, "candidate": candidate.observed.executor},
            "harness_settings": [{"name": name, "value": value} for name, value in protocol.harness_settings],
            "seeds": list(protocol.seeds),
            "expected_output_schema": protocol.expected_output_schema,
        },
        "intervention": {
            "class": protocol.intervention_class,
            "changed_files": list(protocol.changed_files),
            "treatment_diff": protocol.treatment_diff,
        },
        "policy": protocol.policy.to_dict(),
        "decision_rule": protocol.decision_rule.to_dict(),
        "verifier": {"protocol_id": protocol.protocol_id, "expected_output_schema": protocol.expected_output_schema},
        "publication_policy": {
            "baseline": baseline.declared.publication_policy,
            "candidate": candidate.declared.publication_policy,
        },
        "evidence": {
            "scored_provenance": "held_out",
            "calibration_provenance": "public_reference",
            "claim_path": "held_out-only",
        },
        "reproduction": {"status": "assembled-not-executed"},
    }


def _compare_receipt_records(receipt_inputs: Sequence[tuple[str, EvaluationReceipt]]) -> ComparisonData:
    """Compare a non-empty set of records loaded and verified by one store."""

    if not receipt_inputs:
        _fail("uplift comparison requires a non-empty receipt set")
    normalized: list[tuple[str, EvaluationReceipt]] = []
    for index, (digest_value, receipt) in enumerate(receipt_inputs):
        digest = _digest(digest_value, f"receipt_digests[{index}]")
        if not isinstance(receipt, EvaluationReceipt):
            _fail(f"receipt_inputs[{index}] is not an EvaluationReceipt")
        if sha256_bytes(canonical_json_bytes(receipt.to_dict())) != digest:
            _fail(f"receipt digest does not match its canonical record: {digest}")
        if receipt.baseline_run_digest != receipt.baseline_run.content_digest() or receipt.candidate_run_digest != receipt.candidate_run.content_digest():
            _fail(f"receipt run digest does not match its embedded run content: {digest}")
        if receipt.baseline_run.run_id != receipt.baseline_run.expected_run_id() or receipt.candidate_run.run_id != receipt.candidate_run.expected_run_id():
            _fail(f"receipt run identity does not match its embedded run content: {digest}")
        normalized.append((digest, receipt))
    normalized.sort(key=lambda item: item[0])
    normalized_digests = tuple(digest for digest, _ in normalized)
    if len(set(normalized_digests)) != len(normalized_digests):
        _fail("uplift comparison requires distinct receipt digests")
    protocol = normalized[0][1].protocol
    if any(receipt.protocol.to_dict() != protocol.to_dict() for _, receipt in normalized[1:]):
        _fail("receipt protocols are unmatched")
    selections = {selection.task_id: selection for selection in protocol.selections}
    if len(selections) != len(protocol.selections):
        _fail("locked protocol contains duplicate matched selections")
    if not protocol.selections:
        _fail("locked protocol contains no matched selections")
    matched_orders = tuple(selection.matched_order for selection in protocol.selections)
    if len(set(matched_orders)) != len(matched_orders) or set(matched_orders) != set(range(len(matched_orders))):
        _fail("locked protocol matched_order positions are not canonical")
    seen_tasks: set[str] = set()
    baseline_static: dict[str, Any] | None = None
    candidate_static: dict[str, Any] | None = None
    for _, receipt in normalized:
        _validate_receipt(receipt, protocol)
        if receipt.task_id in seen_tasks:
            _fail(f"receipt set contains a duplicate task: {receipt.task_id}")
        seen_tasks.add(receipt.task_id)
        current_baseline = _static_capsule(receipt.baseline_capsule)
        current_candidate = _static_capsule(receipt.candidate_capsule)
        if baseline_static is None:
            baseline_static = current_baseline
            candidate_static = current_candidate
        elif current_baseline != baseline_static or current_candidate != candidate_static:
            _fail("receipt capsules are unmatched across the receipt set")
    if seen_tasks != set(selections):
        _fail("receipt set does not exactly cover the locked matched selections")

    ordered = tuple(sorted((receipt for _, receipt in normalized), key=lambda receipt: selections[receipt.task_id].matched_order))
    differences = tuple(_task_difference(receipt, selections[receipt.task_id], protocol) for receipt in ordered)
    held_out = tuple(difference for difference in differences if difference.provenance == "held_out")
    reference = tuple(difference for difference in differences if difference.provenance == "public_reference")
    rule = protocol.decision_rule
    if rule.primary_metric != "score_millis":
        _fail(f"declared decision rule primary metric is not receipt-backed: {rule.primary_metric}")
    scored = _section("held_out", held_out, rule.minimum_valid_task_count)
    calibration = _section("public_reference", reference, rule.minimum_valid_task_count) if reference else None
    derived_outcome = derive_outcome(rule, scored, calibration)
    point_delta = scored.delta_millis
    outcome = derived_outcome
    severe = tuple(difference.task_id for difference in held_out if difference.regression_severity == "severe")
    non_severe = tuple(difference.task_id for difference in held_out if difference.regression_severity == "non-severe")
    cost_latency = {
        "baseline": {
            "cost_usd_cents": Distribution.from_values(tuple(receipt.baseline_run.cost_usd_cents for receipt in ordered)),
            "wall_time_ms": Distribution.from_values(tuple(receipt.baseline_run.wall_time_ms for receipt in ordered)),
        },
        "candidate": {
            "cost_usd_cents": Distribution.from_values(tuple(receipt.candidate_run.cost_usd_cents for receipt in ordered)),
            "wall_time_ms": Distribution.from_values(tuple(receipt.candidate_run.wall_time_ms for receipt in ordered)),
        },
    }
    baseline_capsule = ordered[0].baseline_capsule
    candidate_capsule = ordered[0].candidate_capsule
    return ComparisonData(
        receipt_digests=normalized_digests,
        receipts=ordered,
        protocol=protocol,
        baseline_capsule=baseline_capsule,
        candidate_capsule=candidate_capsule,
        arms=(
            ArmIdentity("baseline", "baseline", _model_identity(baseline_capsule), baseline_capsule.capsule_id, True, False),
            ArmIdentity("candidate", "treatment", _model_identity(candidate_capsule), candidate_capsule.capsule_id, True, False),
        ),
        task_differences=differences,
        receipt_bindings=tuple(
            ReceiptTaskBinding(receipt.task_id, receipt.baseline_run.provenance, receipt.baseline_run_digest, receipt.candidate_run_digest)
            for receipt in ordered
        ),
        scored_evaluation=scored,
        calibration=calibration,
        outcome=outcome,
        point_delta_millis=point_delta,
        regressions=RegressionSummary(severe, non_severe),
        cost_latency=cost_latency,
        disclosures=_disclosures(protocol, baseline_capsule, candidate_capsule, ordered),
        limitations=(
            "The claim path uses held_out provenance only; public_reference scores are calibration only.",
            "Every public_reference score is marked possible-contamination.",
            "No confidence interval is reported; uncertainty is declared as a point delta under the fixture decision rule.",
            "Freshness is not independently established from these receipts.",
            "Local receipt files are operator-controlled; a local operator can fabricate them.",
            "Receipt digests and store binding are tamper-evident within the runner emission path and checkable by the report verifier.",
            "Cryptographic attestation is the post-v0.1 proof layer; receipt-store binding and the queued post-freeze independent report verifier are the v0.1 checkable layer.",
        ),
        freshness=Freshness("freshness-not-rated", None, ("a new receipt set supersedes this report", "the locked protocol or capsule identity changes")),
    )


def compare_receipts(state_dir: Path, receipt_digests: Sequence[str]) -> ComparisonData:
    """Load a non-empty archived receipt set and compare its verified records."""

    if not receipt_digests:
        _fail("uplift comparison requires a non-empty receipt set")
    normalized_digests = tuple(sorted(_digest(value, f"receipt_digests[{index}]") for index, value in enumerate(receipt_digests)))
    if len(set(normalized_digests)) != len(normalized_digests):
        _fail("uplift comparison requires distinct receipt digests")
    stored: list[tuple[str, EvaluationReceipt]] = []
    for digest in normalized_digests:
        try:
            pointer = show_receipt(state_dir, digest)
            receipt = EvaluationReceipt.from_dict(pointer["receipt"])
        except FileNotFoundError as error:
            raise UpliftReceiptNotFound(str(error)) from error
        except (TypeError, ValueError, KeyError, UnicodeError, RecursionError) as error:
            raise UpliftInputError(f"receipt cannot be verified: {digest}") from error
        stored.append((digest, receipt))
    return _compare_receipt_records(stored)


def decision_sentence(data: ComparisonData) -> str:
    """Render one deterministic sentence from structured comparison fields."""
    return render_decision_sentence(data.outcome, data.scored_evaluation.candidate_mean_millis, data.point_delta_millis, data.regressions)  # type: ignore[arg-type]


def make_report_without_package(data: ComparisonData, package_digest: str, *, tolerance_supplied: bool) -> UpliftReport:
    limitations = data.limitations
    if not tolerance_supplied:
        limitations = (*limitations, "No reproduction tolerance was supplied; the archived package records it as null.")
    placeholder_action = ActionReceipt(
        action_id="placeholder-action",
        capability_id="techtree.uplift",
        action_kind="report",
        resource_type="uplift_report",
        resource_id="placeholder-report",
        status="completed",
        idempotency_key="placeholder-idempotency",
        created_at=None,
        updated_at=None,
        public_url=None,
        next_recommended_action="placeholder",
        next_poll_at=None,
        approval_required=False,
        chain_id=None,
        transaction_hash=None,
        error_code=None,
    )
    report = UpliftReport(
        schema_version=1,
        report_id="",
        receipt_digests=data.receipt_digests,
        protocol_id=data.protocol.protocol_id,
        family_id=data.protocol.family_id,
        challenge_revision_id=data.protocol.challenge_revision_id,
        arms=data.arms,
        receipt_bindings=data.receipt_bindings,
        decision_rule=data.protocol.decision_rule,
        scored_evaluation=data.scored_evaluation,
        calibration=data.calibration,
        outcome=data.outcome,  # type: ignore[arg-type]
        final_capability_level={
            "scale": "score_millis",
            "baseline": data.scored_evaluation.baseline_mean_millis,
            "candidate": data.scored_evaluation.candidate_mean_millis,
        },
        measured_change={
            "absolute_delta_millis": data.scored_evaluation.delta_millis,
            "relative_error_reduction_millis": relative_error_reduction_millis(data.protocol.decision_rule.primary_metric, data.scored_evaluation.baseline_mean_millis, data.scored_evaluation.candidate_mean_millis),
        },
        uncertainty=Uncertainty(
            treatment="declared-point-delta",
            point_delta_millis=data.point_delta_millis,
        ),
        regressions=data.regressions,
        cost_latency=data.cost_latency,
        disclosures=data.disclosures,
        limitations=limitations,
        freshness=data.freshness,
        evidence_class="single_run",
        reproduction_status="none",
        reproduction_package_status="available",
        decision_sentence=decision_sentence(data),
        reproduction_package_digest=package_digest,
        action_receipt=placeholder_action,
    )
    return replace(report, report_id=UpliftReport.expected_report_id(report.to_dict()))
