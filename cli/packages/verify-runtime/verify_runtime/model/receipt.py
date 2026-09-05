"""Canonical evaluation receipt covering one matched task pair."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .base import ModelValidationError, canonical_json_bytes, content_id, require_bounded_int, require_exact_keys, require_identifier, require_int, require_record, require_schema_version, require_sha256, require_string, sha256_bytes
from .capsule import Capsule
from .protocol import EvaluationProtocol
from .run import RunRecord


@dataclass(frozen=True)
class EvaluationReceipt:
    schema_version: int
    store_id: str
    receipt_id: str
    task_id: str
    protocol: EvaluationProtocol
    baseline_capsule: Capsule
    candidate_capsule: Capsule
    baseline_run: RunRecord
    candidate_run: RunRecord
    comparison_result: str
    baseline_score_millis: int | None
    candidate_score_millis: int | None
    total_cost_usd_cents: int
    baseline_run_digest: str
    candidate_run_digest: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "store_id": self.store_id,
            "receipt_id": self.receipt_id,
            "task_id": self.task_id,
            "protocol": self.protocol.to_dict(),
            "capsules": {"baseline": self.baseline_capsule.to_dict(), "candidate": self.candidate_capsule.to_dict()},
            "runs": {"baseline": self.baseline_run.to_dict(), "candidate": self.candidate_run.to_dict(), "digests": {"baseline": self.baseline_run_digest, "candidate": self.candidate_run_digest}},
            "outcome": {"comparison_result": self.comparison_result, "baseline_score_millis": self.baseline_score_millis, "candidate_score_millis": self.candidate_score_millis},
            "cost": {"total_usd_cents": self.total_cost_usd_cents},
        }

    def content_digest(self) -> str:
        return sha256_bytes(canonical_json_bytes(self.to_dict()))

    @classmethod
    def from_dict(cls, value: Any) -> "EvaluationReceipt":
        record = require_record(value, "receipt")
        require_exact_keys(record, {"schema_version", "store_id", "receipt_id", "task_id", "protocol", "capsules", "runs", "outcome", "cost"}, "receipt")
        capsules = require_record(record["capsules"], "receipt.capsules"); require_exact_keys(capsules, {"baseline", "candidate"}, "receipt.capsules")
        runs = require_record(record["runs"], "receipt.runs"); require_exact_keys(runs, {"baseline", "candidate", "digests"}, "receipt.runs")
        outcome = require_record(record["outcome"], "receipt.outcome"); require_exact_keys(outcome, {"comparison_result", "baseline_score_millis", "candidate_score_millis"}, "receipt.outcome")
        cost = require_record(record["cost"], "receipt.cost"); require_exact_keys(cost, {"total_usd_cents"}, "receipt.cost")
        scores = []
        for name in ("baseline_score_millis", "candidate_score_millis"):
            score = outcome[name]
            scores.append(None if score is None else require_bounded_int(score, f"receipt.outcome.{name}"))
        protocol = EvaluationProtocol.from_dict(record["protocol"])
        baseline_capsule = Capsule.from_dict(capsules["baseline"])
        candidate_capsule = Capsule.from_dict(capsules["candidate"])
        baseline_run = RunRecord.from_dict(runs["baseline"])
        candidate_run = RunRecord.from_dict(runs["candidate"])
        digest_record = require_record(runs["digests"], "receipt.runs.digests")
        require_exact_keys(digest_record, {"baseline", "candidate"}, "receipt.runs.digests")
        baseline_run_digest = require_sha256(digest_record["baseline"], "receipt.runs.digests.baseline")
        candidate_run_digest = require_sha256(digest_record["candidate"], "receipt.runs.digests.candidate")
        if baseline_run_digest != baseline_run.content_digest() or candidate_run_digest != candidate_run.content_digest():
            raise ModelValidationError("receipt run digests do not match the embedded run records")
        selection = next((item for item in protocol.selections if item.task_id == record["task_id"]), None)
        if selection is None:
            raise ModelValidationError("receipt task is not in the embedded protocol selections")
        if baseline_run.provenance != selection.provenance or candidate_run.provenance != selection.provenance:
            raise ModelValidationError("receipt run provenance does not match the embedded task provenance")
        if baseline_run.provenance != candidate_run.provenance:
            raise ModelValidationError("receipt arms do not share the embedded task provenance")
        receipt_id = require_identifier(record["receipt_id"], "receipt.receipt_id")
        task_id = require_identifier(record["task_id"], "receipt.task_id")
        if receipt_id != content_id("receipt", {"protocol_id": protocol.protocol_id, "task_id": task_id}):
            raise ModelValidationError("receipt.receipt_id does not match the locked protocol and task")
        if baseline_capsule.capsule_id != protocol.baseline_capsule_id or candidate_capsule.capsule_id != protocol.candidate_capsule_id:
            raise ModelValidationError("receipt capsules do not match the embedded protocol")
        for run, side, capsule_id in (
            (baseline_run, "baseline", protocol.baseline_capsule_id),
            (candidate_run, "candidate", protocol.candidate_capsule_id),
        ):
            if run.protocol_id != protocol.protocol_id or run.capsule_id != capsule_id or run.side != side or run.task_id != task_id:
                raise ModelValidationError("receipt run identity does not match the embedded protocol")
        if scores != [baseline_run.score_millis, candidate_run.score_millis]:
            raise ModelValidationError("receipt score summary does not match the embedded run records")
        if baseline_run.status != "completed":
            expected_comparison = baseline_run.status
        elif candidate_run.status != "completed":
            expected_comparison = candidate_run.status
        elif baseline_run.score_millis is None or candidate_run.score_millis is None:
            expected_comparison = "invalid"
        elif candidate_run.score_millis > baseline_run.score_millis:
            expected_comparison = "positive"
        elif candidate_run.score_millis < baseline_run.score_millis:
            expected_comparison = "negative"
        else:
            expected_comparison = "null"
        if require_string(outcome["comparison_result"], "receipt.outcome.comparison_result") != expected_comparison:
            raise ModelValidationError("receipt comparison result does not match the embedded run records")
        total_cost = require_int(cost["total_usd_cents"], "receipt.cost.total_usd_cents")
        if total_cost != baseline_run.cost_usd_cents + candidate_run.cost_usd_cents:
            raise ModelValidationError("receipt cost summary does not match the embedded run records")
        return cls(require_schema_version(record["schema_version"], "receipt.schema_version"), require_sha256(record["store_id"], "receipt.store_id"), receipt_id, task_id, protocol, baseline_capsule, candidate_capsule, baseline_run, candidate_run, expected_comparison, scores[0], scores[1], total_cost, baseline_run_digest, candidate_run_digest)
