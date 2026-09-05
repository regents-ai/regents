"""Deterministic built-in family used by the offline Verify operating path."""

from __future__ import annotations

from dataclasses import replace

from verify_runtime.model import (
    AuthoredQuestion,
    BenchmarkRole,
    BenchmarkSlice,
    DecisionRule,
    EnvironmentFamily,
    SevereRegressionRule,
    TaskInstance,
    TasksetPackageReference,
    new_answer_key_blinding_nonce,
    sealed_answer_key_commitment,
    sha256_bytes,
)

FAMILY = EnvironmentFamily(
    schema_version=1,
    family_id="techtree.contract-drift-repair.v1",
    product_status="planned",
    kind="deterministic_contract_drift_repair",
    executor="hermes",
    intervention_artifact="SKILL.md",
    intervention_changed_file_count=1,
    verifier_protocol="deterministic_contract_drift",
    verifier_protocol_version=1,
)
FAMILY_CONTRACT = FAMILY.to_dict()

BASELINE_SKILL = b"# Contract repair\n\nEdit every file that appears related to the failure.\n"
CANDIDATE_SKILL = b"# Contract repair\n\nChange exactly the one declared SKILL.md and preserve every other file.\n"
TASKSET_PACKAGE = TasksetPackageReference(
    schema_version=1,
    package="regent.contract-drift.v1",
    version="2",
    content_hash=sha256_bytes(b"contract-drift-taskset-package-v2\n"),
)
CHALLENGE_REVISION_ID = "contract-drift-challenge-v1"
TREATMENT_DIFF = (
    "--- a/SKILL.md\n"
    "+++ b/SKILL.md\n"
    "@@\n"
    "-Edit every file that appears related to the failure.\n"
    "+Change exactly the one declared SKILL.md and preserve every other file.\n"
)

DECISION_RULE = DecisionRule(
    primary_metric="score_millis",
    minimum_valid_task_count=1,
    positive_threshold_millis=100,
    negative_threshold_millis=-100,
    null_band_millis=0,
    severe_regression_rule=SevereRegressionRule("delta_at_or_below", 100),
    inconclusive_conditions=("valid_task_count_below_minimum", "delta_between_thresholds"),
    invalid_conditions=("any_arm_not_completed", "missing_score"),
)

ROLES = (
    BenchmarkRole(1, "repair-agent", "repair the declared contract drift", "task-input-only"),
    BenchmarkRole(1, "deterministic-grader", "check the one-file repair rule", "sealed-grader"),
)

_FAMILY_ID = FAMILY.family_id
GRADER_SOURCE = b"deterministic-contract-drift-grader-v1\n"
TASK_INPUTS = {
    "contract-drift-development-1": b"development-visible-contract-drift\n",
    "contract-drift-validation-1": b"validation-contract-drift\n",
    **{
        f"contract-drift-untouched-{index}": f"sealed-untouched-contract-drift-{index}\n".encode()
        for index in range(1, 11)
    },
}
_GRADER_DIGEST = sha256_bytes(GRADER_SOURCE)
_SEALED_NONCES = {task_id: new_answer_key_blinding_nonce() for task_id in TASK_INPUTS}


def _task(task_id: str, partition: str, provenance: str) -> TaskInstance:
    task = TaskInstance(
        1,
        task_id,
        _FAMILY_ID,
        f"{_FAMILY_ID}.{partition}",
        partition,
        "repair-agent",
        sha256_bytes(TASK_INPUTS[task_id]),
        _GRADER_DIGEST,
        provenance,
        "0" * 64,
    )  # type: ignore[arg-type]
    return replace(
        task,
        answer_key_commitment=sealed_answer_key_commitment(
            family=FAMILY.to_dict(),
            task=task.to_dict(),
            grader_source=GRADER_SOURCE,
            answer_key=None,
            blinding_nonce=_SEALED_NONCES[task_id],
        ),
        answer_key_blinding_nonce=_SEALED_NONCES[task_id],
    )


TASKS = (
    _task("contract-drift-development-1", "development", "held_out"),
    _task("contract-drift-validation-1", "validation", "held_out"),
    *(_task(f"contract-drift-untouched-{index}", "untouched", "public_reference") for index in range(1, 11)),
)

_BUILTIN_PUBLISHER_IDENTITY = "regent://builtin/contract-drift-publisher-v1"
_BUILTIN_AUTHORED_RECORDS = tuple(
    replace(
        AuthoredQuestion.create(
            task_input_digest=task.input_digest,
            author_identity=_BUILTIN_PUBLISHER_IDENTITY,
            pinned_data_revision=f"huggingface://datasets/regent-contract-drift@{'c' * 40}",
            deterministic_answer_key=None,
        ),
        acceptance_decision="accepted",
    ).to_dict()
    for task in TASKS
    if task.provenance == "held_out"
)
_BUILTIN_PUBLICATION_BINDINGS = {
    task.task_id: {
        "publication_reference": f"local-development://publications/{record['question_id']}",
        "question_id": record["question_id"],
        "publisher_identity": record["author_identity"],
        "dataset_revision": record["pinned_data_revision"],
        "task_id": task.task_id,
        "task_input_digest": task.input_digest,
        "answer_key_commitment": task.answer_key_commitment,
    }
    for task in TASKS
    for record in _BUILTIN_AUTHORED_RECORDS
    if task.provenance == "held_out" and record["task_input_digest"] == task.input_digest
}

SLICES = tuple(
    BenchmarkSlice(1, f"{_FAMILY_ID}.{partition}", _FAMILY_ID, partition, ("repair-agent", "deterministic-grader"), tuple(task.task_id for task in TASKS if task.partition == partition))  # type: ignore[arg-type]
    for partition in ("development", "validation", "untouched")
)
