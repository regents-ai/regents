"""GB-Pro challenge, authoring, source, season, and package references."""

from __future__ import annotations

import re
from dataclasses import dataclass, field, replace
from typing import Any

from .base import (
    ModelValidationError,
    content_id,
    require_bool,
    require_exact_keys,
    require_identifier,
    require_identifier_list,
    require_json_value,
    require_record,
    require_schema_version,
    require_sha256,
    require_string,
    require_type,
    sha256_bytes,
)
from .capsule import DeclaredCapsule
from .protocol import DecisionRule
from .sealed import sealed_answer_key_commitment
from .taskset import TasksetPackageReference


ACCEPTANCE_DECISIONS = {"accepted", "rejected", "pending"}
_IMMUTABLE_SOURCE_REVISIONS = {"head", "latest", "main", "master", "trunk", "default"}
_HF_REVISION_PATTERN = re.compile(
    r"^(?:hf|huggingface)://datasets/([^/@\s]+(?:/[^/@\s]+)*)@([0-9a-f]{40})$"
)
_GIT_COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
_EXACT_PACKAGE_VERSION_PATTERN = re.compile(
    r"^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$"
)


def normalize_huggingface_dataset_revision(value: Any, path: str = "pinned_data_revision") -> str:
    """Return one immutable HuggingFace dataset repository+commit locator."""

    revision = require_string(value, path)
    match = _HF_REVISION_PATTERN.fullmatch(revision)
    if match is None:
        raise ModelValidationError(
            f"{path} must be an immutable HuggingFace dataset locator "
            "(huggingface://datasets/<repository>@<40-hex-commit>)"
        )
    repository, commit = match.groups()
    return f"huggingface://datasets/{repository}@{commit}"


def _require_external_revision(value: Any, path: str) -> str:
    revision = require_string(value, path)
    if revision != revision.strip() or any(character.isspace() for character in revision):
        raise ModelValidationError(f"{path} must be a trimmed immutable revision")
    if revision.casefold() in _IMMUTABLE_SOURCE_REVISIONS or revision.casefold().startswith("refs/heads/"):
        raise ModelValidationError(f"{path} must not be a symbolic revision")
    return revision


def _require_git_commit(value: Any, path: str) -> str:
    commit = require_string(value, path)
    if _GIT_COMMIT_PATTERN.fullmatch(commit) is None:
        raise ModelValidationError(f"{path} must be a lowercase 40-character git commit")
    return commit


def _require_exact_package_version(value: Any, path: str) -> str:
    version = require_string(value, path)
    if _EXACT_PACKAGE_VERSION_PATTERN.fullmatch(version) is None:
        raise ModelValidationError(f"{path} must be an exact semantic version, not a floating label")
    return version


@dataclass(frozen=True)
class ExternalSourceReference:
    """A digest-pinned artifact acquired outside the platform admission path."""

    schema_version: int
    storage_id: str
    revision: str
    content_digest: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "storage_id": self.storage_id,
            "revision": self.revision,
            "content_digest": self.content_digest,
        }

    def load(self, content: bytes | bytearray) -> bytes:
        """Accept only bytes matching the pinned digest; perform no acquisition."""

        if not isinstance(content, (bytes, bytearray)):
            raise ModelValidationError("external source content must be bytes")
        loaded = bytes(content)
        if sha256_bytes(loaded) != self.content_digest:
            raise ModelValidationError("external source content digest mismatch")
        return loaded

    @classmethod
    def from_dict(cls, value: Any) -> "ExternalSourceReference":
        record = require_record(value, "external_source")
        require_exact_keys(record, {"schema_version", "storage_id", "revision", "content_digest"}, "external_source")
        return cls(
            require_schema_version(record["schema_version"], "external_source.schema_version"),
            require_identifier(record["storage_id"], "external_source.storage_id"),
            _require_external_revision(record["revision"], "external_source.revision"),
            require_sha256(record["content_digest"], "external_source.content_digest"),
        )


