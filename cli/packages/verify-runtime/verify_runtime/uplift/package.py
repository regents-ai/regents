"""Assembly of archived, never-executed reproduction packages."""

from __future__ import annotations

from typing import Any

from verify_runtime.model import ReproductionPackage, canonical_json_bytes, content_id, sha256_bytes

from .compare import ComparisonData
from .errors import UpliftInputError


def _arm_configuration(capsule) -> dict[str, Any]:
    return {"declared": capsule.declared.to_dict(), "resolved": capsule.resolved.to_dict()}


def _fact_values(capsules, field: str) -> tuple[str, ...]:
    values = {f"{name}={value}" for capsule in capsules for name, value in getattr(capsule.observed, field)}
    return tuple(sorted(values))


def _exact_commands(data: ComparisonData) -> tuple[str, ...]:
    executor = data.baseline_capsule.observed.executor
    digests = data.receipt_digests
    commands = []
    for command in data.protocol.exact_commands:
        resolved = command.replace("<fixture|hermes|prime>", executor)
        placeholders = resolved.count("<sha256>")
        if placeholders not in (0, len(digests)):
            raise UpliftInputError("locked reproduction command must contain one digest placeholder per receipt")
        for digest in digests:
            resolved = resolved.replace("<sha256>", digest, 1)
        commands.append(resolved)
    return tuple(commands)


def _versions(data: ComparisonData) -> dict[str, dict[str, str]]:
    return {
        "model": {
            "baseline": f"{data.baseline_capsule.resolved.provider}:{data.baseline_capsule.resolved.model_identifier}:{data.baseline_capsule.resolved.model_version}",
            "candidate": f"{data.candidate_capsule.resolved.provider}:{data.candidate_capsule.resolved.model_identifier}:{data.candidate_capsule.resolved.model_version}",
        },
        "runtime": {
            "baseline": data.baseline_capsule.resolved.hermes_version,
            "candidate": data.candidate_capsule.resolved.hermes_version,
        },
        "harness": {
            "baseline": content_id("harness", list(data.protocol.harness_settings)),
            "candidate": content_id("harness", list(data.protocol.harness_settings)),
        },
        "skill": {
            "baseline": data.baseline_capsule.resolved.skill_digest,
            "candidate": data.candidate_capsule.resolved.skill_digest,
        },
        "evaluation": {
            "baseline": data.protocol.protocol_id,
            "candidate": data.protocol.protocol_id,
        },
    }


def assemble_reproduction_package(data: ComparisonData, tolerance: dict[str, Any] | None = None) -> ReproductionPackage:
    """Build a package from receipt-contained facts; this function never executes it."""

    if tolerance is not None and type(tolerance) is not dict:
        raise UpliftInputError("reproduction tolerance must be an object or null")
    try:
        canonical_json_bytes(tolerance) if tolerance is not None else None
    except (TypeError, ValueError, OverflowError, RecursionError) as error:
        raise UpliftInputError("reproduction tolerance must be JSON serializable") from error
    package_identity = {
        "receipt_digests": list(data.receipt_digests),
        "protocol_id": data.protocol.protocol_id,
        "tolerance": tolerance,
    }
    artifacts = {
        digest
        for receipt in data.receipts
        for run in (receipt.baseline_run, receipt.candidate_run)
        for _, digest, _ in run.artifacts
    }
    baseline_capsules = tuple(receipt.baseline_capsule for receipt in data.receipts)
    candidate_capsules = tuple(receipt.candidate_capsule for receipt in data.receipts)
    harness_deviations = tuple(
        f"{name}={value}"
        for name, value in data.protocol.harness_settings
        if value != "default"
    )
    return ReproductionPackage(
        schema_version=1,
        package_id=content_id("reproduction-package", package_identity),
        receipt_digests=data.receipt_digests,
        protocol=data.protocol,
        capsules={"baseline": data.baseline_capsule, "candidate": data.candidate_capsule},
        taskset_version=data.protocol.taskset_version,
        baseline_configuration=_arm_configuration(data.baseline_capsule),
        treatment_configuration=_arm_configuration(data.candidate_capsule),
        treatment_skill=data.protocol.treatment_skill_content,
        treatment_diff=data.protocol.treatment_diff,
        versions=_versions(data),
        exact_commands=_exact_commands(data),
        permissions={
            "baseline": tuple(data.baseline_capsule.declared.runtime_permissions),
            "candidate": tuple(data.candidate_capsule.declared.runtime_permissions),
        },
        tool_policy={
            "baseline": _fact_values(baseline_capsules, "tool_facts"),
            "candidate": _fact_values(candidate_capsules, "tool_facts"),
        },
        search_budget={
            "optimizer": {
                "method": data.protocol.optimizer_method,
                "candidate_count": data.protocol.optimizer_candidate_count,
                "rejected_candidate_ids": list(data.protocol.rejected_candidate_ids),
            },
            "verify_policy": data.protocol.policy.to_dict(),
        },
        seeds=data.protocol.seeds,
        artifact_hashes=tuple(sorted(artifacts)),
        expected_output_schema=data.protocol.expected_output_schema,
        harness_settings=data.protocol.harness_settings,
        harness_deviations=harness_deviations,
        reproduction_tolerance=tolerance,
        assembly_status="assembled",
        executed=False,
    )


def validated_reproduction_package(package: ReproductionPackage) -> ReproductionPackage:
    return ReproductionPackage.from_dict(package.to_dict())


def reproduction_package_bytes(package: ReproductionPackage) -> bytes:
    return canonical_json_bytes(validated_reproduction_package(package).to_dict())


def reproduction_package_digest(package: ReproductionPackage) -> str:
    return sha256_bytes(reproduction_package_bytes(package))
