"""Lock a matched protocol before any baseline or candidate execution."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import replace
from typing import Any, Sequence

from verify_runtime.families import (
    CANDIDATE_SKILL,
    CHALLENGE_REVISION_ID,
    DECISION_RULE,
    FAMILY,
    GB_PRO_GRADER_SOURCE,
    GB_PRO_TASKS,
    GRADER_SOURCE,
    TASKS,
    TASKSET_PACKAGE,
    TREATMENT_DIFF,
)
from verify_runtime.families.contract_drift import _BUILTIN_AUTHORED_RECORDS
from verify_runtime.model import (
    AuthoredQuestion,
    BenchmarkFamily,
    Capsule,
    canonical_json_bytes,
    EnvironmentFamily,
    EvaluationProtocol,
    MatchedSelection,
    ModelValidationError,
    SeasonManifest,
    sha256_bytes,
    TaskInstance,
    TasksetPackageReference,
    VerifyPolicy,
)
from verify_runtime.model.base import require_identifier


FOUNDER_DEFAULT_POLICY = VerifyPolicy(
    policy_id="verify-public-default-v1",
    attempts_per_task=1,
    max_task_wall_seconds=600,
    max_comparison_spend_usd_cents=1_000,
    timeout_treatment="terminal-timeout-not-scored",
    missing_result_treatment="terminal-invalid-not-scored",
    infrastructure_failure_treatment="terminal-infrastructure-failure-not-scored",
)


def _validate_capsules(baseline: Capsule, candidate: Capsule) -> None:
    if baseline.resolved.skill_digest == candidate.resolved.skill_digest:
        raise ValueError("baseline and candidate must differ in SKILL.md")
    if baseline.declared.to_dict() | {"skill_source": candidate.declared.skill_source} != candidate.declared.to_dict():
        raise ValueError("built-in comparison must change only SKILL.md")
    baseline_resolved = baseline.resolved.to_dict()
    candidate_resolved = candidate.resolved.to_dict()
    baseline_resolved["skill"] = candidate_resolved["skill"]
    if baseline_resolved != candidate_resolved:
        raise ValueError("built-in comparison resolved more than SKILL.md differently")


def _normalized_tasks(tasks: Sequence[TaskInstance], family_id: str) -> tuple[TaskInstance, ...]:
    normalized = tuple(
        replace(
            TaskInstance.from_dict(task.to_dict()),
            answer_key_commitment=task.answer_key_commitment,
            answer_key_blinding_nonce=task.answer_key_blinding_nonce,
        )
        for task in tasks
    )
    task_ids = tuple(task.task_id for task in normalized)
    if len(set(task_ids)) != len(task_ids):
        raise ModelValidationError("lock taskset contains duplicate task identities")
    if any(task.family_id != family_id for task in normalized):
        raise ModelValidationError("lock taskset contains a task from another family")
    return normalized


_GB_PRO_LOCAL_PUBLISHER = "agent://regent/forge-author-01"
_LOCAL_DEVELOPMENT_PUBLICATIONS = tuple(
    (
        record,
        "regent://builtin/contract-drift-publisher-v1",
        f"local-development://publications/{record['question_id']}",
    )
    for record in _BUILTIN_AUTHORED_RECORDS
) + (
    (
        replace(
            AuthoredQuestion.create(
                task_input_digest=GB_PRO_TASKS[-1].input_digest,
                author_identity=_GB_PRO_LOCAL_PUBLISHER,
                pinned_data_revision=f"huggingface://datasets/regent-gb-pro@{'c' * 40}",
                deterministic_answer_key={"accepted": True, "answer": "fixture"},
            ),
            acceptance_decision="accepted",
        ).to_dict(),
        _GB_PRO_LOCAL_PUBLISHER,
        "local-development://publications/gb-pro-authored-held-out-01",
    ),
    (
        replace(
            AuthoredQuestion.create(
                task_input_digest=sha256_bytes(b"zero-reference-input\n"),
                author_identity=_GB_PRO_LOCAL_PUBLISHER,
                pinned_data_revision=f"huggingface://datasets/regent-gb-pro@{'c' * 40}",
                deterministic_answer_key={"answer": "zero-reference"},
            ),
            acceptance_decision="accepted",
        ).to_dict(),
        _GB_PRO_LOCAL_PUBLISHER,
        "local-development://publications/zero-reference-held-out-01",
    ),
)

# This inspectable tuple is only a local-development stand-in for the platform
# verified-publication layer. It provides no in-process trust guarantee.
# Official verification compares the emitted bindings with the authoritative,
# digest-pinned publication record outside this producing process.
_LOCAL_DEVELOPMENT_GRADER_SOURCES = {
    sha256_bytes(GRADER_SOURCE): GRADER_SOURCE,
    sha256_bytes(GB_PRO_GRADER_SOURCE): GB_PRO_GRADER_SOURCE,
}


def _local_publication_content(record: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "schema_version": record["schema_version"],
        "task_input_digest": record["task_input_digest"],
        "pinned_data_revision": record["pinned_data_revision"],
        "deterministic_answer_key": record["deterministic_answer_key"],
        "acceptance_decision": record["acceptance_decision"],
    }


def _publication_from_local_development_context(
    record: Mapping[str, Any],
) -> tuple[str, str] | None:
    content = _local_publication_content(record)
    for stored_record, publisher_identity, publication_reference in _LOCAL_DEVELOPMENT_PUBLICATIONS:
        if _local_publication_content(stored_record) == content:
            return publisher_identity, publication_reference
    return None


def _validate_authored_records(
    authored_records: Sequence[dict[str, Any]],
    tasks: Sequence[TaskInstance],
) -> tuple[tuple[AuthoredQuestion, str], ...]:
    normalized: list[tuple[AuthoredQuestion, str]] = []
    for raw_record in authored_records:
        # Parse and execute the canonical recorded-decision rule from raw
        # caller content before consulting the local development context.
        question = AuthoredQuestion.from_dict(raw_record)
        if question.acceptance_decision != "accepted":
            raise ModelValidationError(
                f"authored_question_validation_{question.acceptance_decision}: "
                "authored question validation did not accept the record"
            )
        publication = _publication_from_local_development_context(question.to_dict())
        if publication is None:
            raise ModelValidationError("authored question is absent from local development publication context")
        publisher_identity, publication_reference = publication

        # Publisher identity comes from the publication-layer answer. This is
        # content binding, not an in-process authenticity guarantee.
        accepted = AuthoredQuestion(
            schema_version=question.schema_version,
            question_id="pending",
            task_input_digest=question.task_input_digest,
            author_identity=require_identifier(
                publisher_identity,
                "local_publication.publisher_identity",
            ),
            pinned_data_revision=question.pinned_data_revision,
            deterministic_answer_key=question.deterministic_answer_key,
            acceptance_decision="accepted",
        )
        accepted = replace(accepted, question_id=accepted.expected_question_id())
        if question.question_id != accepted.question_id:
            raise ModelValidationError("authored question identity does not match its publication publisher")
        normalized.append((AuthoredQuestion.from_dict(accepted.to_dict()), publication_reference))
    normalized = tuple(normalized)
    questions = tuple(question for question, _ in normalized)
    question_ids = tuple(question.question_id for question in questions)
    if len(set(question_ids)) != len(question_ids):
        raise ModelValidationError("lock authored questions contain duplicate identities")
    held_out_inputs = {task.input_digest for task in tasks if task.provenance == "held_out"}
    authored_inputs = tuple(question.task_input_digest for question in questions)
    if len(set(authored_inputs)) != len(authored_inputs):
        raise ModelValidationError("lock authored questions contain duplicate task inputs")
    if any(input_digest not in held_out_inputs for input_digest in authored_inputs):
        raise ModelValidationError("accepted authored question is absent from a held-out locked task")
    missing = held_out_inputs - set(authored_inputs)
    if missing:
        raise ModelValidationError("every held_out task requires an accepted authored question")
    return normalized


def _publication_binding(
    question: AuthoredQuestion,
    task: TaskInstance,
    *,
    answer_key_commitment: str,
    publication_reference: str,
) -> dict[str, Any]:
    return {
        "publication_reference": publication_reference,
        "question_id": question.question_id,
        "publisher_identity": question.author_identity,
        "dataset_revision": question.pinned_data_revision,
        "task_id": task.task_id,
        "task_input_digest": task.input_digest,
        "answer_key_commitment": answer_key_commitment,
    }


def _bind_held_out_commitments(
    *,
    family: Mapping[str, Any],
    tasks: Sequence[TaskInstance],
    publications: Sequence[tuple[AuthoredQuestion, str]],
) -> tuple[tuple[TaskInstance, ...], tuple[dict[str, Any], ...]]:
    by_input = {
        question.task_input_digest: (question, publication_reference)
        for question, publication_reference in publications
    }
    bound_tasks: list[TaskInstance] = []
    bindings: list[dict[str, Any]] = []
    for task in tasks:
        if task.provenance != "held_out":
            bound_tasks.append(task)
            continue
        question, publication_reference = by_input[task.input_digest]
        if task.answer_key_blinding_nonce is None:
            raise ModelValidationError("held_out_answer_commitment_missing_nonce: held-out task has no sealed nonce")
        grader_source = _LOCAL_DEVELOPMENT_GRADER_SOURCES.get(task.grader_digest)
        if grader_source is None:
            raise ModelValidationError("held_out_answer_commitment_missing_grader: held-out grader is unavailable")
        expected_commitment = question.answer_key_commitment(
            family=dict(family),
            task=task.to_dict(),
            grader_source=grader_source,
            blinding_nonce=task.answer_key_blinding_nonce,
        )
        if task.answer_key_commitment != expected_commitment:
            raise ModelValidationError(
                "held_out_answer_commitment_mismatch: task commitment does not match the validated authored answer"
            )
        bound_task = replace(task, answer_key_commitment=expected_commitment)
        bound_tasks.append(bound_task)
        bindings.append(
            _publication_binding(
                question,
                bound_task,
                answer_key_commitment=expected_commitment,
                publication_reference=publication_reference,
            )
        )
    return tuple(bound_tasks), tuple(bindings)


def _validate_reference_commitments(
    family: BenchmarkFamily,
    tasks: Sequence[TaskInstance],
) -> None:
    references = {question.input_digest: question for question in family.reference_questions}
    for task in tasks:
        reference = references.get(task.input_digest)
        if reference is not None and task.provenance == "held_out":
            raise ModelValidationError("held_out task input digest matches a pinned public reference")
        if task.provenance == "public_reference":
            if reference is None:
                raise ModelValidationError("public_reference task content is not declared by the family")
            if task.answer_key_commitment != reference.answer_key_commitment:
                raise ModelValidationError("public_reference answer-key commitment does not match the family")


def _selections(tasks: Sequence[TaskInstance]) -> tuple[MatchedSelection, ...]:
    matched_tasks = tuple(task for task in tasks if task.partition != "development")
    return tuple(
        MatchedSelection(
            task_id=task.task_id,
            partition=task.partition,
            matched_order=order,
            provenance=task.provenance,
            answer_key_commitment=task.answer_key_commitment,
        )
        for order, task in enumerate(matched_tasks)
    )


def _protocol(
    *,
    family_id: str,
    baseline: Capsule,
    candidate: Capsule,
    selections: tuple[MatchedSelection, ...],
    development_task_ids: tuple[str, ...],
    validation_task_ids: tuple[str, ...],
    untouched_task_ids: tuple[str, ...],
    taskset_package: TasksetPackageReference,
    challenge_revision_id: str,
    decision_rule,
    treatment_skill_content: str,
    season_id: str | None,
    publication_bindings: tuple[dict[str, Any], ...],
) -> EvaluationProtocol:
    publication_context = canonical_json_bytes(
        {
            "profile": "default",
            "publication_bindings": list(publication_bindings),
        }
    ).decode("utf-8")
    protocol = EvaluationProtocol(
        schema_version=1,
        protocol_id="pending",
        family_id=family_id,
        baseline_capsule_id=baseline.capsule_id,
        candidate_capsule_id=candidate.capsule_id,
        intervention_class="skill",
        changed_files=("SKILL.md",),
        baseline_class="canonical-community-baseline",
        baseline_justification="current Hermes hosted default resolved at capsule resolution",
        selections=selections,
        development_task_ids=development_task_ids,
        validation_task_ids=validation_task_ids,
        untouched_task_ids=untouched_task_ids,
        optimizer_method="manual",
        optimizer_candidate_count=1,
        rejected_candidate_ids=(),
        policy=FOUNDER_DEFAULT_POLICY,
        taskset_version=taskset_package,
        challenge_revision_id=challenge_revision_id,
        season_id=season_id,
        treatment_skill_source="builtin://candidate/SKILL.md",
        treatment_skill_content=treatment_skill_content,
        treatment_diff=TREATMENT_DIFF,
        exact_commands=(
            "regents techtree verify run --builtin --executor <fixture|hermes|prime> --json",
            "regents techtree uplift report " + " ".join("--receipt-digest <sha256>" for _ in selections) + " --json",
        ),
        harness_settings=(("publication_context", publication_context),),
        seeds=(),
        expected_output_schema="verify_runtime.execution_result.v1",
        decision_rule=decision_rule,
    )
    return EvaluationProtocol.from_dict(replace(protocol, protocol_id=protocol.expected_protocol_id()).to_dict())


def _lock_from_records(
    baseline: Capsule,
    candidate: Capsule,
    *,
    family: Mapping[str, Any],
    family_id: str,
    tasks: Sequence[TaskInstance],
    taskset_package: TasksetPackageReference,
    challenge_revision_id: str,
    decision_rule,
    season: SeasonManifest | None = None,
    authored_records: Sequence[dict[str, Any]] = (),
) -> EvaluationProtocol:
    _validate_capsules(baseline, candidate)
    normalized_tasks = _normalized_tasks(tasks, family_id)
    if season is not None and season.capsule_template.to_dict() != baseline.declared.to_dict():
        raise ModelValidationError("season_manifest capsule template does not match the locked baseline capsule")
    publications = _validate_authored_records(authored_records, normalized_tasks)
    normalized_tasks, publication_bindings = _bind_held_out_commitments(
        family=family,
        tasks=normalized_tasks,
        publications=publications,
    )
    selections = _selections(normalized_tasks)
    if not selections:
        raise ModelValidationError("lock taskset contains no scored or calibration tasks")
    partitions = {
        partition: tuple(task.task_id for task in normalized_tasks if task.partition == partition)
        for partition in ("development", "validation", "untouched")
    }
    return _protocol(
        family_id=family_id,
        baseline=baseline,
        candidate=candidate,
        selections=selections,
        development_task_ids=partitions["development"],
        validation_task_ids=partitions["validation"],
        untouched_task_ids=partitions["untouched"],
        taskset_package=taskset_package,
        challenge_revision_id=challenge_revision_id,
        decision_rule=decision_rule,
        treatment_skill_content=CANDIDATE_SKILL.decode("utf-8"),
        season_id=season.season_id if season is not None else None,
        publication_bindings=publication_bindings,
    )


def lock_benchmark_protocol(
    baseline: Capsule,
    candidate: Capsule,
    *,
    family: BenchmarkFamily,
    season: SeasonManifest,
    tasks: Sequence[TaskInstance],
    authored_records: Sequence[dict[str, Any]] = (),
) -> EvaluationProtocol:
    """Lock a family using only its rule, revision, package, and task provenance."""

    locked_family = BenchmarkFamily.from_dict(family.to_dict())
    locked_season = SeasonManifest.from_dict(season.to_dict(), family=locked_family)
    normalized_tasks = _normalized_tasks(tasks, locked_family.family_id)
    _validate_reference_commitments(locked_family, normalized_tasks)
    return _lock_from_records(
        baseline,
        candidate,
        family=locked_family.to_dict(),
        family_id=locked_family.family_id,
        tasks=normalized_tasks,
        taskset_package=locked_family.taskset_package,
        challenge_revision_id=locked_family.challenge_contract.challenge_revision_id,
        decision_rule=locked_family.challenge_contract.decision_rule,
        season=locked_season,
        authored_records=authored_records,
    )


def lock_builtin_protocol(baseline: Capsule, candidate: Capsule) -> EvaluationProtocol:
    """Lock the existing offline family while carrying the new commitments."""

    family = EnvironmentFamily.from_dict(FAMILY.to_dict())
    tasks = TASKS
    return _lock_from_records(
        baseline,
        candidate,
        family=family.to_dict(),
        family_id=family.family_id,
        tasks=tasks,
        taskset_package=TASKSET_PACKAGE,
        challenge_revision_id=CHALLENGE_REVISION_ID,
        decision_rule=DECISION_RULE,
        season=None,
        authored_records=_BUILTIN_AUTHORED_RECORDS,
    )
