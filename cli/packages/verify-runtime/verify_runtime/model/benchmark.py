"""Canonical benchmark role and partitioned slice records."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal

from .base import require_exact_keys, require_identifier, require_identifier_list, require_int, require_record, require_schema_version, require_string

Partition = Literal["development", "validation", "untouched"]
PARTITIONS = {"development", "validation", "untouched"}


@dataclass(frozen=True)
class BenchmarkRole:
    schema_version: int
    role_id: str
    purpose: str
    access: str

    def to_dict(self) -> dict[str, Any]:
        return {"schema_version": self.schema_version, "role_id": self.role_id, "purpose": self.purpose, "access": self.access}

    @classmethod
    def from_dict(cls, value: Any) -> "BenchmarkRole":
        record = require_record(value, "role")
        require_exact_keys(record, {"schema_version", "role_id", "purpose", "access"}, "role")
        return cls(
            require_schema_version(record["schema_version"], "role.schema_version"),
            require_identifier(record["role_id"], "role.role_id"),
            require_string(record["purpose"], "role.purpose"),
            require_string(record["access"], "role.access"),
        )


@dataclass(frozen=True)
class BenchmarkSlice:
    schema_version: int
    slice_id: str
    family_id: str
    partition: Partition
    role_ids: tuple[str, ...]
    task_ids: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "slice_id": self.slice_id,
            "family_id": self.family_id,
            "partition": self.partition,
            "role_ids": list(self.role_ids),
            "task_ids": list(self.task_ids),
        }

    @classmethod
    def from_dict(cls, value: Any) -> "BenchmarkSlice":
        record = require_record(value, "slice")
        require_exact_keys(record, {"schema_version", "slice_id", "family_id", "partition", "role_ids", "task_ids"}, "slice")
        partition = require_string(record["partition"], "slice.partition")
        if partition not in PARTITIONS:
            raise ValueError("slice.partition must be development, validation, or untouched")
        return cls(
            require_schema_version(record["schema_version"], "slice.schema_version"),
            require_identifier(record["slice_id"], "slice.slice_id"),
            require_identifier(record["family_id"], "slice.family_id"),
            partition,  # type: ignore[arg-type]
            tuple(require_identifier_list(record["role_ids"], "slice.role_ids")),
            tuple(require_identifier_list(record["task_ids"], "slice.task_ids")),
        )
