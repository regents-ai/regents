"""Canonical archived reproduction-package record.

The package is a durable instruction and evidence bundle.  Its explicit
``executed`` field is deliberately false: assembly never invokes an executor.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .base import (
    ModelValidationError,
    require_bool,
    require_exact_keys,
    require_identifier,
    require_record,
    require_schema_version,
    require_sha256,
    require_string,
    require_string_list,
    require_type,
)
from .capsule import Capsule
from .protocol import EvaluationProtocol
from .taskset import TasksetPackageReference


def _string_map(value: Any, expected: set[str], path: str) -> dict[str, str]:
    record = require_record(value, path)
    require_exact_keys(record, expected, path)
    return {key: require_string(record[key], f"{path}.{key}") for key in expected}


def _arm_string_lists(value: Any, path: str) -> dict[str, tuple[str, ...]]:
    record = require_record(value, path)
    require_exact_keys(record, {"baseline", "candidate"}, path)
    return {
        arm: tuple(require_string_list(record[arm], f"{path}.{arm}"))
        for arm in ("baseline", "candidate")
    }


def _pairs(value: Any, path: str) -> tuple[tuple[str, str], ...]:
    raw = require_type(value, list, path)
    pairs: list[tuple[str, str]] = []
    names: set[str] = set()
    for index, item in enumerate(raw):
        record = require_record(item, f"{path}[{index}]")
        require_exact_keys(record, {"name", "value"}, f"{path}[{index}]")
        name = require_string(record["name"], f"{path}[{index}].name")
        if name in names:
            raise ModelValidationError(f"{path} contains duplicate name: {name}")
        names.add(name)
        pairs.append((name, require_string(record["value"], f"{path}[{index}].value", allow_empty=True)))
    return tuple(pairs)


@dataclass(frozen=True)
class ReproductionPackage:
    schema_version: int
    package_id: str
    receipt_digests: tuple[str, ...]
    protocol: EvaluationProtocol
    capsules: dict[str, Capsule]
    taskset_version: TasksetPackageReference
    baseline_configuration: dict[str, Any]
    treatment_configuration: dict[str, Any]
    treatment_skill: str
    treatment_diff: str
    versions: dict[str, dict[str, str]]
    exact_commands: tuple[str, ...]
    permissions: dict[str, tuple[str, ...]]
    tool_policy: dict[str, tuple[str, ...]]
    search_budget: dict[str, Any]
    seeds: tuple[str, ...]
    artifact_hashes: tuple[str, ...]
    expected_output_schema: str
    harness_settings: tuple[tuple[str, str], ...]
    harness_deviations: tuple[str, ...]
    reproduction_tolerance: dict[str, Any] | None
    assembly_status: str
    executed: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "package_id": self.package_id,
            "receipt_digests": list(self.receipt_digests),
            "protocol": self.protocol.to_dict(),
            "capsules": {arm: self.capsules[arm].to_dict() for arm in ("baseline", "candidate")},
            "taskset_version": self.taskset_version.to_dict(),
            "baseline_configuration": self.baseline_configuration,
            "treatment_configuration": self.treatment_configuration,
            "treatment_skill": self.treatment_skill,
            "treatment_diff": self.treatment_diff,
            "versions": self.versions,
            "exact_commands": list(self.exact_commands),
            "permissions": {arm: list(values) for arm, values in self.permissions.items()},
            "tool_policy": {arm: list(values) for arm, values in self.tool_policy.items()},
            "search_budget": self.search_budget,
            "seeds": list(self.seeds),
            "artifact_hashes": list(self.artifact_hashes),
            "expected_output_schema": self.expected_output_schema,
            "harness_settings": [{"name": name, "value": value} for name, value in self.harness_settings],
            "harness_deviations": list(self.harness_deviations),
            "reproduction_tolerance": self.reproduction_tolerance,
            "assembly_status": self.assembly_status,
            "executed": self.executed,
        }

    @classmethod
    def from_dict(cls, value: Any) -> "ReproductionPackage":
        record = require_record(value, "reproduction_package")
        require_exact_keys(record, {"schema_version", "package_id", "receipt_digests", "protocol", "capsules", "taskset_version", "baseline_configuration", "treatment_configuration", "treatment_skill", "treatment_diff", "versions", "exact_commands", "permissions", "tool_policy", "search_budget", "seeds", "artifact_hashes", "expected_output_schema", "harness_settings", "harness_deviations", "reproduction_tolerance", "assembly_status", "executed"}, "reproduction_package")
        digests = require_type(record["receipt_digests"], list, "reproduction_package.receipt_digests")
        if not digests:
            raise ModelValidationError("reproduction_package.receipt_digests must be non-empty")
        receipt_digests = tuple(require_sha256(item, f"reproduction_package.receipt_digests[{index}]") for index, item in enumerate(digests))
        if len(set(receipt_digests)) != len(receipt_digests):
            raise ModelValidationError("reproduction_package.receipt_digests must be distinct")
        if receipt_digests != tuple(sorted(receipt_digests)):
            raise ModelValidationError("reproduction_package.receipt_digests must use canonical lexical order")
        protocol = EvaluationProtocol.from_dict(record["protocol"])
        capsules_record = require_record(record["capsules"], "reproduction_package.capsules")
        require_exact_keys(capsules_record, {"baseline", "candidate"}, "reproduction_package.capsules")
        capsules = {arm: Capsule.from_dict(capsules_record[arm]) for arm in ("baseline", "candidate")}
        if protocol.baseline_capsule_id != capsules["baseline"].capsule_id or protocol.candidate_capsule_id != capsules["candidate"].capsule_id:
            raise ModelValidationError("reproduction_package capsules do not match the protocol")
        versions_record = require_record(record["versions"], "reproduction_package.versions")
        require_exact_keys(versions_record, {"model", "runtime", "harness", "skill", "evaluation"}, "reproduction_package.versions")
        versions = {
            key: _string_map(versions_record[key], {"baseline", "candidate"}, f"reproduction_package.versions.{key}")
            for key in ("model", "runtime", "harness", "skill", "evaluation")
        }
        tolerance = record["reproduction_tolerance"]
        if tolerance is not None:
            tolerance = require_record(tolerance, "reproduction_package.reproduction_tolerance")
        artifact_hashes = tuple(require_sha256(item, f"reproduction_package.artifact_hashes[{index}]") for index, item in enumerate(require_type(record["artifact_hashes"], list, "reproduction_package.artifact_hashes")))
        assembly_status = require_string(record["assembly_status"], "reproduction_package.assembly_status")
        if assembly_status != "assembled":
            raise ModelValidationError("reproduction_package.assembly_status must be assembled")
        executed = require_bool(record["executed"], "reproduction_package.executed")
        if executed:
            raise ModelValidationError("reproduction_package.executed must be false")
        taskset_version = TasksetPackageReference.from_dict(record["taskset_version"])
        if taskset_version != protocol.taskset_version:
            raise ModelValidationError("reproduction_package taskset version does not match the protocol")
        return cls(
            require_schema_version(record["schema_version"], "reproduction_package.schema_version"),
            require_identifier(record["package_id"], "reproduction_package.package_id"),
            receipt_digests,
            protocol,
            capsules,
            taskset_version,
            require_record(record["baseline_configuration"], "reproduction_package.baseline_configuration"),
            require_record(record["treatment_configuration"], "reproduction_package.treatment_configuration"),
            require_string(record["treatment_skill"], "reproduction_package.treatment_skill", allow_empty=True),
            require_string(record["treatment_diff"], "reproduction_package.treatment_diff", allow_empty=True),
            versions,
            tuple(require_string_list(record["exact_commands"], "reproduction_package.exact_commands")),
            _arm_string_lists(record["permissions"], "reproduction_package.permissions"),
            _arm_string_lists(record["tool_policy"], "reproduction_package.tool_policy"),
            require_record(record["search_budget"], "reproduction_package.search_budget"),
            tuple(require_string_list(record["seeds"], "reproduction_package.seeds")),
            artifact_hashes,
            require_identifier(record["expected_output_schema"], "reproduction_package.expected_output_schema"),
            _pairs(record["harness_settings"], "reproduction_package.harness_settings"),
            tuple(require_string_list(record["harness_deviations"], "reproduction_package.harness_deviations")),
            tolerance,
            assembly_status,
            executed,
        )
