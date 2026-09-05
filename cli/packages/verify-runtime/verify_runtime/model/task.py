"""Canonical task-instance record."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

from .base import require_exact_keys, require_identifier, require_record, require_schema_version, require_sha256, require_string
from .benchmark import PARTITIONS, Partition

TaskProvenance = Literal["held_out", "public_reference"]
TASK_PROVENANCES = {"held_out", "public_reference"}
POSSIBLE_CONTAMINATION = "possible-contamination"


@dataclass(frozen=True)
class TaskInstance:
    schema_version: int
    task_id: str
    family_id: str
    slice_id: str
    partition: Partition
    role_id: str
    input_digest: str
    grader_digest: str
    provenance: TaskProvenance = "held_out"
    # Lock-only sealed-side evidence.  It is intentionally not part of the
    # provider task wire record; the lock copies it into MatchedSelection.
    answer_key_commitment: str | None = field(default=None, compare=False, repr=False)
    # The nonce is sealed-side evidence used only when the verifier recomputes
    # ``answer_key_commitment``.  It is never serialized by ``to_dict``.
    answer_key_blinding_nonce: bytes | None = field(default=None, compare=False, repr=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "task_id": self.task_id,
            "family_id": self.family_id,
            "slice_id": self.slice_id,
            "partition": self.partition,
            "role_id": self.role_id,
            "input_digest": self.input_digest,
            "grader_digest": self.grader_digest,
            "provenance": self.provenance,
        }

    @classmethod
    def from_dict(cls, value: Any) -> "TaskInstance":
        record = require_record(value, "task")
        require_exact_keys(
            record,
            {
                "schema_version",
                "task_id",
                "family_id",
                "slice_id",
                "partition",
                "role_id",
                "input_digest",
                "grader_digest",
                "provenance",
            },
            "task",
        )
        partition = require_string(record["partition"], "task.partition")
        if partition not in PARTITIONS:
            raise ValueError("task.partition must be development, validation, or untouched")
        provenance = require_string(record["provenance"], "task.provenance")
        if provenance not in TASK_PROVENANCES:
            raise ValueError("task.provenance must be held_out or public_reference")
        return cls(
            require_schema_version(record["schema_version"], "task.schema_version"),
            require_identifier(record["task_id"], "task.task_id"),
            require_identifier(record["family_id"], "task.family_id"),
            require_identifier(record["slice_id"], "task.slice_id"),
            partition,  # type: ignore[arg-type]
            require_identifier(record["role_id"], "task.role_id"),
            require_sha256(record["input_digest"], "task.input_digest"),
            require_sha256(record["grader_digest"], "task.grader_digest"),
            provenance,  # type: ignore[arg-type]
        )
