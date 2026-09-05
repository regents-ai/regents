"""Canonical environment-family record aligned with the landed Forge contract."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .base import require_exact_keys, require_identifier, require_int, require_record, require_schema_version, require_string


@dataclass(frozen=True)
class EnvironmentFamily:
    schema_version: int
    family_id: str
    product_status: str
    kind: str
    executor: str
    intervention_artifact: str
    intervention_changed_file_count: int
    verifier_protocol: str
    verifier_protocol_version: int

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "family_id": self.family_id,
            "product_status": self.product_status,
            "kind": self.kind,
            "executor": self.executor,
            "intervention": {
                "artifact": self.intervention_artifact,
                "changed_file_count": self.intervention_changed_file_count,
            },
            "verifier": {
                "protocol": self.verifier_protocol,
                "protocol_version": self.verifier_protocol_version,
            },
        }

    @classmethod
    def from_dict(cls, value: Any) -> "EnvironmentFamily":
        record = require_record(value, "family")
        require_exact_keys(
            record,
            {"schema_version", "family_id", "product_status", "kind", "executor", "intervention", "verifier"},
            "family",
        )
        intervention = require_record(record["intervention"], "family.intervention")
        require_exact_keys(intervention, {"artifact", "changed_file_count"}, "family.intervention")
        verifier = require_record(record["verifier"], "family.verifier")
        require_exact_keys(verifier, {"protocol", "protocol_version"}, "family.verifier")
        return cls(
            schema_version=require_schema_version(record["schema_version"], "family.schema_version"),
            family_id=require_identifier(record["family_id"], "family.family_id"),
            product_status=require_string(record["product_status"], "family.product_status"),
            kind=require_string(record["kind"], "family.kind"),
            executor=require_string(record["executor"], "family.executor"),
            intervention_artifact=require_string(intervention["artifact"], "family.intervention.artifact"),
            intervention_changed_file_count=require_int(
                intervention["changed_file_count"], "family.intervention.changed_file_count", minimum=1
            ),
            verifier_protocol=require_string(verifier["protocol"], "family.verifier.protocol"),
            verifier_protocol_version=require_int(
                verifier["protocol_version"], "family.verifier.protocol_version", minimum=1
            ),
        )
