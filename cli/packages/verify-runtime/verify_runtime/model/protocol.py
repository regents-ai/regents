"""Canonical locked evaluation protocol and founder-default policy records."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .base import (
    ModelValidationError,
    content_id,
    require_bounded_int,
    require_exact_keys,
    require_identifier,
    require_identifier_list,
    require_int,
    require_nullable_string,
    require_record,
    require_schema_version,
    require_sha256,
    require_string,
    require_string_list,
    require_type,
)
from .benchmark import PARTITIONS
from .taskset import TasksetPackageReference
from .task import TASK_PROVENANCES, TaskProvenance

INCONCLUSIVE_CONDITIONS = {"valid_task_count_below_minimum", "delta_between_thresholds"}
INVALID_CONDITIONS = {"any_arm_not_completed", "missing_score"}


def _string_pairs(value: Any, path: str) -> tuple[tuple[str, str], ...]:
    require_type(value, list, path)
    pairs: list[tuple[str, str]] = []
    names: set[str] = set()
    for index, item in enumerate(value):
        record = require_record(item, f"{path}[{index}]")
        require_exact_keys(record, {"name", "value"}, f"{path}[{index}]")
        name = require_string(record["name"], f"{path}[{index}].name")
        if name in names:
            raise ValueError(f"{path} has duplicate name: {name}")
        names.add(name)
        pairs.append((name, require_string(record["value"], f"{path}[{index}].value", allow_empty=True)))
    return tuple(pairs)


@dataclass(frozen=True)
class VerifyPolicy:
    policy_id: str
    attempts_per_task: int
    max_task_wall_seconds: int
    max_comparison_spend_usd_cents: int
    timeout_treatment: str
    missing_result_treatment: str
    infrastructure_failure_treatment: str

    def to_dict(self) -> dict[str, Any]:
        return {"policy_id": self.policy_id, "attempts_per_task": self.attempts_per_task, "max_task_wall_seconds": self.max_task_wall_seconds, "max_comparison_spend_usd_cents": self.max_comparison_spend_usd_cents, "timeout_treatment": self.timeout_treatment, "missing_result_treatment": self.missing_result_treatment, "infrastructure_failure_treatment": self.infrastructure_failure_treatment}

    @classmethod
    def from_dict(cls, value: Any) -> "VerifyPolicy":
        record = require_record(value, "protocol.policy")
        require_exact_keys(record, {"policy_id", "attempts_per_task", "max_task_wall_seconds", "max_comparison_spend_usd_cents", "timeout_treatment", "missing_result_treatment", "infrastructure_failure_treatment"}, "protocol.policy")
        return cls(require_identifier(record["policy_id"], "protocol.policy.policy_id"), require_int(record["attempts_per_task"], "protocol.policy.attempts_per_task", minimum=1), require_int(record["max_task_wall_seconds"], "protocol.policy.max_task_wall_seconds", minimum=1), require_int(record["max_comparison_spend_usd_cents"], "protocol.policy.max_comparison_spend_usd_cents", minimum=1), require_string(record["timeout_treatment"], "protocol.policy.timeout_treatment"), require_string(record["missing_result_treatment"], "protocol.policy.missing_result_treatment"), require_string(record["infrastructure_failure_treatment"], "protocol.policy.infrastructure_failure_treatment"))


@dataclass(frozen=True)
class SevereRegressionRule:
    kind: str
    threshold_millis: int

    def to_dict(self) -> dict[str, Any]:
        return {"kind": self.kind, "threshold_millis": self.threshold_millis}

    @classmethod
    def from_dict(cls, value: Any) -> "SevereRegressionRule":
        record = require_record(value, "protocol.decision_rule.severe_regression_rule")
        require_exact_keys(record, {"kind", "threshold_millis"}, "protocol.decision_rule.severe_regression_rule")
        kind = require_identifier(record["kind"], "protocol.decision_rule.severe_regression_rule.kind")
        if kind != "delta_at_or_below":
            raise ValueError("protocol.decision_rule.severe_regression_rule.kind is invalid")
        return cls(kind, require_int(record["threshold_millis"], "protocol.decision_rule.severe_regression_rule.threshold_millis", minimum=1))


@dataclass(frozen=True)
class DecisionRule:
    primary_metric: str
    minimum_valid_task_count: int
    positive_threshold_millis: int
    negative_threshold_millis: int
    null_band_millis: int
    severe_regression_rule: SevereRegressionRule
    inconclusive_conditions: tuple[str, ...]
    invalid_conditions: tuple[str, ...]

    def __post_init__(self) -> None:
        if len(set(self.inconclusive_conditions)) != len(self.inconclusive_conditions):
            raise ValueError("protocol.decision_rule conditions must be unique")
        if len(set(self.invalid_conditions)) != len(self.invalid_conditions):
            raise ValueError("protocol.decision_rule conditions must be unique")
        if set(self.inconclusive_conditions) - INCONCLUSIVE_CONDITIONS:
            raise ValueError("protocol.decision_rule.inconclusive_conditions contains an unknown condition")
        if set(self.invalid_conditions) - INVALID_CONDITIONS:
            raise ValueError("protocol.decision_rule.invalid_conditions contains an unknown condition")

    def to_dict(self) -> dict[str, Any]:
        return {
            "primary_metric": self.primary_metric,
            "minimum_valid_task_count": self.minimum_valid_task_count,
            "positive_threshold_millis": self.positive_threshold_millis,
            "negative_threshold_millis": self.negative_threshold_millis,
            "null_band_millis": self.null_band_millis,
            "severe_regression_rule": self.severe_regression_rule.to_dict(),
            "inconclusive_conditions": list(self.inconclusive_conditions),
            "invalid_conditions": list(self.invalid_conditions),
        }

    @classmethod
    def from_dict(cls, value: Any) -> "DecisionRule":
        record = require_record(value, "protocol.decision_rule")
        require_exact_keys(
            record,
            {
                "primary_metric",
                "minimum_valid_task_count",
                "positive_threshold_millis",
                "negative_threshold_millis",
                "null_band_millis",
                "severe_regression_rule",
                "inconclusive_conditions",
                "invalid_conditions",
            },
            "protocol.decision_rule",
        )
        inconclusive = tuple(require_string_list(record["inconclusive_conditions"], "protocol.decision_rule.inconclusive_conditions"))
        invalid = tuple(require_string_list(record["invalid_conditions"], "protocol.decision_rule.invalid_conditions"))
        positive = require_bounded_int(record["positive_threshold_millis"], "protocol.decision_rule.positive_threshold_millis", minimum=0)
        negative = require_bounded_int(record["negative_threshold_millis"], "protocol.decision_rule.negative_threshold_millis")
        null_band = require_bounded_int(record["null_band_millis"], "protocol.decision_rule.null_band_millis", minimum=0)
        if positive <= null_band or negative >= -null_band:
            raise ValueError("protocol.decision_rule thresholds must leave a declared null band")
        return cls(
            require_identifier(record["primary_metric"], "protocol.decision_rule.primary_metric"),
            require_int(record["minimum_valid_task_count"], "protocol.decision_rule.minimum_valid_task_count", minimum=1),
            positive,
            negative,
            null_band,
            SevereRegressionRule.from_dict(record["severe_regression_rule"]),
            inconclusive,
            invalid,
        )


@dataclass(frozen=True)
class MatchedSelection:
    task_id: str
    partition: str
    matched_order: int
    provenance: TaskProvenance = "held_out"
    answer_key_commitment: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "partition": self.partition,
            "matched_order": self.matched_order,
            "provenance": self.provenance,
            "answer_key_commitment": self.answer_key_commitment,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "MatchedSelection":
        record = require_record(value, path)
        require_exact_keys(
            record,
            {"task_id", "partition", "matched_order", "provenance", "answer_key_commitment"},
            path,
        )
        partition = require_string(record["partition"], f"{path}.partition")
        if partition not in PARTITIONS:
            raise ValueError(f"{path}.partition is invalid")
        provenance = require_string(record["provenance"], f"{path}.provenance")
        if provenance not in TASK_PROVENANCES:
            raise ValueError(f"{path}.provenance is invalid")
        return cls(
            require_identifier(record["task_id"], f"{path}.task_id"),
            partition,
            require_int(record["matched_order"], f"{path}.matched_order", minimum=0),
            provenance,
            require_sha256(record["answer_key_commitment"], f"{path}.answer_key_commitment"),
        )  # type: ignore[arg-type]


@dataclass(frozen=True)
class EvaluationProtocol:
    schema_version: int
    protocol_id: str
    family_id: str
    baseline_capsule_id: str
    candidate_capsule_id: str
    intervention_class: str
    changed_files: tuple[str, ...]
    baseline_class: str
    baseline_justification: str
    selections: tuple[MatchedSelection, ...]
    development_task_ids: tuple[str, ...]
    validation_task_ids: tuple[str, ...]
    untouched_task_ids: tuple[str, ...]
    optimizer_method: str
    optimizer_candidate_count: int
    rejected_candidate_ids: tuple[str, ...]
    policy: VerifyPolicy
    taskset_version: TasksetPackageReference
    challenge_revision_id: str
    season_id: str | None
    treatment_skill_source: str
    treatment_skill_content: str
    treatment_diff: str
    exact_commands: tuple[str, ...]
    harness_settings: tuple[tuple[str, str], ...]
    seeds: tuple[str, ...]
    expected_output_schema: str
    decision_rule: DecisionRule

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "protocol_id": self.protocol_id,
            "family_id": self.family_id,
            "capsules": {"baseline": self.baseline_capsule_id, "candidate": self.candidate_capsule_id},
            "intervention": {"class": self.intervention_class, "changed_files": list(self.changed_files)},
            "baseline": {"class": self.baseline_class, "justification": self.baseline_justification},
            "matched_selections": [selection.to_dict() for selection in self.selections],
            "partitions": {"development": list(self.development_task_ids), "validation": list(self.validation_task_ids), "untouched": list(self.untouched_task_ids)},
            "optimizer_disclosure": {"method": self.optimizer_method, "candidate_count": self.optimizer_candidate_count, "rejected_candidate_ids": list(self.rejected_candidate_ids)},
            "policy": self.policy.to_dict(),
            "taskset": self.taskset_version.to_dict(),
            "season_id": self.season_id,
            "treatment": {
                "skill_source": self.treatment_skill_source,
                "skill_content": self.treatment_skill_content,
                "diff": self.treatment_diff,
            },
            "execution": {
                "exact_commands": list(self.exact_commands),
                "harness_settings": [{"name": name, "value": value} for name, value in self.harness_settings],
                "seeds": list(self.seeds),
                "expected_output_schema": self.expected_output_schema,
            },
            "decision_rule": self.decision_rule.to_dict(),
            "challenge_revision_id": self.challenge_revision_id,
        }

    def expected_protocol_id(self) -> str:
        identity = self.to_dict()
        identity.pop("protocol_id")
        return content_id("protocol", identity)

    @property
    def scored_task_ids(self) -> tuple[str, ...]:
        """The lock-derived claim selection; provenance is the authority."""

        return tuple(selection.task_id for selection in self.selections if selection.provenance == "held_out")

    @property
    def calibration_task_ids(self) -> tuple[str, ...]:
        """The lock-derived reference/calibration selection."""

        return tuple(selection.task_id for selection in self.selections if selection.provenance == "public_reference")

    def validate_evaluation_partition(self) -> None:
        partition_lists = (
            self.development_task_ids,
            self.validation_task_ids,
            self.untouched_task_ids,
        )
        partition_ids = tuple(task_id for values in partition_lists for task_id in values)
        if len(set(partition_ids)) != len(partition_ids):
            raise ModelValidationError("protocol partitions must contain unique task ids")
        selected_ids = tuple(selection.task_id for selection in self.selections)
        if set(selected_ids) != set(self.validation_task_ids) | set(self.untouched_task_ids):
            raise ModelValidationError("protocol matched selections must equal the locked non-development partitions")
        if any(selection.partition == "development" for selection in self.selections):
            raise ModelValidationError("protocol matched selections cannot include development tasks")
        expected_validation = tuple(selection.task_id for selection in self.selections if selection.partition == "validation")
        expected_untouched = tuple(selection.task_id for selection in self.selections if selection.partition == "untouched")
        if expected_validation != self.validation_task_ids or expected_untouched != self.untouched_task_ids:
            raise ModelValidationError("protocol partition lists do not match matched selections")
        if set(self.scored_task_ids) & set(self.calibration_task_ids):
            raise ModelValidationError("protocol scored and calibration selections overlap")
        if any(selection.provenance == "public_reference" for selection in self.selections if selection.task_id in self.scored_task_ids):
            raise ModelValidationError("public_reference task cannot enter scored evaluation")

    @classmethod
    def from_dict(cls, value: Any) -> "EvaluationProtocol":
        record = require_record(value, "protocol")
        require_exact_keys(record, {"schema_version", "protocol_id", "family_id", "capsules", "intervention", "baseline", "matched_selections", "partitions", "optimizer_disclosure", "policy", "taskset", "season_id", "treatment", "execution", "decision_rule", "challenge_revision_id"}, "protocol")
        capsules = require_record(record["capsules"], "protocol.capsules"); require_exact_keys(capsules, {"baseline", "candidate"}, "protocol.capsules")
        intervention = require_record(record["intervention"], "protocol.intervention"); require_exact_keys(intervention, {"class", "changed_files"}, "protocol.intervention")
        baseline = require_record(record["baseline"], "protocol.baseline"); require_exact_keys(baseline, {"class", "justification"}, "protocol.baseline")
        partitions = require_record(record["partitions"], "protocol.partitions"); require_exact_keys(partitions, {"development", "validation", "untouched"}, "protocol.partitions")
        optimizer = require_record(record["optimizer_disclosure"], "protocol.optimizer_disclosure"); require_exact_keys(optimizer, {"method", "candidate_count", "rejected_candidate_ids"}, "protocol.optimizer_disclosure")
        taskset = require_record(record["taskset"], "protocol.taskset"); require_exact_keys(taskset, {"schema_version", "package", "version", "content_hash"}, "protocol.taskset")
        treatment = require_record(record["treatment"], "protocol.treatment"); require_exact_keys(treatment, {"skill_source", "skill_content", "diff"}, "protocol.treatment")
        execution = require_record(record["execution"], "protocol.execution"); require_exact_keys(execution, {"exact_commands", "harness_settings", "seeds", "expected_output_schema"}, "protocol.execution")
        require_type(record["matched_selections"], list, "protocol.matched_selections")
        selections = tuple(MatchedSelection.from_dict(item, f"protocol.matched_selections[{index}]") for index, item in enumerate(record["matched_selections"]))
        task_ids = tuple(selection.task_id for selection in selections)
        matched_orders = tuple(selection.matched_order for selection in selections)
        if len(set(task_ids)) != len(task_ids):
            raise ValueError("protocol.matched_selections must contain unique task ids")
        if len(set(matched_orders)) != len(matched_orders) or set(matched_orders) != set(range(len(matched_orders))):
            raise ValueError("protocol.matched_selections matched_order positions must be canonical")
        protocol = cls(
            require_schema_version(record["schema_version"], "protocol.schema_version"), require_identifier(record["protocol_id"], "protocol.protocol_id"), require_identifier(record["family_id"], "protocol.family_id"),
            require_identifier(capsules["baseline"], "protocol.capsules.baseline"), require_identifier(capsules["candidate"], "protocol.capsules.candidate"),
            require_string(intervention["class"], "protocol.intervention.class"), tuple(require_string_list(intervention["changed_files"], "protocol.intervention.changed_files")),
            require_string(baseline["class"], "protocol.baseline.class"), require_string(baseline["justification"], "protocol.baseline.justification"),
            selections,
            tuple(require_identifier_list(partitions["development"], "protocol.partitions.development")), tuple(require_identifier_list(partitions["validation"], "protocol.partitions.validation")), tuple(require_identifier_list(partitions["untouched"], "protocol.partitions.untouched")),
            require_string(optimizer["method"], "protocol.optimizer_disclosure.method"), require_int(optimizer["candidate_count"], "protocol.optimizer_disclosure.candidate_count", minimum=1), tuple(require_identifier_list(optimizer["rejected_candidate_ids"], "protocol.optimizer_disclosure.rejected_candidate_ids")), VerifyPolicy.from_dict(record["policy"]),
            TasksetPackageReference.from_dict(taskset),
            require_identifier(record["challenge_revision_id"], "protocol.challenge_revision_id"),
            require_nullable_string(record["season_id"], "protocol.season_id"),
            require_string(treatment["skill_source"], "protocol.treatment.skill_source"),
            require_string(treatment["skill_content"], "protocol.treatment.skill_content", allow_empty=True),
            require_string(treatment["diff"], "protocol.treatment.diff", allow_empty=True),
            tuple(require_string_list(execution["exact_commands"], "protocol.execution.exact_commands")),
            _string_pairs(execution["harness_settings"], "protocol.execution.harness_settings"),
            tuple(require_string_list(execution["seeds"], "protocol.execution.seeds")),
            require_identifier(execution["expected_output_schema"], "protocol.execution.expected_output_schema"),
            DecisionRule.from_dict(record["decision_rule"]),
        )
        protocol.validate_evaluation_partition()
        if protocol.protocol_id != protocol.expected_protocol_id():
            raise ModelValidationError("protocol.protocol_id does not match the canonical protocol content")
        return protocol