def load_digest_pinned_source(reference: ExternalSourceReference, content: bytes | bytearray) -> bytes:
    """Pure loading seam used by runtimes after out-of-band acquisition."""

    return reference.load(content)


@dataclass(frozen=True)
class ChallengeContract:
    """Family-owned decision rule copied into the lock without caller override."""

    schema_version: int
    challenge_revision_id: str
    decision_rule: DecisionRule

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "challenge_revision_id": self.challenge_revision_id,
            "decision_rule": self.decision_rule.to_dict(),
        }

    @classmethod
    def from_dict(cls, value: Any) -> "ChallengeContract":
        record = require_record(value, "challenge_contract")
        require_exact_keys(record, {"schema_version", "challenge_revision_id", "decision_rule"}, "challenge_contract")
        return cls(
            require_schema_version(record["schema_version"], "challenge_contract.schema_version"),
            require_identifier(record["challenge_revision_id"], "challenge_contract.challenge_revision_id"),
            DecisionRule.from_dict(record["decision_rule"]),
        )


@dataclass(frozen=True)
class ReferenceQuestion:
    """Public reference content identity plus a blinded answer commitment."""

    schema_version: int
    question_id: str
    input_digest: str
    answer_key_commitment: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "question_id": self.question_id,
            "input_digest": self.input_digest,
            "answer_key_commitment": self.answer_key_commitment,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str = "reference_question") -> "ReferenceQuestion":
        record = require_record(value, path)
        require_exact_keys(record, {"schema_version", "question_id", "input_digest", "answer_key_commitment"}, path)
        return cls(
            require_schema_version(record["schema_version"], f"{path}.schema_version"),
            require_identifier(record["question_id"], f"{path}.question_id"),
            require_sha256(record["input_digest"], f"{path}.input_digest"),
            require_sha256(record["answer_key_commitment"], f"{path}.answer_key_commitment"),
        )


@dataclass(frozen=True)
class BenchmarkFamily:
    """Reusable family shape; GB-Pro construction adds its ten-reference rule."""

    schema_version: int
    family_id: str
    challenge_contract: ChallengeContract
    taskset_package: TasksetPackageReference
    taskset_source: ExternalSourceReference | None
    reference_source: ExternalSourceReference | None
    held_out_source: ExternalSourceReference | None
    reference_questions: tuple[ReferenceQuestion, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "family_id": self.family_id,
            "challenge_contract": self.challenge_contract.to_dict(),
            "taskset_package": self.taskset_package.to_dict(),
            "taskset_source": self.taskset_source.to_dict() if self.taskset_source is not None else None,
            "reference_source": self.reference_source.to_dict() if self.reference_source is not None else None,
            "held_out_source": self.held_out_source.to_dict() if self.held_out_source is not None else None,
            "reference_questions": [question.to_dict() for question in self.reference_questions],
        }

    def identity_content(self) -> dict[str, Any]:
        value = self.to_dict()
        value.pop("family_id")
        return value

    def expected_family_id(self) -> str:
        return content_id("family", self.identity_content())

    @classmethod
    def create(
        cls,
        *,
        challenge_contract: ChallengeContract,
        taskset_package: TasksetPackageReference,
        taskset_source: ExternalSourceReference | None = None,
        reference_source: ExternalSourceReference | None = None,
        held_out_source: ExternalSourceReference | None = None,
        reference_questions: tuple[ReferenceQuestion, ...] = (),
    ) -> "BenchmarkFamily":
        family = cls(
            schema_version=1,
            family_id="pending",
            challenge_contract=challenge_contract,
            taskset_package=taskset_package,
            taskset_source=taskset_source,
            reference_source=reference_source,
            held_out_source=held_out_source,
            reference_questions=reference_questions,
        )
        return replace(family, family_id=family.expected_family_id())

    @classmethod
    def from_dict(cls, value: Any) -> "BenchmarkFamily":
        record = require_record(value, "family")
        require_exact_keys(
            record,
            {
                "schema_version",
                "family_id",
                "challenge_contract",
                "taskset_package",
                "taskset_source",
                "reference_source",
                "held_out_source",
                "reference_questions",
            },
            "family",
        )
        raw_questions = require_type(record["reference_questions"], list, "family.reference_questions")
        questions = tuple(
            ReferenceQuestion.from_dict(item, f"family.reference_questions[{index}]")
            for index, item in enumerate(raw_questions)
        )
        question_ids = tuple(question.question_id for question in questions)
        if len(set(question_ids)) != len(question_ids):
            raise ModelValidationError("family.reference_questions must contain unique question identities")
        input_digests = tuple(question.input_digest for question in questions)
        if len(set(input_digests)) != len(input_digests):
            raise ModelValidationError("family.reference_questions must contain unique input content")

        def optional_source(value: Any, path: str) -> ExternalSourceReference | None:
            return None if value is None else ExternalSourceReference.from_dict(value)

        family = cls(
            require_schema_version(record["schema_version"], "family.schema_version"),
            require_identifier(record["family_id"], "family.family_id"),
            ChallengeContract.from_dict(record["challenge_contract"]),
            TasksetPackageReference.from_dict(record["taskset_package"]),
            optional_source(record["taskset_source"], "family.taskset_source"),
            optional_source(record["reference_source"], "family.reference_source"),
            optional_source(record["held_out_source"], "family.held_out_source"),
            questions,
        )
        if questions and family.reference_source is None:
            raise ModelValidationError("family.reference_source is required when reference questions exist")
        if family.family_id != family.expected_family_id():
            raise ModelValidationError("family.family_id does not match the canonical family content")
        return family


