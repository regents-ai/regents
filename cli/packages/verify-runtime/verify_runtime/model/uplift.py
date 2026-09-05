"""Canonical, validation-symmetric Uplift report records."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal, Sequence, TYPE_CHECKING

from .base import (
    ModelValidationError,
    content_id,
    require_bool,
    require_bounded_int,
    require_exact_keys,
    require_identifier,
    require_int,
    require_nullable_int,
    require_nullable_string,
    require_record,
    require_schema_version,
    require_sha256,
    require_string,
    require_string_list,
    require_type,
)
from .protocol import DecisionRule, INVALID_CONDITIONS, INCONCLUSIVE_CONDITIONS
from .task import POSSIBLE_CONTAMINATION, TASK_PROVENANCES, TaskProvenance

if TYPE_CHECKING:
    from .receipt import EvaluationReceipt

Outcome = Literal["positive", "null", "negative", "inconclusive", "invalid"]
PROVENANCE = TaskProvenance
OUTCOMES = {"positive", "null", "negative", "inconclusive", "invalid"}
PROVENANCES = TASK_PROVENANCES
EVIDENCE_CLASS = "single_run"
REPRODUCTION_STATUS = "none"
REPRODUCTION_PACKAGE_STATUSES = {"available", "absent"}


def _require_provenance(value: Any, path: str) -> PROVENANCE:
    provenance = require_string(value, path)
    if provenance not in PROVENANCES:
        raise ModelValidationError(f"{path} must be held_out or public_reference")
    return provenance  # type: ignore[return-value]


def _require_nullable_string_list(value: Any, path: str) -> tuple[str, ...]:
    require_type(value, list, path)
    return tuple(require_string(item, f"{path}[{index}]") for index, item in enumerate(value))


@dataclass(frozen=True)
class ModelIdentity:
    provider: str
    identifier: str
    version: str
    behavioral_fingerprint: str | None
    mutability: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "provider": self.provider,
            "identifier": self.identifier,
            "version": self.version,
            "behavioral_fingerprint": self.behavioral_fingerprint,
            "mutability": self.mutability,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str = "model_identity") -> "ModelIdentity":
        record = require_record(value, path)
        require_exact_keys(record, {"provider", "identifier", "version", "behavioral_fingerprint", "mutability"}, path)
        return cls(
            require_string(record["provider"], f"{path}.provider"),
            require_string(record["identifier"], f"{path}.identifier"),
            require_string(record["version"], f"{path}.version"),
            require_nullable_string(record["behavioral_fingerprint"], f"{path}.behavioral_fingerprint"),
            require_string(record["mutability"], f"{path}.mutability"),
        )


@dataclass(frozen=True)
class ArmIdentity:
    arm_id: str
    role: str
    model: ModelIdentity
    capsule_id: str
    gating: bool
    evidence_only: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "arm_id": self.arm_id,
            "role": self.role,
            "model": self.model.to_dict(),
            "capsule_id": self.capsule_id,
            "gating": self.gating,
            "evidence_only": self.evidence_only,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "ArmIdentity":
        record = require_record(value, path)
        require_exact_keys(record, {"arm_id", "role", "model", "capsule_id", "gating", "evidence_only"}, path)
        gating = require_bool(record["gating"], f"{path}.gating")
        evidence_only = require_bool(record["evidence_only"], f"{path}.evidence_only")
        if evidence_only and gating:
            raise ModelValidationError(f"{path} evidence-only arms cannot be gating")
        return cls(
            require_identifier(record["arm_id"], f"{path}.arm_id"),
            require_identifier(record["role"], f"{path}.role"),
            ModelIdentity.from_dict(record["model"], f"{path}.model"),
            require_identifier(record["capsule_id"], f"{path}.capsule_id"),
            gating,
            evidence_only,
        )


@dataclass(frozen=True)
class ReceiptTaskBinding:
    task_id: str
    provenance: PROVENANCE
    baseline_run_digest: str
    candidate_run_digest: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "provenance": self.provenance,
            "baseline_run_digest": self.baseline_run_digest,
            "candidate_run_digest": self.candidate_run_digest,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "ReceiptTaskBinding":
        record = require_record(value, path)
        require_exact_keys(record, {"task_id", "provenance", "baseline_run_digest", "candidate_run_digest"}, path)
        provenance = _require_provenance(record["provenance"], f"{path}.provenance")
        return cls(
            require_identifier(record["task_id"], f"{path}.task_id"),
            provenance,
            require_sha256(record["baseline_run_digest"], f"{path}.baseline_run_digest"),
            require_sha256(record["candidate_run_digest"], f"{path}.candidate_run_digest"),
        )


@dataclass(frozen=True)
class Distribution:
    values: tuple[int, ...]
    count: int
    total: int
    minimum: int | None
    maximum: int | None
    mean: int | None

    @classmethod
    def from_values(cls, values: tuple[int, ...]) -> "Distribution":
        ordered = tuple(values)
        count = len(ordered)
        total = sum(ordered)
        return cls(ordered, count, total, min(ordered) if ordered else None, max(ordered) if ordered else None, total // count if ordered else None)

    def to_dict(self) -> dict[str, Any]:
        return {
            "values": list(self.values),
            "count": self.count,
            "total": self.total,
            "minimum": self.minimum,
            "maximum": self.maximum,
            "mean": self.mean,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "Distribution":
        record = require_record(value, path)
        require_exact_keys(record, {"values", "count", "total", "minimum", "maximum", "mean"}, path)
        raw_values = require_type(record["values"], list, f"{path}.values")
        values = tuple(require_bounded_int(item, f"{path}.values[{index}]") for index, item in enumerate(raw_values))
        count = require_int(record["count"], f"{path}.count")
        total = require_bounded_int(record["total"], f"{path}.total")
        minimum = require_nullable_int(record["minimum"], f"{path}.minimum")
        maximum = require_nullable_int(record["maximum"], f"{path}.maximum")
        mean = require_nullable_int(record["mean"], f"{path}.mean")
        expected = cls.from_values(values)
        if (count, total, minimum, maximum, mean) != (expected.count, expected.total, expected.minimum, expected.maximum, expected.mean):
            raise ModelValidationError(f"{path} distribution summary does not match values")
        return cls(values, count, total, minimum, maximum, mean)


@dataclass(frozen=True)
class TaskDifference:
    task_id: str
    family_id: str
    provenance: PROVENANCE
    baseline_status: str
    candidate_status: str
    baseline_score_millis: int | None
    candidate_score_millis: int | None
    delta_millis: int | None
    classification: str
    regression_severity: str
    possible_contamination: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "family_id": self.family_id,
            "provenance": self.provenance,
            "baseline_status": self.baseline_status,
            "candidate_status": self.candidate_status,
            "baseline_score_millis": self.baseline_score_millis,
            "candidate_score_millis": self.candidate_score_millis,
            "delta_millis": self.delta_millis,
            "classification": self.classification,
            "regression_severity": self.regression_severity,
            "possible_contamination": self.possible_contamination,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "TaskDifference":
        record = require_record(value, path)
        require_exact_keys(record, {"task_id", "family_id", "provenance", "baseline_status", "candidate_status", "baseline_score_millis", "candidate_score_millis", "delta_millis", "classification", "regression_severity", "possible_contamination"}, path)
        provenance = _require_provenance(record["provenance"], f"{path}.provenance")
        contamination = require_nullable_string(record["possible_contamination"], f"{path}.possible_contamination")
        if provenance == "public_reference" and contamination != POSSIBLE_CONTAMINATION:
            raise ModelValidationError(f"{path}.possible_contamination must equal {POSSIBLE_CONTAMINATION}")
        if provenance == "held_out" and contamination is not None:
            raise ModelValidationError(f"{path}.possible_contamination must be null for held_out scores")
        return cls(
            require_identifier(record["task_id"], f"{path}.task_id"),
            require_identifier(record["family_id"], f"{path}.family_id"),
            provenance,
            require_string(record["baseline_status"], f"{path}.baseline_status"),
            require_string(record["candidate_status"], f"{path}.candidate_status"),
            require_nullable_int(record["baseline_score_millis"], f"{path}.baseline_score_millis"),
            require_nullable_int(record["candidate_score_millis"], f"{path}.candidate_score_millis"),
            require_nullable_int(record["delta_millis"], f"{path}.delta_millis"),
            require_string(record["classification"], f"{path}.classification"),
            require_string(record["regression_severity"], f"{path}.regression_severity"),
            contamination,
        )


@dataclass(frozen=True)
class FamilyDifference:
    family_id: str
    provenance: PROVENANCE
    task_count: int
    baseline_mean_millis: int | None
    candidate_mean_millis: int | None
    delta_millis: int | None
    possible_contamination: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "family_id": self.family_id,
            "provenance": self.provenance,
            "task_count": self.task_count,
            "baseline_mean_millis": self.baseline_mean_millis,
            "candidate_mean_millis": self.candidate_mean_millis,
            "delta_millis": self.delta_millis,
            "possible_contamination": self.possible_contamination,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "FamilyDifference":
        record = require_record(value, path)
        require_exact_keys(record, {"family_id", "provenance", "task_count", "baseline_mean_millis", "candidate_mean_millis", "delta_millis", "possible_contamination"}, path)
        provenance = _require_provenance(record["provenance"], f"{path}.provenance")
        contamination = require_nullable_string(record["possible_contamination"], f"{path}.possible_contamination")
        if provenance == "public_reference" and contamination != POSSIBLE_CONTAMINATION:
            raise ModelValidationError(f"{path}.possible_contamination must equal {POSSIBLE_CONTAMINATION}")
        if provenance == "held_out" and contamination is not None:
            raise ModelValidationError(f"{path}.possible_contamination must be null for held_out scores")
        return cls(
            require_identifier(record["family_id"], f"{path}.family_id"),
            provenance,
            require_int(record["task_count"], f"{path}.task_count"),
            require_nullable_int(record["baseline_mean_millis"], f"{path}.baseline_mean_millis"),
            require_nullable_int(record["candidate_mean_millis"], f"{path}.candidate_mean_millis"),
            require_nullable_int(record["delta_millis"], f"{path}.delta_millis"),
            contamination,
        )


@dataclass(frozen=True)
class EvaluationSection:
    provenance: PROVENANCE
    possible_contamination: str | None
    baseline_distribution: Distribution
    candidate_distribution: Distribution
    task_scores: tuple[TaskDifference, ...]
    family_differences: tuple[FamilyDifference, ...]
    task_count: int
    claim_eligible: bool
    baseline_mean_millis: int | None
    candidate_mean_millis: int | None
    delta_millis: int | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "provenance": self.provenance,
            "possible_contamination": self.possible_contamination,
            "score_distributions": {
                "baseline": self.baseline_distribution.to_dict(),
                "candidate": self.candidate_distribution.to_dict(),
            },
            "task_scores": [score.to_dict() for score in self.task_scores],
            "family_differences": [difference.to_dict() for difference in self.family_differences],
            "task_count": self.task_count,
            "claim_eligible": self.claim_eligible,
            "baseline_mean_millis": self.baseline_mean_millis,
            "candidate_mean_millis": self.candidate_mean_millis,
            "delta_millis": self.delta_millis,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "EvaluationSection":
        record = require_record(value, path)
        require_exact_keys(record, {"provenance", "possible_contamination", "score_distributions", "task_scores", "family_differences", "task_count", "claim_eligible", "baseline_mean_millis", "candidate_mean_millis", "delta_millis"}, path)
        provenance = _require_provenance(record["provenance"], f"{path}.provenance")
        contamination = require_nullable_string(record["possible_contamination"], f"{path}.possible_contamination")
        if provenance == "public_reference" and contamination != POSSIBLE_CONTAMINATION:
            raise ModelValidationError(f"{path}.possible_contamination must equal {POSSIBLE_CONTAMINATION}")
        if provenance == "held_out" and contamination is not None:
            raise ModelValidationError(f"{path}.possible_contamination must be null for held_out scores")
        distributions = require_record(record["score_distributions"], f"{path}.score_distributions")
        require_exact_keys(distributions, {"baseline", "candidate"}, f"{path}.score_distributions")
        baseline_distribution = Distribution.from_dict(distributions["baseline"], f"{path}.score_distributions.baseline")
        candidate_distribution = Distribution.from_dict(distributions["candidate"], f"{path}.score_distributions.candidate")
        raw_scores = require_type(record["task_scores"], list, f"{path}.task_scores")
        scores = tuple(TaskDifference.from_dict(item, f"{path}.task_scores[{index}]") for index, item in enumerate(raw_scores))
        if any(score.provenance != provenance for score in scores):
            raise ModelValidationError(f"{path}.task_scores contain another provenance")
        raw_families = require_type(record["family_differences"], list, f"{path}.family_differences")
        families = tuple(FamilyDifference.from_dict(item, f"{path}.family_differences[{index}]") for index, item in enumerate(raw_families))
        if any(difference.provenance != provenance for difference in families):
            raise ModelValidationError(f"{path}.family_differences contain another provenance")
        claim_eligible = require_bool(record["claim_eligible"], f"{path}.claim_eligible")
        if provenance == "public_reference" and claim_eligible:
            raise ModelValidationError(f"{path}.public_reference cannot be claim eligible")
        task_count = require_int(record["task_count"], f"{path}.task_count")
        if task_count != len(scores):
            raise ModelValidationError(f"{path}.task_count does not match task_scores")
        valid_scores = [score for score in scores if score.baseline_score_millis is not None and score.candidate_score_millis is not None and score.delta_millis is not None]
        expected_baseline_distribution = Distribution.from_values(tuple(score.baseline_score_millis for score in valid_scores if score.baseline_score_millis is not None))
        expected_candidate_distribution = Distribution.from_values(tuple(score.candidate_score_millis for score in valid_scores if score.candidate_score_millis is not None))
        if baseline_distribution != expected_baseline_distribution or candidate_distribution != expected_candidate_distribution:
            raise ModelValidationError(f"{path}.score_distributions do not match task_scores")
        baseline_mean = baseline_distribution.mean
        candidate_mean = candidate_distribution.mean
        delta = candidate_mean - baseline_mean if baseline_mean is not None and candidate_mean is not None else None
        if (record["baseline_mean_millis"], record["candidate_mean_millis"], record["delta_millis"]) != (baseline_mean, candidate_mean, delta):
            raise ModelValidationError(f"{path} summary does not match task_scores")
        if claim_eligible and not (provenance == "held_out" and bool(scores) and len(valid_scores) == len(scores)):
            raise ModelValidationError(f"{path}.claim_eligible does not match the provenance and score validity")
        if sum(difference.task_count for difference in families) != task_count:
            raise ModelValidationError(f"{path}.family_differences counts do not match task_scores")
        if {difference.family_id for difference in families} != {score.family_id for score in scores}:
            raise ModelValidationError(f"{path}.family_differences do not cover task_scores")
        return cls(
            provenance,
            contamination,
            baseline_distribution,
            candidate_distribution,
            scores,
            families,
            task_count,
            claim_eligible,
            require_nullable_int(record["baseline_mean_millis"], f"{path}.baseline_mean_millis"),
            require_nullable_int(record["candidate_mean_millis"], f"{path}.candidate_mean_millis"),
            require_nullable_int(record["delta_millis"], f"{path}.delta_millis"),
        )


@dataclass(frozen=True)
class RegressionSummary:
    severe_task_ids: tuple[str, ...]
    non_severe_task_ids: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "severe": list(self.severe_task_ids),
            "non_severe": list(self.non_severe_task_ids),
            "severe_count": len(self.severe_task_ids),
            "non_severe_count": len(self.non_severe_task_ids),
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "RegressionSummary":
        record = require_record(value, path)
        require_exact_keys(record, {"severe", "non_severe", "severe_count", "non_severe_count"}, path)
        severe = tuple(require_identifier(item, f"{path}.severe[{index}]") for index, item in enumerate(require_type(record["severe"], list, f"{path}.severe")))
        non_severe = tuple(require_identifier(item, f"{path}.non_severe[{index}]") for index, item in enumerate(require_type(record["non_severe"], list, f"{path}.non_severe")))
        if require_int(record["severe_count"], f"{path}.severe_count") != len(severe) or require_int(record["non_severe_count"], f"{path}.non_severe_count") != len(non_severe):
            raise ModelValidationError(f"{path} counts do not match task ids")
        return cls(severe, non_severe)


def _percentage(value: int | None) -> str:
    if value is None:
        return "unavailable"
    sign = "-" if value < 0 else ""
    magnitude = abs(value)
    whole, remainder = divmod(magnitude, 10)
    return f"{sign}{whole}" if remainder == 0 else f"{sign}{whole}.{remainder}"


def _percentage_phrase(value: int | None) -> str:
    rendered = _percentage(abs(value) if value is not None else None)
    return f"{rendered} percentage point" if value is not None and abs(value) == 10 else f"{rendered} percentage points"


def _regression_sentence(regressions: RegressionSummary) -> str:
    count = len(regressions.severe_task_ids)
    if count == 0:
        return "no severe regressions"
    return f"{count} severe regression" if count == 1 else f"{count} severe regressions"


def render_decision_sentence(
    outcome: Outcome,
    candidate_mean_millis: int | None,
    point_delta_millis: int | None,
    regressions: RegressionSummary,
) -> str:
    final = _percentage(candidate_mean_millis)
    if outcome == "positive":
        return f"This skill improved held-out performance by {_percentage_phrase(point_delta_millis)}, ending at {final}%, with {_regression_sentence(regressions)}."
    if outcome == "negative":
        return f"This skill hurt held-out performance by {_percentage_phrase(point_delta_millis)}, ending at {final}%, with {_regression_sentence(regressions)}."
    if outcome == "null":
        return f"This skill showed no measurable change on the held-out result, ending at {final}%, with {_regression_sentence(regressions)}."
    if outcome == "invalid":
        return "This single-run comparison was invalid because the receipt-backed held-out result was not valid."
    return "This single-run comparison could not tell whether the skill produced a measured improvement on the held-out result."


def derive_outcome(
    decision_rule: DecisionRule,
    scored_evaluation: EvaluationSection,
    calibration: EvaluationSection | None,
) -> Outcome:
    if decision_rule.primary_metric != "score_millis":
        raise ModelValidationError("uplift decision rule primary metric is not receipt-backed")
    all_scores = (*scored_evaluation.task_scores, *(calibration.task_scores if calibration is not None else ()))
    if "any_arm_not_completed" in decision_rule.invalid_conditions and any(
        score.baseline_status != "completed" or score.candidate_status != "completed" for score in all_scores
    ):
        return "invalid"
    if "missing_score" in decision_rule.invalid_conditions and any(score.delta_millis is None for score in all_scores):
        return "invalid"
    valid_count = sum(score.delta_millis is not None for score in scored_evaluation.task_scores)
    if valid_count < decision_rule.minimum_valid_task_count:
        return "inconclusive" if "valid_task_count_below_minimum" in decision_rule.inconclusive_conditions else "invalid"
    point_delta = scored_evaluation.delta_millis
    if point_delta is None:
        return "inconclusive"
    if point_delta >= decision_rule.positive_threshold_millis:
        return "positive"
    if point_delta <= decision_rule.negative_threshold_millis:
        return "negative"
    if abs(point_delta) <= decision_rule.null_band_millis:
        return "null"
    return "inconclusive" if "delta_between_thresholds" in decision_rule.inconclusive_conditions else "invalid"


def relative_error_reduction_millis(
    primary_metric: str,
    baseline_mean_millis: int | None,
    candidate_mean_millis: int | None,
) -> int | None:
    if primary_metric != "score_millis" or baseline_mean_millis is None or candidate_mean_millis is None:
        return None
    baseline_error = 1_000 - baseline_mean_millis
    if baseline_error <= 0:
        return None
    return round((baseline_error - (1_000 - candidate_mean_millis)) * 1_000 / baseline_error)


@dataclass(frozen=True)
class Uncertainty:
    treatment: str
    point_delta_millis: int | None
    confidence_interval: None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "treatment": self.treatment,
            "point_delta_millis": self.point_delta_millis,
            "confidence_interval": self.confidence_interval,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "Uncertainty":
        record = require_record(value, path)
        require_exact_keys(record, {"treatment", "point_delta_millis", "confidence_interval"}, path)
        if record["confidence_interval"] is not None:
            raise ModelValidationError(f"{path}.confidence_interval must be null for declared point uncertainty")
        return cls(
            require_string(record["treatment"], f"{path}.treatment"),
            require_nullable_int(record["point_delta_millis"], f"{path}.point_delta_millis"),
        )


@dataclass(frozen=True)
class Freshness:
    status: str
    as_of: str | None
    invalidation_triggers: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {"status": self.status, "as_of": self.as_of, "invalidation_triggers": list(self.invalidation_triggers)}

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "Freshness":
        record = require_record(value, path)
        require_exact_keys(record, {"status", "as_of", "invalidation_triggers"}, path)
        return cls(require_string(record["status"], f"{path}.status"), require_nullable_string(record["as_of"], f"{path}.as_of"), _require_nullable_string_list(record["invalidation_triggers"], f"{path}.invalidation_triggers"))


@dataclass(frozen=True)
class ActionReceipt:
    action_id: str
    capability_id: str
    action_kind: str
    resource_type: str
    resource_id: str
    status: str
    idempotency_key: str
    created_at: str | None
    updated_at: str | None
    public_url: str | None
    next_recommended_action: str
    next_poll_at: str | None
    approval_required: bool
    chain_id: int | None
    transaction_hash: str | None
    error_code: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "action_id": self.action_id,
            "capability_id": self.capability_id,
            "action_kind": self.action_kind,
            "resource_type": self.resource_type,
            "resource_id": self.resource_id,
            "status": self.status,
            "idempotency_key": self.idempotency_key,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "public_url": self.public_url,
            "next_recommended_action": self.next_recommended_action,
            "next_poll_at": self.next_poll_at,
            "approval_required": self.approval_required,
            "chain_id": self.chain_id,
            "transaction_hash": self.transaction_hash,
            "error_code": self.error_code,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str = "action_receipt") -> "ActionReceipt":
        record = require_record(value, path)
        require_exact_keys(record, {"action_id", "capability_id", "action_kind", "resource_type", "resource_id", "status", "idempotency_key", "created_at", "updated_at", "public_url", "next_recommended_action", "next_poll_at", "approval_required", "chain_id", "transaction_hash", "error_code"}, path)
        chain_id = record["chain_id"]
        if chain_id is not None:
            chain_id = require_int(chain_id, f"{path}.chain_id")
        return cls(
            require_identifier(record["action_id"], f"{path}.action_id"),
            require_identifier(record["capability_id"], f"{path}.capability_id"),
            require_identifier(record["action_kind"], f"{path}.action_kind"),
            require_identifier(record["resource_type"], f"{path}.resource_type"),
            require_identifier(record["resource_id"], f"{path}.resource_id"),
            require_identifier(record["status"], f"{path}.status"),
            require_identifier(record["idempotency_key"], f"{path}.idempotency_key"),
            require_nullable_string(record["created_at"], f"{path}.created_at"),
            require_nullable_string(record["updated_at"], f"{path}.updated_at"),
            require_nullable_string(record["public_url"], f"{path}.public_url"),
            require_string(record["next_recommended_action"], f"{path}.next_recommended_action"),
            require_nullable_string(record["next_poll_at"], f"{path}.next_poll_at"),
            require_bool(record["approval_required"], f"{path}.approval_required"),
            chain_id,
            require_nullable_string(record["transaction_hash"], f"{path}.transaction_hash"),
            require_nullable_string(record["error_code"], f"{path}.error_code"),
        )


@dataclass(frozen=True)
class UpliftReport:
    schema_version: int
    report_id: str
    receipt_digests: tuple[str, ...]
    protocol_id: str
    family_id: str
    challenge_revision_id: str
    arms: tuple[ArmIdentity, ...]
    receipt_bindings: tuple[ReceiptTaskBinding, ...]
    decision_rule: DecisionRule
    scored_evaluation: EvaluationSection
    calibration: EvaluationSection | None
    outcome: Outcome
    final_capability_level: dict[str, int | None]
    measured_change: dict[str, int | None]
    uncertainty: Uncertainty
    regressions: RegressionSummary
    cost_latency: dict[str, dict[str, Distribution]]
    disclosures: dict[str, Any]
    limitations: tuple[str, ...]
    freshness: Freshness
    evidence_class: str
    reproduction_status: str
    reproduction_package_status: str
    decision_sentence: str
    reproduction_package_digest: str | None
    action_receipt: ActionReceipt

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "report_id": self.report_id,
            "comparison": {
                "receipt_digests": list(self.receipt_digests),
                "protocol_id": self.protocol_id,
                "family_id": self.family_id,
                "challenge_revision_id": self.challenge_revision_id,
            },
            "arms": [arm.to_dict() for arm in self.arms],
            "receipt_bindings": [binding.to_dict() for binding in self.receipt_bindings],
            "decision_rule": self.decision_rule.to_dict(),
            "scored_evaluation": self.scored_evaluation.to_dict(),
            "calibration": self.calibration.to_dict() if self.calibration is not None else None,
            "outcome": self.outcome,
            "final_capability_level": self.final_capability_level,
            "measured_change": self.measured_change,
            "uncertainty": self.uncertainty.to_dict(),
            "regressions": self.regressions.to_dict(),
            "cost_latency": {
                arm: {metric: distribution.to_dict() for metric, distribution in metrics.items()}
                for arm, metrics in self.cost_latency.items()
            },
            "disclosures": self.disclosures,
            "limitations": list(self.limitations),
            "freshness": self.freshness.to_dict(),
            "evidence_class": self.evidence_class,
            "reproduction_status": self.reproduction_status,
            "reproduction_package_status": self.reproduction_package_status,
            "decision_sentence": self.decision_sentence,
            "reproduction_package": (
                {"algorithm": "sha256", "digest": self.reproduction_package_digest}
                if self.reproduction_package_digest is not None
                else None
            ),
            "action_receipt": self.action_receipt.to_dict(),
        }

    @staticmethod
    def expected_report_id(value: Any) -> str:
        record = require_record(value, "uplift_report")
        identity = dict(record)
        identity.pop("report_id", None)
        identity.pop("action_receipt", None)
        return content_id("uplift-report", identity)

    def validate_against_receipts(self, receipts: Sequence["EvaluationReceipt"]) -> None:
        if not receipts:
            raise ModelValidationError("uplift report must be anchored to a non-empty receipt set")

        # Rebuild the comparison from the authoritative receipt records.  The
        # report may carry derived summaries and human-facing disclosures, but
        # none of those fields may become a second source of score truth.
        from verify_runtime.uplift.compare import _compare_receipt_records

        try:
            expected = _compare_receipt_records(tuple((receipt.content_digest(), receipt) for receipt in receipts))
        except (TypeError, ValueError, KeyError) as error:
            raise ModelValidationError(f"receipt comparison is invalid: {error}") from error
        if self.receipt_digests != expected.receipt_digests:
            raise ModelValidationError("uplift report receipt digests are not in canonical lexical order")
        if self.receipt_bindings != expected.receipt_bindings:
            raise ModelValidationError("uplift report receipt bindings are not in locked matched_order")
        if (
            self.protocol_id != expected.protocol.protocol_id
            or self.family_id != expected.protocol.family_id
            or self.challenge_revision_id != expected.protocol.challenge_revision_id
        ):
            raise ModelValidationError("uplift report protocol identity does not match the receipts")
        expected_arms = {arm.arm_id: arm for arm in expected.arms}
        actual_arms = {arm.arm_id: arm for arm in self.arms}
        if any(actual_arms.get(arm_id) != arm for arm_id, arm in expected_arms.items()):
            raise ModelValidationError("uplift report arms are not receipt-derived")
        if self.decision_rule != expected.protocol.decision_rule:
            raise ModelValidationError("uplift report decision rule is not receipt-derived")
        if self.scored_evaluation != expected.scored_evaluation or self.calibration != expected.calibration:
            raise ModelValidationError("uplift report score sections are not receipt-derived")
        if self.outcome != expected.outcome:
            raise ModelValidationError("uplift report outcome is not receipt-derived")
        if self.final_capability_level != {
            "scale": "score_millis",
            "baseline": expected.scored_evaluation.baseline_mean_millis,
            "candidate": expected.scored_evaluation.candidate_mean_millis,
        }:
            raise ModelValidationError("uplift report final capability is not receipt-derived")
        expected_change = {
            "absolute_delta_millis": expected.scored_evaluation.delta_millis,
            "relative_error_reduction_millis": relative_error_reduction_millis(
                expected.protocol.decision_rule.primary_metric,
                expected.scored_evaluation.baseline_mean_millis,
                expected.scored_evaluation.candidate_mean_millis,
            ),
        }
        if self.measured_change != expected_change:
            raise ModelValidationError("uplift report measured change is not receipt-derived")
        if self.uncertainty != Uncertainty("declared-point-delta", expected.point_delta_millis):
            raise ModelValidationError("uplift report uncertainty is not receipt-derived")
        if self.regressions != expected.regressions:
            raise ModelValidationError("uplift report regressions are not receipt-derived")
        if self.cost_latency != expected.cost_latency:
            raise ModelValidationError("uplift report cost and latency are not receipt-derived")
        if self.disclosures != expected.disclosures:
            raise ModelValidationError("uplift report disclosures are not receipt-derived")
        if self.freshness != expected.freshness:
            raise ModelValidationError("uplift report freshness is not receipt-derived")
        if self.decision_sentence != render_decision_sentence(
            expected.outcome,
            expected.scored_evaluation.candidate_mean_millis,
            expected.point_delta_millis,
            expected.regressions,
        ):
            raise ModelValidationError("uplift report decision sentence is not receipt-derived")

    @classmethod
    def from_dict(cls, value: Any) -> "UpliftReport":
        record = require_record(value, "uplift_report")
        require_exact_keys(record, {"schema_version", "report_id", "comparison", "arms", "receipt_bindings", "decision_rule", "scored_evaluation", "calibration", "outcome", "final_capability_level", "measured_change", "uncertainty", "regressions", "cost_latency", "disclosures", "limitations", "freshness", "evidence_class", "reproduction_status", "reproduction_package_status", "decision_sentence", "reproduction_package", "action_receipt"}, "uplift_report")
        report_id = require_identifier(record["report_id"], "uplift_report.report_id")
        if report_id != cls.expected_report_id(record):
            raise ModelValidationError("uplift_report.report_id does not match the canonical report content")
        comparison = require_record(record["comparison"], "uplift_report.comparison")
        require_exact_keys(comparison, {"receipt_digests", "protocol_id", "family_id", "challenge_revision_id"}, "uplift_report.comparison")
        digests = require_type(comparison["receipt_digests"], list, "uplift_report.comparison.receipt_digests")
        if not digests:
            raise ModelValidationError("uplift_report.comparison.receipt_digests must be non-empty")
        receipt_digests = tuple(require_sha256(item, f"uplift_report.comparison.receipt_digests[{index}]") for index, item in enumerate(digests))
        if len(set(receipt_digests)) != len(receipt_digests):
            raise ModelValidationError("uplift_report.comparison.receipt_digests must be distinct")
        if receipt_digests != tuple(sorted(receipt_digests)):
            raise ModelValidationError("uplift_report.comparison.receipt_digests must use canonical lexical order")
        arms_raw = require_type(record["arms"], list, "uplift_report.arms")
        arms = tuple(ArmIdentity.from_dict(item, f"uplift_report.arms[{index}]") for index, item in enumerate(arms_raw))
        arm_ids = {arm.arm_id for arm in arms}
        if len(arm_ids) != len(arms):
            raise ModelValidationError("uplift_report.arms must not contain duplicate arm ids")
        if not {"baseline", "candidate"} <= arm_ids:
            raise ModelValidationError("uplift_report.arms must contain baseline and candidate")
        bindings_raw = require_type(record["receipt_bindings"], list, "uplift_report.receipt_bindings")
        receipt_bindings = tuple(ReceiptTaskBinding.from_dict(item, f"uplift_report.receipt_bindings[{index}]") for index, item in enumerate(bindings_raw))
        binding_ids = {binding.task_id for binding in receipt_bindings}
        if len(binding_ids) != len(receipt_bindings):
            raise ModelValidationError("uplift_report.receipt_bindings must not contain duplicate task ids")
        outcome = require_string(record["outcome"], "uplift_report.outcome")
        if outcome not in OUTCOMES:
            raise ModelValidationError("uplift_report.outcome is invalid")
        levels = require_record(record["final_capability_level"], "uplift_report.final_capability_level")
        require_exact_keys(levels, {"scale", "baseline", "candidate"}, "uplift_report.final_capability_level")
        level_scale = require_identifier(levels["scale"], "uplift_report.final_capability_level.scale")
        level_baseline = require_nullable_int(levels["baseline"], "uplift_report.final_capability_level.baseline")
        level_candidate = require_nullable_int(levels["candidate"], "uplift_report.final_capability_level.candidate")
        change = require_record(record["measured_change"], "uplift_report.measured_change")
        require_exact_keys(change, {"absolute_delta_millis", "relative_error_reduction_millis"}, "uplift_report.measured_change")
        absolute_change = require_nullable_int(change["absolute_delta_millis"], "uplift_report.measured_change.absolute_delta_millis")
        relative_change = require_nullable_int(change["relative_error_reduction_millis"], "uplift_report.measured_change.relative_error_reduction_millis")
        cost_latency = require_record(record["cost_latency"], "uplift_report.cost_latency")
        require_exact_keys(cost_latency, {"baseline", "candidate"}, "uplift_report.cost_latency")
        normalized_distributions: dict[str, dict[str, Distribution]] = {}
        for arm in ("baseline", "candidate"):
            metrics = require_record(cost_latency[arm], f"uplift_report.cost_latency.{arm}")
            require_exact_keys(metrics, {"cost_usd_cents", "wall_time_ms"}, f"uplift_report.cost_latency.{arm}")
            normalized_distributions[arm] = {
                metric: Distribution.from_dict(metrics[metric], f"uplift_report.cost_latency.{arm}.{metric}")
                for metric in ("cost_usd_cents", "wall_time_ms")
            }
        decision_rule = DecisionRule.from_dict(record["decision_rule"])
        evidence_class = require_string(record["evidence_class"], "uplift_report.evidence_class")
        if evidence_class != EVIDENCE_CLASS:
            raise ModelValidationError("uplift_report.evidence_class must be single_run")
        reproduction_status = require_string(record["reproduction_status"], "uplift_report.reproduction_status")
        if reproduction_status != REPRODUCTION_STATUS:
            raise ModelValidationError("uplift_report.reproduction_status must be none")
        reproduction_package_status = require_string(record["reproduction_package_status"], "uplift_report.reproduction_package_status")
        if reproduction_package_status not in REPRODUCTION_PACKAGE_STATUSES:
            raise ModelValidationError("uplift_report.reproduction_package_status is invalid")
        decision_sentence = require_string(record["decision_sentence"], "uplift_report.decision_sentence")
        if "\n" in decision_sentence or "!" in decision_sentence or "?" in decision_sentence or ". " in decision_sentence or not decision_sentence.endswith("."):
            raise ModelValidationError("uplift_report.decision_sentence must be one plain-language sentence")
        package = record["reproduction_package"]
        package_digest: str | None
        if reproduction_package_status == "available":
            package_record = require_record(package, "uplift_report.reproduction_package")
            require_exact_keys(package_record, {"algorithm", "digest"}, "uplift_report.reproduction_package")
            if package_record["algorithm"] != "sha256":
                raise ModelValidationError("uplift_report.reproduction_package.algorithm must be sha256")
            package_digest = require_sha256(package_record["digest"], "uplift_report.reproduction_package.digest")
        else:
            if package is not None:
                raise ModelValidationError("uplift_report.reproduction_package must be null when status is absent")
            package_digest = None
        scored_evaluation = EvaluationSection.from_dict(record["scored_evaluation"], "uplift_report.scored_evaluation")
        calibration_value = record["calibration"]
        calibration = None if calibration_value is None else EvaluationSection.from_dict(calibration_value, "uplift_report.calibration")
        if scored_evaluation.provenance != "held_out":
            raise ModelValidationError("uplift_report.scored_evaluation must use held_out provenance")
        reference_bindings = {binding.task_id for binding in receipt_bindings if binding.provenance == "public_reference"}
        held_out_bindings = {binding.task_id for binding in receipt_bindings if binding.provenance == "held_out"}
        if bool(reference_bindings) != (calibration is not None):
            raise ModelValidationError("uplift_report.calibration presence does not match receipt-embedded reference tasks")
        if calibration is not None and calibration.provenance != "public_reference":
            raise ModelValidationError("uplift_report.calibration must use public_reference provenance")
        if {score.task_id for score in scored_evaluation.task_scores} != held_out_bindings:
            raise ModelValidationError("uplift_report.scored_evaluation tasks do not match receipt-embedded provenance")
        if calibration is not None and {score.task_id for score in calibration.task_scores} != reference_bindings:
            raise ModelValidationError("uplift_report.calibration tasks do not match receipt-embedded provenance")
        binding_by_task = {binding.task_id: binding for binding in receipt_bindings}
        for score in (*scored_evaluation.task_scores, *(calibration.task_scores if calibration is not None else ())):
            if binding_by_task[score.task_id].provenance != score.provenance:
                raise ModelValidationError("uplift_report score provenance is not receipt-anchored")
        valid_scored = [score for score in scored_evaluation.task_scores if score.delta_millis is not None and score.baseline_score_millis is not None and score.candidate_score_millis is not None]
        expected_claim = bool(valid_scored) and len(valid_scored) == len(scored_evaluation.task_scores) and len(valid_scored) >= decision_rule.minimum_valid_task_count
        if scored_evaluation.claim_eligible != expected_claim:
            raise ModelValidationError("uplift_report.scored_evaluation.claim_eligible does not match the declared decision rule")
        uncertainty = Uncertainty.from_dict(record["uncertainty"], "uplift_report.uncertainty")
        regressions = RegressionSummary.from_dict(record["regressions"], "uplift_report.regressions")
        expected_outcome = derive_outcome(decision_rule, scored_evaluation, calibration)
        if outcome != expected_outcome:
            raise ModelValidationError("uplift_report.outcome does not match the embedded decision rule and scored data")
        if absolute_change != scored_evaluation.delta_millis or uncertainty.point_delta_millis != scored_evaluation.delta_millis:
            raise ModelValidationError("uplift_report measured change does not match the scored evaluation")
        expected_relative_change = relative_error_reduction_millis(decision_rule.primary_metric, scored_evaluation.baseline_mean_millis, scored_evaluation.candidate_mean_millis)
        if relative_change != expected_relative_change:
            raise ModelValidationError("uplift_report relative error reduction does not match the scored evaluation")
        if level_scale != "score_millis" or (level_baseline, level_candidate) != (scored_evaluation.baseline_mean_millis, scored_evaluation.candidate_mean_millis):
            raise ModelValidationError("uplift_report final capability does not match the scored evaluation")
        if absolute_change is not None and (level_baseline is None or level_candidate is None):
            raise ModelValidationError("uplift_report final capability is required when measured change is present")
        expected_sentence = render_decision_sentence(outcome, scored_evaluation.candidate_mean_millis, uncertainty.point_delta_millis, regressions)
        if decision_sentence != expected_sentence:
            raise ModelValidationError("uplift_report.decision_sentence does not match the deterministic generator")
        action_receipt = ActionReceipt.from_dict(record["action_receipt"], "uplift_report.action_receipt")
        if action_receipt.resource_id != report_id:
            raise ModelValidationError("uplift_report action receipt does not name the report")
        if action_receipt.action_id != content_id("action", {"report_id": report_id, "package_digest": package_digest}):
            raise ModelValidationError("uplift_report action receipt is not derived from the report")
        if action_receipt.idempotency_key != content_id("uplift-action", {"receipt_digests": list(receipt_digests)}):
            raise ModelValidationError("uplift_report action receipt idempotency key is not keyed to the canonical receipt set")
        return cls(
            require_schema_version(record["schema_version"], "uplift_report.schema_version"),
            report_id,
            receipt_digests,
            require_identifier(comparison["protocol_id"], "uplift_report.comparison.protocol_id"),
            require_identifier(comparison["family_id"], "uplift_report.comparison.family_id"),
            require_identifier(comparison["challenge_revision_id"], "uplift_report.comparison.challenge_revision_id"),
            arms,
            receipt_bindings,
            decision_rule,
            scored_evaluation,
            calibration,
            outcome,  # type: ignore[arg-type]
            {
                "scale": level_scale,
                "baseline": level_baseline,
                "candidate": level_candidate,
            },
            {
                "absolute_delta_millis": absolute_change,
                "relative_error_reduction_millis": relative_change,
            },
            uncertainty,
            regressions,
            normalized_distributions,
            require_record(record["disclosures"], "uplift_report.disclosures"),
            tuple(require_string_list(record["limitations"], "uplift_report.limitations")),
            Freshness.from_dict(record["freshness"], "uplift_report.freshness"),
            evidence_class,
            reproduction_status,
            reproduction_package_status,
            decision_sentence,
            package_digest,
            action_receipt,
        )
