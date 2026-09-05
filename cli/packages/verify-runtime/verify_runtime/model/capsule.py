"""Canonical capsule record with declared, resolved, and observed views."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .base import (
    require_exact_keys,
    require_identifier,
    require_int,
    require_nullable_sha256,
    require_nullable_string,
    require_record,
    require_schema_version,
    require_sha256,
    require_string,
    require_string_list,
    require_type,
)


def _fact_list(value: Any, path: str) -> tuple[tuple[str, str], ...]:
    require_type(value, list, path)
    facts: list[tuple[str, str]] = []
    names: set[str] = set()
    for index, item in enumerate(value):
        record = require_record(item, f"{path}[{index}]")
        require_exact_keys(record, {"name", "value"}, f"{path}[{index}]")
        name = require_string(record["name"], f"{path}[{index}].name")
        if name in names:
            raise ValueError(f"{path} has duplicate fact name: {name}")
        names.add(name)
        facts.append((name, require_string(record["value"], f"{path}[{index}].value", allow_empty=True)))
    return tuple(facts)


def _facts_dict(value: tuple[tuple[str, str], ...]) -> list[dict[str, str]]:
    return [{"name": name, "value": fact_value} for name, fact_value in value]


@dataclass(frozen=True)
class DeclaredCapsule:
    provider: str
    model: str
    inference_settings: tuple[tuple[str, str], ...]
    hermes_version: str
    hermes_configuration: str
    skill_source: str
    tools: tuple[str, ...]
    context_memory_policy: str
    runtime_permissions: tuple[str, ...]
    private_knowledge_commitments: tuple[str, ...]
    budget_policy_id: str
    termination_policy: str
    publication_policy: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "model": {"provider": self.provider, "identifier": self.model, "inference_settings": _facts_dict(self.inference_settings)},
            "hermes": {"version": self.hermes_version, "configuration": self.hermes_configuration},
            "skill_source": self.skill_source,
            "tools": list(self.tools),
            "context_memory_policy": self.context_memory_policy,
            "runtime_permissions": list(self.runtime_permissions),
            "private_knowledge_commitments": list(self.private_knowledge_commitments),
            "budget_policy_id": self.budget_policy_id,
            "termination_policy": self.termination_policy,
            "publication_policy": self.publication_policy,
        }

    @classmethod
    def from_dict(cls, value: Any) -> "DeclaredCapsule":
        record = require_record(value, "capsule.declared")
        require_exact_keys(record, {"model", "hermes", "skill_source", "tools", "context_memory_policy", "runtime_permissions", "private_knowledge_commitments", "budget_policy_id", "termination_policy", "publication_policy"}, "capsule.declared")
        model = require_record(record["model"], "capsule.declared.model")
        require_exact_keys(model, {"provider", "identifier", "inference_settings"}, "capsule.declared.model")
        hermes = require_record(record["hermes"], "capsule.declared.hermes")
        require_exact_keys(hermes, {"version", "configuration"}, "capsule.declared.hermes")
        return cls(
            require_string(model["provider"], "capsule.declared.model.provider"),
            require_string(model["identifier"], "capsule.declared.model.identifier"),
            _fact_list(model["inference_settings"], "capsule.declared.model.inference_settings"),
            require_string(hermes["version"], "capsule.declared.hermes.version"),
            require_string(hermes["configuration"], "capsule.declared.hermes.configuration"),
            require_string(record["skill_source"], "capsule.declared.skill_source"),
            tuple(require_string_list(record["tools"], "capsule.declared.tools")),
            require_string(record["context_memory_policy"], "capsule.declared.context_memory_policy"),
            tuple(require_string_list(record["runtime_permissions"], "capsule.declared.runtime_permissions")),
            tuple(require_string_list(record["private_knowledge_commitments"], "capsule.declared.private_knowledge_commitments")),
            require_identifier(record["budget_policy_id"], "capsule.declared.budget_policy_id"),
            require_string(record["termination_policy"], "capsule.declared.termination_policy"),
            require_string(record["publication_policy"], "capsule.declared.publication_policy"),
        )


@dataclass(frozen=True)
class ResolvedCapsule:
    provider: str
    model_identifier: str
    model_version: str
    behavioral_fingerprint: str | None
    model_mutability: str
    hermes_version: str
    hermes_digest: str | None
    hermes_mutability: str
    skill_source: str
    skill_digest: str
    skill_mutability: str
    tool_components: tuple[tuple[str, str, str], ...]
    config_components: tuple[tuple[str, str, str], ...]

    def to_dict(self) -> dict[str, Any]:
        components = lambda values: [{"name": name, "digest": digest, "mutability": mutability} for name, digest, mutability in values]
        return {
            "model": {"provider": self.provider, "identifier": self.model_identifier, "version": self.model_version, "behavioral_fingerprint": self.behavioral_fingerprint, "mutability": self.model_mutability},
            "hermes": {"version": self.hermes_version, "digest": self.hermes_digest, "mutability": self.hermes_mutability},
            "skill": {"source": self.skill_source, "digest": self.skill_digest, "mutability": self.skill_mutability},
            "tools": components(self.tool_components),
            "configs": components(self.config_components),
        }

    @classmethod
    def from_dict(cls, value: Any) -> "ResolvedCapsule":
        record = require_record(value, "capsule.resolved")
        require_exact_keys(record, {"model", "hermes", "skill", "tools", "configs"}, "capsule.resolved")
        model = require_record(record["model"], "capsule.resolved.model")
        require_exact_keys(model, {"provider", "identifier", "version", "behavioral_fingerprint", "mutability"}, "capsule.resolved.model")
        hermes = require_record(record["hermes"], "capsule.resolved.hermes")
        require_exact_keys(hermes, {"version", "digest", "mutability"}, "capsule.resolved.hermes")
        skill = require_record(record["skill"], "capsule.resolved.skill")
        require_exact_keys(skill, {"source", "digest", "mutability"}, "capsule.resolved.skill")
        def components(raw: Any, path: str) -> tuple[tuple[str, str, str], ...]:
            require_type(raw, list, path)
            result = []
            for index, item in enumerate(raw):
                component = require_record(item, f"{path}[{index}]")
                require_exact_keys(component, {"name", "digest", "mutability"}, f"{path}[{index}]")
                result.append((require_string(component["name"], f"{path}[{index}].name"), require_sha256(component["digest"], f"{path}[{index}].digest"), require_string(component["mutability"], f"{path}[{index}].mutability")))
            return tuple(result)
        return cls(
            require_string(model["provider"], "capsule.resolved.model.provider"),
            require_string(model["identifier"], "capsule.resolved.model.identifier"),
            require_string(model["version"], "capsule.resolved.model.version"),
            require_nullable_string(model["behavioral_fingerprint"], "capsule.resolved.model.behavioral_fingerprint"),
            require_string(model["mutability"], "capsule.resolved.model.mutability"),
            require_string(hermes["version"], "capsule.resolved.hermes.version"),
            require_nullable_sha256(hermes["digest"], "capsule.resolved.hermes.digest"),
            require_string(hermes["mutability"], "capsule.resolved.hermes.mutability"),
            require_string(skill["source"], "capsule.resolved.skill.source"),
            require_sha256(skill["digest"], "capsule.resolved.skill.digest"),
            require_string(skill["mutability"], "capsule.resolved.skill.mutability"),
            components(record["tools"], "capsule.resolved.tools"),
            components(record["configs"], "capsule.resolved.configs"),
        )


@dataclass(frozen=True)
class ObservedCapsule:
    executor: str
    provider_facts: tuple[tuple[str, str], ...]
    runtime_facts: tuple[tuple[str, str], ...]
    tool_facts: tuple[tuple[str, str], ...]
    retry_count: int

    def to_dict(self) -> dict[str, Any]:
        return {"executor": self.executor, "provider_facts": _facts_dict(self.provider_facts), "runtime_facts": _facts_dict(self.runtime_facts), "tool_facts": _facts_dict(self.tool_facts), "retry_count": self.retry_count}

    @classmethod
    def from_dict(cls, value: Any) -> "ObservedCapsule":
        record = require_record(value, "capsule.observed")
        require_exact_keys(record, {"executor", "provider_facts", "runtime_facts", "tool_facts", "retry_count"}, "capsule.observed")
        return cls(require_string(record["executor"], "capsule.observed.executor"), _fact_list(record["provider_facts"], "capsule.observed.provider_facts"), _fact_list(record["runtime_facts"], "capsule.observed.runtime_facts"), _fact_list(record["tool_facts"], "capsule.observed.tool_facts"), require_int(record["retry_count"], "capsule.observed.retry_count"))


@dataclass(frozen=True)
class Capsule:
    schema_version: int
    capsule_id: str
    declared: DeclaredCapsule
    resolved: ResolvedCapsule
    observed: ObservedCapsule

    def to_dict(self) -> dict[str, Any]:
        return {"schema_version": self.schema_version, "capsule_id": self.capsule_id, "declared": self.declared.to_dict(), "resolved": self.resolved.to_dict(), "observed": self.observed.to_dict()}

    @classmethod
    def from_dict(cls, value: Any) -> "Capsule":
        record = require_record(value, "capsule")
        require_exact_keys(record, {"schema_version", "capsule_id", "declared", "resolved", "observed"}, "capsule")
        return cls(require_schema_version(record["schema_version"], "capsule.schema_version"), require_identifier(record["capsule_id"], "capsule.capsule_id"), DeclaredCapsule.from_dict(record["declared"]), ResolvedCapsule.from_dict(record["resolved"]), ObservedCapsule.from_dict(record["observed"]))