@dataclass(frozen=True)
class AuthoredQuestion:
    """Sealed-side four-field Forge question record plus canonical identity.

    ``question_id`` is derived only from public question content: task-input
    digest, publisher-stamped author identity, and pinned data revision.  The
    deterministic answer key and acceptance result never influence a public
    identifier.  Question text and synthetic data stay in the task input, not
    this record.  The raw deterministic answer key is never agent-visible.
    """

    schema_version: int
    question_id: str
    task_input_digest: str
    author_identity: str
    pinned_data_revision: str
    deterministic_answer_key: Any
    acceptance_decision: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "question_id": self.question_id,
            "task_input_digest": self.task_input_digest,
            "author_identity": self.author_identity,
            "pinned_data_revision": self.pinned_data_revision,
            "deterministic_answer_key": self.deterministic_answer_key,
            "acceptance_decision": self.acceptance_decision,
        }

    def identity_content(self) -> dict[str, Any]:
        return {
            "task_input_digest": self.task_input_digest,
            "author_identity": self.author_identity,
            "pinned_data_revision": self.pinned_data_revision,
        }

    def expected_question_id(self) -> str:
        return content_id("authored-question", self.identity_content())

    @classmethod
    def create(
        cls,
        *,
        task_input_digest: str,
        author_identity: str,
        pinned_data_revision: str,
        deterministic_answer_key: Any,
    ) -> "AuthoredQuestion":
        question = cls(
            schema_version=1,
            question_id="pending",
            task_input_digest=require_sha256(task_input_digest, "question.task_input_digest"),
            author_identity=require_identifier(author_identity, "question.author_identity"),
            pinned_data_revision=normalize_huggingface_dataset_revision(pinned_data_revision),
            deterministic_answer_key=require_json_value(deterministic_answer_key, "question.deterministic_answer_key"),
            acceptance_decision="pending",
        )
        return replace(question, question_id=question.expected_question_id())

    def answer_key_commitment(
        self,
        *,
        family: dict[str, Any],
        task: dict[str, Any],
        grader_source: bytes,
        blinding_nonce: bytes,
    ) -> str:
        """Commit to sealed material without exposing the raw answer key."""

        return sealed_answer_key_commitment(
            family=family,
            task=task,
            grader_source=grader_source,
            answer_key=self.deterministic_answer_key,
            blinding_nonce=blinding_nonce,
        )

    def public_dict(self, *, answer_key_commitment: str) -> dict[str, Any]:
        """Return the public-side projection; the raw four-field record stays sealed."""

        return {
            "schema_version": self.schema_version,
            "question_id": self.question_id,
            "acceptance_decision": self.acceptance_decision,
            "answer_key_commitment": require_sha256(answer_key_commitment, "question.answer_key_commitment"),
        }

    @classmethod
    def from_dict(cls, value: Any) -> "AuthoredQuestion":
        record = require_record(value, "question")
        require_exact_keys(
            record,
            {
                "schema_version",
                "question_id",
                "task_input_digest",
                "author_identity",
                "pinned_data_revision",
                "deterministic_answer_key",
                "acceptance_decision",
            },
            "question",
        )
        acceptance = require_string(record["acceptance_decision"], "question.acceptance_decision")
        if acceptance not in ACCEPTANCE_DECISIONS:
            raise ModelValidationError("question.acceptance_decision is invalid")
        question = cls(
            require_schema_version(record["schema_version"], "question.schema_version"),
            require_identifier(record["question_id"], "question.question_id"),
            require_sha256(record["task_input_digest"], "question.task_input_digest"),
            require_identifier(record["author_identity"], "question.author_identity"),
            normalize_huggingface_dataset_revision(record["pinned_data_revision"], "question.pinned_data_revision"),
            require_json_value(record["deterministic_answer_key"], "question.deterministic_answer_key"),
            acceptance,
        )
        if question.question_id != question.expected_question_id():
            raise ModelValidationError("question.question_id does not match the canonical question content")
        return question


