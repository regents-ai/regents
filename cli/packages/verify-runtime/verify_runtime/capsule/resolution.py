"""Build declared, resolved, and observed capsule views from runtime facts."""

from __future__ import annotations

from dataclasses import dataclass, replace

from verify_runtime.model import Capsule, DeclaredCapsule, ObservedCapsule, ResolvedCapsule, content_id, sha256_bytes

HOSTED_HERMES_DEFAULT = {
    "schema_version": 1,
    "default_id": "hermes-hosted-default-v1",
    "declared_provider": "hermes-hosted",
    "declared_model": "current-default",
    "hermes_configuration": "hosted-default",
}


@dataclass(frozen=True)
class ResolvedRuntimeIdentity:
    """Facts learned by interrogating the selected executor at resolution time."""

    executor: str
    provider: str
    model_identifier: str
    model_version: str
    behavioral_fingerprint: str | None
    model_mutability: str
    hermes_version: str
    hermes_digest: str | None
    hermes_mutability: str
    tool_components: tuple[tuple[str, str, str], ...]
    config_components: tuple[tuple[str, str, str], ...]


def declared_capsule(
    skill_source: str,
    *,
    executor: str = "hermes",
    provider: str | None = None,
    model: str | None = None,
    hermes_configuration: str | None = None,
) -> DeclaredCapsule:
    if executor == "fixture":
        declared_provider = provider or "fixture"
        declared_model = model or "contract-drift-fixture-v1"
        configuration = hermes_configuration or "fixture-executor-v1"
        tools = ("fixture-filesystem",)
        permissions = ("workspace-read-write", "network-disabled")
    else:
        declared_provider = provider or HOSTED_HERMES_DEFAULT["declared_provider"]
        declared_model = model or HOSTED_HERMES_DEFAULT["declared_model"]
        configuration = hermes_configuration or HOSTED_HERMES_DEFAULT["hermes_configuration"]
        tools = ("filesystem",)
        permissions = ("workspace-read-write", "network-by-executor-policy")
    return DeclaredCapsule(
        provider=declared_provider,
        model=declared_model,
        inference_settings=(("profile", configuration),),
        hermes_version="selected-runtime",
        hermes_configuration=configuration,
        skill_source=skill_source,
        tools=tools,
        context_memory_policy="fresh-per-task",
        runtime_permissions=permissions,
        private_knowledge_commitments=(),
        budget_policy_id="verify-public-default-v1",
        termination_policy="locked-policy",
        publication_policy="private-local",
    )


def resolve_capsule(
    declared: DeclaredCapsule,
    skill_bytes: bytes,
    *,
    identity: ResolvedRuntimeIdentity,
) -> Capsule:
    resolved = ResolvedCapsule(
        provider=identity.provider,
        model_identifier=identity.model_identifier,
        model_version=identity.model_version,
        behavioral_fingerprint=identity.behavioral_fingerprint,
        model_mutability=identity.model_mutability,
        hermes_version=identity.hermes_version,
        hermes_digest=identity.hermes_digest,
        hermes_mutability=identity.hermes_mutability,
        skill_source=declared.skill_source,
        skill_digest=sha256_bytes(skill_bytes),
        skill_mutability="content-pinned",
        tool_components=identity.tool_components,
        config_components=identity.config_components,
    )
    observed = ObservedCapsule(identity.executor, (), (("state", "resolved"),), (), 0)
    capsule_identity = {"declared": declared.to_dict(), "resolved": resolved.to_dict()}
    return Capsule(1, content_id("capsule", capsule_identity), declared, resolved, observed)


def with_observed_execution(
    capsule: Capsule,
    *,
    executor: str,
    status: str,
    provider_facts: tuple[tuple[str, str], ...] = (),
    runtime_facts: tuple[tuple[str, str], ...] = (),
    tool_facts: tuple[tuple[str, str], ...] = (),
    retry_count: int = 0,
) -> Capsule:
    observed = ObservedCapsule(
        executor,
        provider_facts,
        (("terminal_status", status), *runtime_facts),
        tool_facts,
        retry_count,
    )
    return replace(capsule, observed=observed)
