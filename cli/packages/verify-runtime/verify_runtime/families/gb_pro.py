"""Representative GB-Pro family metadata with no dataset fetch or embedded task shapes."""

from __future__ import annotations

from dataclasses import replace

from verify_runtime.model import (
    BenchmarkFamily,
    ChallengeContract,
    DecisionRule,
    ExternalSourceReference,
    ReferenceQuestion,
    SevereRegressionRule,
    TaskInstance,
    TasksetPackageReference,
    new_answer_key_blinding_nonce,
    sealed_answer_key_commitment,
    sha256_bytes,
)


GB_PRO_REFERENCE_DATA = b"gb-pro-reference-dataset-fixture-v1\n"
GB_PRO_HELD_OUT_DATA = b"gb-pro-held-out-dataset-fixture-v1\n"
GB_PRO_GRADER_SOURCE = b"gb-pro-deterministic-grader-fixture-v1\n"
GB_PRO_GRADER_DIGEST = sha256_bytes(GB_PRO_GRADER_SOURCE)

GB_PRO_REFERENCE_SOURCE = ExternalSourceReference(
    schema_version=1,
    storage_id="huggingface://datasets/gene-bench-pro",
    revision="a" * 40,
    content_digest=sha256_bytes(GB_PRO_REFERENCE_DATA),
)
GB_PRO_HELD_OUT_SOURCE = ExternalSourceReference(
    schema_version=1,
    storage_id="huggingface://datasets/regent-gb-pro-held-out",
    revision="b" * 40,
    content_digest=sha256_bytes(GB_PRO_HELD_OUT_DATA),
)
GB_PRO_TASKSET_PACKAGE = TasksetPackageReference(
    schema_version=1,
    package="verifiers.v1.taskset.gene-bench-pro",
    version="1",
    content_hash=sha256_bytes(b"gb-pro-verifiers-v1-taskset-package-fixture\n"),
)
GB_PRO_DECISION_RULE = DecisionRule(
    primary_metric="score_millis",
    minimum_valid_task_count=1,
    positive_threshold_millis=100,
    negative_threshold_millis=-100,
    null_band_millis=0,
    severe_regression_rule=SevereRegressionRule("delta_at_or_below", 100),
    inconclusive_conditions=("valid_task_count_below_minimum", "delta_between_thresholds"),
    invalid_conditions=("any_arm_not_completed", "missing_score"),
)
GB_PRO_CHALLENGE_CONTRACT = ChallengeContract(
    schema_version=1,
    challenge_revision_id="gb-pro-challenge-v1",
    decision_rule=GB_PRO_DECISION_RULE,
)

_REFERENCE_NONCES: dict[str, bytes] = {}


def _reference_question(question_number: int) -> ReferenceQuestion:
    question_id = f"gb-pro-reference-{question_number:02d}"
    input_digest = sha256_bytes(f"gb-pro-reference-input-{question_number}\n".encode())
    blinding_nonce = new_answer_key_blinding_nonce()
    _REFERENCE_NONCES[question_id] = blinding_nonce
    task = {
        "schema_version": 1,
        "task_id": question_id,
        "family_id": "gb-pro-family-pending",
        "slice_id": "gb-pro.reference",
        "partition": "untouched",
        "role_id": "gb-pro-agent",
        "input_digest": input_digest,
        "grader_digest": GB_PRO_GRADER_DIGEST,
        "provenance": "public_reference",
    }
    commitment = sealed_answer_key_commitment(
        family={
            "schema_version": 1,
            "challenge_contract": GB_PRO_CHALLENGE_CONTRACT.to_dict(),
            "taskset_package": GB_PRO_TASKSET_PACKAGE.to_dict(),
            "taskset_source": GB_PRO_REFERENCE_SOURCE.to_dict(),
            "reference_source": GB_PRO_REFERENCE_SOURCE.to_dict(),
            "held_out_source": GB_PRO_HELD_OUT_SOURCE.to_dict(),
        },
        task=task,
        grader_source=GB_PRO_GRADER_SOURCE,
        answer_key={"reference_number": question_number, "fixture": True},
        blinding_nonce=blinding_nonce,
    )
    return ReferenceQuestion(1, question_id, input_digest, commitment)


GB_PRO_REFERENCE_QUESTIONS = tuple(_reference_question(number) for number in range(1, 11))
GB_PRO_FAMILY = BenchmarkFamily.create(
    challenge_contract=GB_PRO_CHALLENGE_CONTRACT,
    taskset_package=GB_PRO_TASKSET_PACKAGE,
    taskset_source=GB_PRO_REFERENCE_SOURCE,
    reference_source=GB_PRO_REFERENCE_SOURCE,
    held_out_source=GB_PRO_HELD_OUT_SOURCE,
    reference_questions=GB_PRO_REFERENCE_QUESTIONS,
)


_HELD_OUT_NONCE = new_answer_key_blinding_nonce()


def _task(task_id: str, partition: str, provenance: str, input_bytes: bytes, answer_key: object) -> TaskInstance:
    task = TaskInstance(
        schema_version=1,
        task_id=task_id,
        family_id=GB_PRO_FAMILY.family_id,
        slice_id="gb-pro.reference" if provenance == "public_reference" else "gb-pro.held-out",
        partition=partition,  # type: ignore[arg-type]
        role_id="gb-pro-agent",
        input_digest=sha256_bytes(input_bytes),
        grader_digest=GB_PRO_GRADER_DIGEST,
        provenance=provenance,  # type: ignore[arg-type]
    )
    blinding_nonce = _REFERENCE_NONCES.get(task_id, _HELD_OUT_NONCE)
    return replace(
        task,
        answer_key_commitment=sealed_answer_key_commitment(
            family=GB_PRO_FAMILY.to_dict(),
            task=task.to_dict(),
            grader_source=GB_PRO_GRADER_SOURCE,
            answer_key=answer_key,
            blinding_nonce=blinding_nonce,
        ),
        answer_key_blinding_nonce=blinding_nonce,
    )


GB_PRO_TASK_INPUTS = {
    question.question_id: f"gb-pro-reference-input-{index}\n".encode()
    for index, question in enumerate(GB_PRO_REFERENCE_QUESTIONS, start=1)
}
GB_PRO_TASK_INPUTS["gb-pro-authored-held-out-01"] = b"gb-pro-authored-held-out-input-01\n"
GB_PRO_TASKS = tuple(
    _task(
        question.question_id,
        "untouched",
        "public_reference",
        GB_PRO_TASK_INPUTS[question.question_id],
        {"reference_number": index, "fixture": True},
    )
    for index, question in enumerate(GB_PRO_REFERENCE_QUESTIONS, start=1)
) + (
    _task(
        "gb-pro-authored-held-out-01",
        "validation",
        "held_out",
        GB_PRO_TASK_INPUTS["gb-pro-authored-held-out-01"],
        {"accepted": True, "answer": "fixture"},
    ),
)


def validate_gb_pro_family(family: BenchmarkFamily = GB_PRO_FAMILY) -> BenchmarkFamily:
    """Apply the GB-Pro profile: exactly ten unique public references."""

    validated = BenchmarkFamily.from_dict(family.to_dict())
    if len(validated.reference_questions) != 10:
        raise ValueError("GB-Pro family requires exactly 10 reference questions")
    if len({question.question_id for question in validated.reference_questions}) != 10:
        raise ValueError("GB-Pro family reference questions must be unique")
    if validated.reference_source is None:
        raise ValueError("GB-Pro family requires a pinned reference source")
    return validated