@dataclass(frozen=True)
class VerifiersPin:
    """The exact Prime/Verifiers v1 pin carried by a season manifest."""

    api: str
    package_version: str
    git_commit: str
    trace_version: str

    def __post_init__(self) -> None:
        api = require_identifier(self.api, "season_manifest.verifiers.api")
        if api != "v1":
            raise ModelValidationError("season_manifest.verifiers.api must equal v1")
        _require_exact_package_version(self.package_version, "season_manifest.verifiers.package_version")
        _require_git_commit(self.git_commit, "season_manifest.verifiers.git_commit")
        require_identifier(self.trace_version, "season_manifest.verifiers.trace_version")

    def to_dict(self) -> dict[str, Any]:
        return {
            "api": self.api,
            "package_version": self.package_version,
            "git_commit": self.git_commit,
            "trace_version": self.trace_version,
        }

    @classmethod
    def from_dict(cls, value: Any) -> "VerifiersPin":
        record = require_record(value, "season_manifest.verifiers")
        require_exact_keys(record, {"api", "package_version", "git_commit", "trace_version"}, "season_manifest.verifiers")
        api = require_identifier(record["api"], "season_manifest.verifiers.api")
        if api != "v1":
            raise ModelValidationError("season_manifest.verifiers.api must equal v1")
        return cls(
            api,
            _require_exact_package_version(record["package_version"], "season_manifest.verifiers.package_version"),
            _require_git_commit(record["git_commit"], "season_manifest.verifiers.git_commit"),
            require_identifier(record["trace_version"], "season_manifest.verifiers.trace_version"),
        )


@dataclass(frozen=True)
class SeasonSplit:
    visibility: str
    reward_bearing: bool
    purpose: str

    def __post_init__(self) -> None:
        if self.purpose not in {"development", "certification", "anti-overfit"}:
            raise ModelValidationError("season_manifest split purpose is invalid")
        expected_split = {
            "development": ("public", False),
            "certification": ("hidden", True),
            "anti-overfit": ("hidden", False),
        }[self.purpose]
        if (self.visibility, self.reward_bearing) != expected_split:
            raise ModelValidationError("season_manifest split does not match the fixed three-split policy")
        require_identifier(self.visibility, "season_manifest.split.visibility")
        require_bool(self.reward_bearing, "season_manifest.split.reward_bearing")
        require_identifier(self.purpose, "season_manifest.split.purpose")

    def to_dict(self) -> dict[str, Any]:
        return {
            "visibility": self.visibility,
            "reward_bearing": self.reward_bearing,
            "purpose": self.purpose,
        }

    @classmethod
    def from_dict(cls, value: Any, path: str) -> "SeasonSplit":
        record = require_record(value, path)
        require_exact_keys(record, {"visibility", "reward_bearing", "purpose"}, path)
        return cls(
            require_identifier(record["visibility"], f"{path}.visibility"),
            require_bool(record["reward_bearing"], f"{path}.reward_bearing"),
            require_identifier(record["purpose"], f"{path}.purpose"),
        )


@dataclass(frozen=True)
class SeasonManifest:
    """Immutable challenge-bound season rules consumed by the protocol lock."""

    schema_version: int
    season_id: str
    challenge_revision_id: str
    verifiers: VerifiersPin
    benchmark_identity: str
    benchmark_public_name: str
    benchmark_category: str
    taskset_package: TasksetPackageReference
    mutable_paths: tuple[str, ...]
    capsule_template: DeclaredCapsule
    runtime_provider: str
    runtime_permissions_profile: tuple[str, ...]
    budgets: dict[str, Any]
    hidden_evaluation_source: ExternalSourceReference
    hidden_evaluation_access_policy: str
    acceptance_rules: DecisionRule
    reproduction_policy: dict[str, Any]
    reward_config: dict[str, Any]
    development: SeasonSplit
    certification: SeasonSplit
    successor: SeasonSplit
    _allow_pending: bool = field(default=False, compare=False, repr=False)

    def __post_init__(self) -> None:
        require_schema_version(self.schema_version, "season_manifest.schema_version")
        require_identifier(self.season_id, "season_manifest.season_id")
        require_identifier(self.challenge_revision_id, "season_manifest.challenge_revision_id")
        if not isinstance(self.verifiers, VerifiersPin):
            raise ModelValidationError("season_manifest.verifiers must be a VerifiersPin")
        VerifiersPin.from_dict(self.verifiers.to_dict())
        require_identifier(self.benchmark_identity, "season_manifest.benchmark.identity")
        require_string(self.benchmark_public_name, "season_manifest.benchmark.public_name")
        require_identifier(self.benchmark_category, "season_manifest.benchmark.category")
        if not isinstance(self.taskset_package, TasksetPackageReference):
            raise ModelValidationError("season_manifest.benchmark.taskset_package must be a TasksetPackageReference")
        TasksetPackageReference.from_dict(self.taskset_package.to_dict())
        if self.mutable_paths != ("SKILL.md",):
            raise ModelValidationError("season_manifest.mutable_paths must contain only SKILL.md")
        if not isinstance(self.capsule_template, DeclaredCapsule):
            raise ModelValidationError("season_manifest.capsule_template must be a DeclaredCapsule")
        DeclaredCapsule.from_dict(self.capsule_template.to_dict())
        require_identifier(self.runtime_provider, "season_manifest.runtime.provider")
        if not self.runtime_permissions_profile:
            raise ModelValidationError("season_manifest.runtime.permissions_profile must not be empty")
        for index, permission in enumerate(self.runtime_permissions_profile):
            require_identifier(permission, f"season_manifest.runtime.permissions_profile[{index}]")
        for value, path in (
            (self.budgets, "season_manifest.budgets"),
            (self.reproduction_policy, "season_manifest.reproduction_policy"),
            (self.reward_config, "season_manifest.reward_config"),
        ):
            if type(value) is not dict or not value:
                raise ModelValidationError(f"{path} must be a non-empty object")
            require_json_value(value, path)
        if not isinstance(self.hidden_evaluation_source, ExternalSourceReference):
            raise ModelValidationError("season_manifest.hidden_evaluation.source must be an ExternalSourceReference")
        ExternalSourceReference.from_dict(self.hidden_evaluation_source.to_dict())
        require_identifier(self.hidden_evaluation_access_policy, "season_manifest.hidden_evaluation.access_policy")
        if not isinstance(self.acceptance_rules, DecisionRule):
            raise ModelValidationError("season_manifest.acceptance_rules must be a DecisionRule")
        DecisionRule.from_dict(self.acceptance_rules.to_dict())
        if not isinstance(self.development, SeasonSplit) or not isinstance(self.certification, SeasonSplit) or not isinstance(self.successor, SeasonSplit):
            raise ModelValidationError("season_manifest.splits must contain SeasonSplit values")
        expected_splits = {
            "development": SeasonSplit("public", False, "development"),
            "certification": SeasonSplit("hidden", True, "certification"),
            "successor": SeasonSplit("hidden", False, "anti-overfit"),
        }
        actual_splits = {
            "development": self.development,
            "certification": self.certification,
            "successor": self.successor,
        }
        if actual_splits != expected_splits:
            raise ModelValidationError("season_manifest.splits must use the fixed three-split policy")
        if self.season_id == "pending":
            if not self._allow_pending:
                raise ModelValidationError("season_manifest.season_id must be the canonical season identity")
        elif self.season_id != self.expected_season_id():
            raise ModelValidationError("season_manifest.season_id does not match the canonical manifest content")

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "season_id": self.season_id,
            "challenge_revision_id": self.challenge_revision_id,
            "verifiers": self.verifiers.to_dict(),
            "benchmark": {
                "identity": self.benchmark_identity,
                "public_name": self.benchmark_public_name,
                "category": self.benchmark_category,
                "taskset_package": self.taskset_package.to_dict(),
            },
            "mutable_paths": list(self.mutable_paths),
            "model": {
                "provider": self.capsule_template.provider,
                "identifier": self.capsule_template.model,
            },
            "sampling": {"inference_settings": [{"name": name, "value": value} for name, value in self.capsule_template.inference_settings]},
            "harness": {
                "version": self.capsule_template.hermes_version,
                "configuration": self.capsule_template.hermes_configuration,
            },
            "capsule_template": self.capsule_template.to_dict(),
            "runtime": {
                "provider": self.runtime_provider,
                "permissions_profile": list(self.runtime_permissions_profile),
            },
            "budgets": self.budgets,
            "hidden_evaluation": {
                "source": self.hidden_evaluation_source.to_dict(),
                "content_hash": self.hidden_evaluation_source.content_digest,
                "access_policy": self.hidden_evaluation_access_policy,
            },
            "acceptance_rules": self.acceptance_rules.to_dict(),
            "reproduction_policy": self.reproduction_policy,
            "reward_config": self.reward_config,
            "splits": {
                "development": self.development.to_dict(),
                "certification": self.certification.to_dict(),
                "successor": self.successor.to_dict(),
            },
        }

    def identity_content(self) -> dict[str, Any]:
        value = self.to_dict()
        value.pop("season_id")
        return value

    def expected_season_id(self) -> str:
        return content_id("season-manifest", self.identity_content())

    @classmethod
    def create(
        cls,
        *,
        family: BenchmarkFamily,
        verifiers: VerifiersPin,
        benchmark_public_name: str,
        benchmark_category: str,
        capsule_template: DeclaredCapsule,
        runtime_provider: str = "prime",
        runtime_permissions_profile: tuple[str, ...] | None = None,
        budgets: dict[str, Any] | None = None,
        hidden_evaluation_access_policy: str = "runtime-scoped-sealed-external",
        reproduction_policy: dict[str, Any] | None = None,
        reward_config: dict[str, Any] | None = None,
    ) -> "SeasonManifest":
        if not isinstance(family, BenchmarkFamily):
            raise ModelValidationError("season_manifest.family must be a BenchmarkFamily")
        canonical_family = BenchmarkFamily.from_dict(family.to_dict())
        if canonical_family.held_out_source is None:
            raise ModelValidationError("season_manifest requires a pinned held-out evaluation source")
        if not isinstance(capsule_template, DeclaredCapsule):
            raise ModelValidationError("season_manifest.capsule_template must be a DeclaredCapsule")
        permissions = capsule_template.runtime_permissions if runtime_permissions_profile is None else runtime_permissions_profile
        budget_config = {
            "attempts_per_task": 1,
            "max_task_wall_seconds": 600,
            "max_spend_usd_cents": 1_000,
        } if budgets is None else budgets
        reproduction_config = {
            "minimum_runs": 1,
            "package_required": True,
            "tolerance": "predeclared",
        } if reproduction_policy is None else reproduction_policy
        reward_config_value = {"mode": "none"} if reward_config is None else reward_config
        manifest = cls(
            schema_version=1,
            season_id="pending",
            challenge_revision_id=canonical_family.challenge_contract.challenge_revision_id,
            verifiers=verifiers,
            benchmark_identity=canonical_family.family_id,
            benchmark_public_name=require_string(benchmark_public_name, "season_manifest.benchmark.public_name"),
            benchmark_category=require_identifier(benchmark_category, "season_manifest.benchmark.category"),
            taskset_package=canonical_family.taskset_package,
            mutable_paths=("SKILL.md",),
            capsule_template=capsule_template,
            runtime_provider=runtime_provider,
            runtime_permissions_profile=tuple(permissions),
            budgets=budget_config,
            hidden_evaluation_source=canonical_family.held_out_source,
            hidden_evaluation_access_policy=hidden_evaluation_access_policy,
            acceptance_rules=canonical_family.challenge_contract.decision_rule,
            reproduction_policy=reproduction_config,
            reward_config=reward_config_value,
            development=SeasonSplit("public", False, "development"),
            certification=SeasonSplit("hidden", True, "certification"),
            successor=SeasonSplit("hidden", False, "anti-overfit"),
            _allow_pending=True,
        )
        return replace(manifest, season_id=manifest.expected_season_id(), _allow_pending=False)

    @classmethod
    def from_dict(cls, value: Any, *, family: BenchmarkFamily) -> "SeasonManifest":
        record = require_record(value, "season_manifest")
        require_exact_keys(
            record,
            {
                "schema_version",
                "season_id",
                "challenge_revision_id",
                "verifiers",
                "benchmark",
                "mutable_paths",
                "model",
                "sampling",
                "harness",
                "capsule_template",
                "runtime",
                "budgets",
                "hidden_evaluation",
                "acceptance_rules",
                "reproduction_policy",
                "reward_config",
                "splits",
            },
            "season_manifest",
        )
        if not isinstance(family, BenchmarkFamily):
            raise ModelValidationError("season_manifest.family must be a BenchmarkFamily")
        benchmark = require_record(record["benchmark"], "season_manifest.benchmark")
        require_exact_keys(
            benchmark,
            {"identity", "public_name", "category", "taskset_package"},
            "season_manifest.benchmark",
        )
        model = require_record(record["model"], "season_manifest.model")
        require_exact_keys(model, {"provider", "identifier"}, "season_manifest.model")
        sampling = require_record(record["sampling"], "season_manifest.sampling")
        require_exact_keys(sampling, {"inference_settings"}, "season_manifest.sampling")
        harness = require_record(record["harness"], "season_manifest.harness")
        require_exact_keys(harness, {"version", "configuration"}, "season_manifest.harness")
        runtime = require_record(record["runtime"], "season_manifest.runtime")
        require_exact_keys(runtime, {"provider", "permissions_profile"}, "season_manifest.runtime")
        hidden = require_record(record["hidden_evaluation"], "season_manifest.hidden_evaluation")
        require_exact_keys(hidden, {"source", "content_hash", "access_policy"}, "season_manifest.hidden_evaluation")
        hidden_source = ExternalSourceReference.from_dict(hidden["source"])
        if require_sha256(hidden["content_hash"], "season_manifest.hidden_evaluation.content_hash") != hidden_source.content_digest:
            raise ModelValidationError("season_manifest.hidden_evaluation.content_hash does not match its source")
        splits = require_record(record["splits"], "season_manifest.splits")
        require_exact_keys(splits, {"development", "certification", "successor"}, "season_manifest.splits")
        manifest = cls(
            require_schema_version(record["schema_version"], "season_manifest.schema_version"),
            require_identifier(record["season_id"], "season_manifest.season_id"),
            require_identifier(record["challenge_revision_id"], "season_manifest.challenge_revision_id"),
            VerifiersPin.from_dict(record["verifiers"]),
            require_identifier(benchmark["identity"], "season_manifest.benchmark.identity"),
            require_string(benchmark["public_name"], "season_manifest.benchmark.public_name"),
            require_identifier(benchmark["category"], "season_manifest.benchmark.category"),
            TasksetPackageReference.from_dict(benchmark["taskset_package"]),
            tuple(require_identifier_list(record["mutable_paths"], "season_manifest.mutable_paths")),
            DeclaredCapsule.from_dict(record["capsule_template"]),
            require_identifier(runtime["provider"], "season_manifest.runtime.provider"),
            tuple(require_identifier_list(runtime["permissions_profile"], "season_manifest.runtime.permissions_profile")),
            require_json_value(record["budgets"], "season_manifest.budgets"),
            hidden_source,
            require_identifier(hidden["access_policy"], "season_manifest.hidden_evaluation.access_policy"),
            DecisionRule.from_dict(record["acceptance_rules"]),
            require_json_value(record["reproduction_policy"], "season_manifest.reproduction_policy"),
            require_json_value(record["reward_config"], "season_manifest.reward_config"),
            SeasonSplit.from_dict(splits["development"], "season_manifest.splits.development"),
            SeasonSplit.from_dict(splits["certification"], "season_manifest.splits.certification"),
            SeasonSplit.from_dict(splits["successor"], "season_manifest.splits.successor"),
        )
        expected_model = {
            "provider": manifest.capsule_template.provider,
            "identifier": manifest.capsule_template.model,
        }
        expected_sampling = {
            "inference_settings": [
                {"name": name, "value": value}
                for name, value in manifest.capsule_template.inference_settings
            ]
        }
        expected_harness = {
            "version": manifest.capsule_template.hermes_version,
            "configuration": manifest.capsule_template.hermes_configuration,
        }
        if model != expected_model or sampling != expected_sampling or harness != expected_harness:
            raise ModelValidationError("season_manifest capsule template does not match its pinned model, sampling, or harness")
        canonical_family = BenchmarkFamily.from_dict(family.to_dict())
        if manifest.benchmark_identity != canonical_family.family_id:
            raise ModelValidationError("season_manifest.benchmark.identity does not match the family")
        if manifest.challenge_revision_id != canonical_family.challenge_contract.challenge_revision_id:
            raise ModelValidationError("season_manifest.challenge_revision_id does not match the family")
        if manifest.taskset_package != canonical_family.taskset_package:
            raise ModelValidationError("season_manifest taskset package does not match the family")
        if manifest.hidden_evaluation_source != canonical_family.held_out_source:
            raise ModelValidationError("season_manifest hidden evaluation source does not match the family")
        if manifest.acceptance_rules != canonical_family.challenge_contract.decision_rule:
            raise ModelValidationError("season_manifest acceptance rules do not match the challenge contract")
        return manifest
