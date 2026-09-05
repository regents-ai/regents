from __future__ import annotations

import importlib
import importlib.util
import secrets
from dataclasses import fields, replace
from typing import Any

import pytest

import verify_runtime.model as public_model
import verify_runtime.protocol.lock as protocol_lock
from verify_runtime.adapters.prime import package_taskset
from verify_runtime.capsule import declared_capsule, resolve_capsule
from verify_runtime.families import (
    BASELINE_SKILL,
    CANDIDATE_SKILL,
    GB_PRO_FAMILY,
    GB_PRO_GRADER_SOURCE,
    GB_PRO_HELD_OUT_SOURCE,
    GB_PRO_REFERENCE_DATA,
    GB_PRO_REFERENCE_SOURCE,
    GB_PRO_TASKS,
    GB_PRO_TASKSET_PACKAGE,
    validate_gb_pro_family,
)
from verify_runtime.model import (
    AuthoredQuestion,
    BenchmarkFamily,
    content_id,
    MatchedSelection,
    ModelValidationError,
    TaskInstance,
    SeasonManifest,
    TasksetPackageReference,
    VerifiersPin,
    canonical_json_bytes,
    load_digest_pinned_source,
    new_answer_key_blinding_nonce,
    sealed_answer_key_commitment,
    sha256_bytes,
    strict_json_loads,
    verify_sealed_answer_key_commitment,
)
from verify_runtime.protocol import lock_benchmark_protocol
from verify_runtime.runner import FixtureExecutor


DATASET_COMMIT = "c" * 40
PUBLISHER_IDENTITY = "agent://regent/forge-author-01"


def _capsules():
    identity = FixtureExecutor().resolve_identity()
    return (
        resolve_capsule(
            declared_capsule("builtin://baseline/SKILL.md", executor="fixture"),
            BASELINE_SKILL,
            identity=identity,
        ),
        resolve_capsule(
            declared_capsule("builtin://candidate/SKILL.md", executor="fixture"),
            CANDIDATE_SKILL,
            identity=identity,
        ),
    )


def _authored_draft(
    task: TaskInstance = GB_PRO_TASKS[-1],
    *,
    answer_key: object | None = None,
    author_identity: str = PUBLISHER_IDENTITY,
) -> AuthoredQuestion:
    return AuthoredQuestion.create(
        task_input_digest=task.input_digest,
        author_identity=author_identity,
        pinned_data_revision=f"huggingface://datasets/regent-gb-pro@{DATASET_COMMIT}",
        deterministic_answer_key=answer_key if answer_key is not None else {"answer": [1, True]},
    )


def _authored_record(
    task: TaskInstance = GB_PRO_TASKS[-1],
    *,
    answer_key: object | None = None,
    author_identity: str = PUBLISHER_IDENTITY,
) -> dict[str, Any]:
    return replace(
        _authored_draft(task, answer_key=answer_key, author_identity=author_identity),
        acceptance_decision="accepted",
    ).to_dict()


def _lock_with_verified_records(
    baseline,
    candidate,
    *,
    authored_records: tuple[dict[str, Any], ...],
    **kwargs,
):
    return lock_benchmark_protocol(
        baseline,
        candidate,
        authored_records=authored_records,
        **kwargs,
    )


def _public_scalars(value: Any, path: str = "") -> dict[str, Any]:
    if type(value) is dict:
        return {
            item_path: scalar
            for key, item in value.items()
            for item_path, scalar in _public_scalars(item, f"{path}.{key}" if path else key).items()
        }
    if type(value) in {list, tuple}:
        return {
            item_path: scalar
            for index, item in enumerate(value)
            for item_path, scalar in _public_scalars(item, f"{path}[{index}]").items()
        }
    return {path: value}


def _protocol_publication_bindings(protocol) -> tuple[dict[str, Any], ...]:
    settings = dict(protocol.harness_settings)
    context = strict_json_loads(settings["publication_context"].encode("utf-8"))
    assert context["profile"] == "default"
    return tuple(context["publication_bindings"])


def _with_binding_commitment(protocol, commitment: str):
    context = strict_json_loads(dict(protocol.harness_settings)["publication_context"].encode("utf-8"))
    context["publication_bindings"][-1]["answer_key_commitment"] = commitment
    updated = replace(
        protocol,
        protocol_id="pending",
        harness_settings=(("publication_context", canonical_json_bytes(context).decode("utf-8")),),
    )
    return replace(updated, protocol_id=updated.expected_protocol_id())


def _authoritative_binding(
    record: dict[str, Any],
    task: TaskInstance,
    commitment: str,
    publication_reference: str = "local-development://publications/gb-pro-authored-held-out-01",
) -> dict[str, Any]:
    question = AuthoredQuestion.from_dict(record)
    return {
        "publication_reference": publication_reference,
        "question_id": question.question_id,
        "publisher_identity": question.author_identity,
        "dataset_revision": question.pinned_data_revision,
        "task_id": task.task_id,
        "task_input_digest": task.input_digest,
        "answer_key_commitment": commitment,
    }


def _external_publication_verifies(protocol, package, authoritative_binding: dict[str, Any]) -> bool:
    sealed_packet = strict_json_loads(package.sealed_verifier_packet)
    family = sealed_packet["family"]
    task = sealed_packet["task"]
    grader_source = sealed_packet["grader"]["content"].encode("utf-8")
    answer_key = sealed_packet["answer_key"]
    blinding_nonce = bytes.fromhex(sealed_packet["blinding_nonce"])
    derived_commitment = sealed_answer_key_commitment(
        family=family,
        task=task,
        grader_source=grader_source,
        answer_key=answer_key,
        blinding_nonce=blinding_nonce,
    )
    matching_selections = tuple(
        selection
        for selection in protocol.selections
        if selection.task_id == task["task_id"] and selection.partition == task["partition"]
    )
    return (
        len(matching_selections) == 1
        and derived_commitment == authoritative_binding["answer_key_commitment"]
        and matching_selections[0].answer_key_commitment == derived_commitment
    )


def _season(family: BenchmarkFamily = GB_PRO_FAMILY, baseline=None) -> SeasonManifest:
    if baseline is None:
        baseline, _ = _capsules()
    return SeasonManifest.create(
        family=family,
        verifiers=VerifiersPin("v1", "0.2.1", "e" * 40, "trace-v1"),
        benchmark_public_name="Gene Bench Pro",
        benchmark_category="computational-biology",
        capsule_template=baseline.declared,
    )


def test_gb_pro_family_is_pinned_without_embedded_task_shapes() -> None:
    family = validate_gb_pro_family()
    record = family.to_dict()

    assert len(family.reference_questions) == 10
    assert len({question.question_id for question in family.reference_questions}) == 10
    assert record["taskset_package"] == GB_PRO_TASKSET_PACKAGE.to_dict()
    assert set(record["taskset_package"]) == {"schema_version", "package", "version", "content_hash"}
    assert "tasks" not in record
    assert family.family_id == family.expected_family_id()
    assert type(GB_PRO_REFERENCE_SOURCE.revision) is str
    assert type(GB_PRO_HELD_OUT_SOURCE.revision) is str

    assert type(family).from_dict(record).to_dict() == record
    tampered = {**record, "reference_questions": [dict(item) for item in record["reference_questions"]]}
    tampered["reference_questions"][0]["answer_key_commitment"] = "0" * 64
    with pytest.raises(ModelValidationError, match="family_id does not match"):
        type(family).from_dict(tampered)


def test_external_sources_and_taskset_package_refuse_digest_mismatches() -> None:
    assert load_digest_pinned_source(GB_PRO_REFERENCE_SOURCE, GB_PRO_REFERENCE_DATA) == GB_PRO_REFERENCE_DATA
    with pytest.raises(ModelValidationError, match="external source content digest mismatch"):
        load_digest_pinned_source(GB_PRO_REFERENCE_SOURCE, b"different-source\n")

    package_content = b"verifiers-v1-taskset-package-fixture\n"
    package = TasksetPackageReference(1, "verifiers.v1.taskset.fixture", "1", sha256_bytes(package_content))
    assert package.verify_content(package_content) == package_content
    with pytest.raises(ModelValidationError, match="taskset package content hash mismatch"):
        package.verify_content(b"different-package\n")


def test_authored_question_has_only_the_four_business_fields_and_canonical_identity() -> None:
    question = _authored_draft(answer_key={"answer": [1, True], "sentinel": "SEALED-ANSWER"})
    record = question.to_dict()
    assert set(record) == {
        "schema_version",
        "question_id",
        "task_input_digest",
        "author_identity",
        "pinned_data_revision",
        "deterministic_answer_key",
        "acceptance_decision",
    }
    assert type(question).from_dict(record).to_dict() == record
    assert set(question.identity_content()) == {
        "task_input_digest",
        "author_identity",
        "pinned_data_revision",
    }
    assert "SEALED-ANSWER" not in canonical_json_bytes(question.public_dict(answer_key_commitment="0" * 64)).decode()

    for field, value in (
        ("author_identity", "agent://regent/forge-author-02"),
        ("pinned_data_revision", f"huggingface://datasets/regent-gb-pro@{'d' * 40}"),
        ("task_input_digest", sha256_bytes(b"different-question-input\n")),
    ):
        assert replace(question, **{field: value}).expected_question_id() != question.question_id
    for field, value in (
        ("deterministic_answer_key", {"answer": [2, False]}),
        ("acceptance_decision", "rejected"),
    ):
        assert replace(question, **{field: value}).expected_question_id() == question.question_id

    tampered = record | {"author_identity": "agent://regent/forge-author-02"}
    with pytest.raises(ModelValidationError, match="canonical question content"):
        AuthoredQuestion.from_dict(tampered)
    with pytest.raises(ModelValidationError, match="immutable HuggingFace dataset locator"):
        AuthoredQuestion.create(
            task_input_digest=question.task_input_digest,
            author_identity=question.author_identity,
            pinned_data_revision="huggingface://datasets/regent-gb-pro@main",
            deterministic_answer_key=question.deterministic_answer_key,
        )
    with pytest.raises(TypeError):
        AuthoredQuestion.create(  # type: ignore[call-arg]
            task_input_digest=question.task_input_digest,
            author_identity=question.author_identity,
            pinned_data_revision=f"huggingface://datasets/regent-gb-pro@{DATASET_COMMIT}",
            deterministic_answer_key=question.deterministic_answer_key,
            acceptance_decision="accepted",
        )


def test_sealed_answer_key_is_not_agent_visible_and_is_not_a_raw_key_digest() -> None:
    sentinel = "SEALED-ANSWER-KEY-SENTINEL"
    task = GB_PRO_TASKS[-1]
    assert task.answer_key_blinding_nonce is not None
    commitment = sealed_answer_key_commitment(
        family=GB_PRO_FAMILY.to_dict(),
        task=task.to_dict(),
        grader_source=GB_PRO_GRADER_SOURCE,
        answer_key=sentinel,
        blinding_nonce=task.answer_key_blinding_nonce,
    )
    assert commitment != sha256_bytes(sentinel.encode())
    sentinel_record = replace(
        _authored_draft(answer_key=sentinel),
        acceptance_decision="accepted",
    ).to_dict()

    package = package_taskset(
        family=GB_PRO_FAMILY,  # type: ignore[arg-type]
        selection=MatchedSelection(task.task_id, task.partition, 0, task.provenance, commitment),
        task=task,
        side="candidate",
        skill_bytes=CANDIDATE_SKILL,
        task_input=b"gb-pro-authored-held-out-input-01\n",
        grader_source=GB_PRO_GRADER_SOURCE,
        max_spend_usd_cents=1_000,
        answer_key=sentinel,
        blinding_nonce=task.answer_key_blinding_nonce,
        publication_binding=_authoritative_binding(
            sentinel_record,
            task,
            commitment,
            "local-development://publications/sealed-sentinel",
        ),
    )
    assert sentinel.encode() not in canonical_json_bytes(package.agent_taskset)
    assert sentinel.encode() in package.sealed_verifier_packet
    assert task.answer_key_blinding_nonce.hex().encode() in package.sealed_verifier_packet


def test_every_public_sealed_question_field_defeats_three_guess_enumeration() -> None:
    task = GB_PRO_TASKS[-1]
    guesses = (
        {"accepted": True, "answer": "first"},
        {"accepted": True, "answer": "fixture"},
        {"accepted": True, "answer": "third"},
    )
    answer = guesses[1]
    assert task.answer_key_blinding_nonce is not None
    nonce_a = task.answer_key_blinding_nonce
    nonce_b = secrets.token_bytes(32)
    question = replace(_authored_draft(answer_key=answer), acceptance_decision="accepted")
    commitment = question.answer_key_commitment(
        family=GB_PRO_FAMILY.to_dict(),
        task=task.to_dict(),
        grader_source=GB_PRO_GRADER_SOURCE,
        blinding_nonce=nonce_a,
    )
    second_commitment = question.answer_key_commitment(
        family=GB_PRO_FAMILY.to_dict(),
        task=task.to_dict(),
        grader_source=GB_PRO_GRADER_SOURCE,
        blinding_nonce=nonce_b,
    )
    assert commitment != second_commitment
    assert commitment == task.answer_key_commitment

    baseline, candidate = _capsules()
    authored_record = question.to_dict()
    protocol = _lock_with_verified_records(
        baseline,
        candidate,
        family=GB_PRO_FAMILY,
        season=_season(baseline=baseline),
        tasks=GB_PRO_TASKS,
        authored_records=(authored_record,),
    )

    def public_surfaces(
        authored_question: AuthoredQuestion,
        answer_key_commitment: str,
        locked_protocol,
        blinding_nonce: bytes,
    ) -> dict[str, Any]:
        selection = locked_protocol.selections[-1]
        publication_binding = _protocol_publication_bindings(locked_protocol)[-1]
        package = package_taskset(
            family=GB_PRO_FAMILY,  # type: ignore[arg-type]
            selection=selection,
            task=task,
            side="candidate",
            skill_bytes=CANDIDATE_SKILL,
            task_input=b"gb-pro-authored-held-out-input-01\n",
            grader_source=GB_PRO_GRADER_SOURCE,
            max_spend_usd_cents=1_000,
            answer_key=authored_question.deterministic_answer_key,
            blinding_nonce=blinding_nonce,
            publication_binding=publication_binding,
        )
        protocol_record = locked_protocol.to_dict()
        return {
            "authored_projection": replace(
                authored_question,
                acceptance_decision="accepted",
            ).public_dict(answer_key_commitment=answer_key_commitment),
            "task_record": task.to_dict(),
            "agent_taskset": package.agent_taskset,
            "protocol": protocol_record,
            "derived_receipt_and_digests": {
                "agent_taskset_digest": sha256_bytes(canonical_json_bytes(package.agent_taskset)),
                "protocol_digest": sha256_bytes(canonical_json_bytes(protocol_record)),
                "receipt_id": content_id(
                    "receipt",
                    {"protocol_id": locked_protocol.protocol_id, "task_id": task.task_id},
                ),
            },
        }

    actual_scalars = _public_scalars(public_surfaces(question, commitment, protocol, nonce_a))
    assert len(actual_scalars) == 147
    assert {
        surface: len(_public_scalars(value))
        for surface, value in public_surfaces(question, commitment, protocol, nonce_a).items()
    } == {
        "authored_projection": 4,
        "task_record": 9,
        "agent_taskset": 22,
        "protocol": 109,
        "derived_receipt_and_digests": 3,
    }

    guessed_scalar_records = []
    for guess in guesses:
        guessed_question = replace(_authored_draft(answer_key=guess), acceptance_decision="accepted")
        guessed_commitment = guessed_question.answer_key_commitment(
            family=GB_PRO_FAMILY.to_dict(),
            task=task.to_dict(),
            grader_source=GB_PRO_GRADER_SOURCE,
            blinding_nonce=bytes(32),
        )
        guessed_selections = (
            *protocol.selections[:-1],
            replace(protocol.selections[-1], answer_key_commitment=guessed_commitment),
        )
        guessed_protocol = replace(protocol, protocol_id="pending", selections=guessed_selections)
        guessed_protocol = _with_binding_commitment(guessed_protocol, guessed_commitment)
        guessed_scalar_records.append(
            _public_scalars(
                public_surfaces(
                    guessed_question,
                    guessed_commitment,
                    guessed_protocol,
                    bytes(32),
                )
            )
        )
        assert not verify_sealed_answer_key_commitment(
            commitment=commitment,
            family=GB_PRO_FAMILY.to_dict(),
            task=task.to_dict(),
            grader_source=GB_PRO_GRADER_SOURCE,
            answer_key=guess,
            blinding_nonce=bytes(32),
        )

    # Sweep every public scalar across all five answer-bearing downstream
    # surfaces.  Each is answer-independent (all guesses match) or blinded
    # (none match); no scalar singles out the correct low-entropy answer.
    for field_path, field_value in actual_scalars.items():
        matches = tuple(candidate[field_path] == field_value for candidate in guessed_scalar_records)
        assert matches in {(True, True, True), (False, False, False)}, field_path


def test_benchmark_lock_derives_calibration_and_scored_sets_from_provenance() -> None:
    baseline, candidate = _capsules()
    authored_record = _authored_record(
        GB_PRO_TASKS[-1],
        answer_key={"accepted": True, "answer": "fixture"},
    )
    protocol = _lock_with_verified_records(
        baseline,
        candidate,
        family=GB_PRO_FAMILY,
        season=_season(baseline=baseline),
        tasks=GB_PRO_TASKS,
        authored_records=(authored_record,),
    )

    assert len(protocol.calibration_task_ids) == 10
    assert len(protocol.scored_task_ids) == 1
    assert all(selection.provenance == "public_reference" for selection in protocol.selections[:10])
    assert protocol.selections[-1].provenance == "held_out"
    assert protocol.challenge_revision_id == GB_PRO_FAMILY.challenge_contract.challenge_revision_id
    assert protocol.season_id == _season(baseline=baseline).season_id
    assert protocol.decision_rule == GB_PRO_FAMILY.challenge_contract.decision_rule
    assert protocol.taskset_version == GB_PRO_TASKSET_PACKAGE
    assert all("SEALED-ANSWER" not in canonical_json_bytes(value).decode() for value in (protocol.to_dict(),))

    fabricated = protocol.to_dict()
    fabricated["partitions"] = {**fabricated["partitions"], "validation": list(fabricated["partitions"]["untouched"])}
    with pytest.raises(ModelValidationError, match="protocol (partitions must contain unique|matched selections must equal)"):
        type(protocol).from_dict(fabricated)

    relabeled = replace(GB_PRO_TASKS[0], provenance="held_out")
    with pytest.raises(ModelValidationError, match="input digest matches a pinned public reference"):
        _lock_with_verified_records(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=_season(baseline=baseline),
            tasks=(relabeled, *GB_PRO_TASKS[1:]),
            authored_records=(authored_record,),
        )

    wrong_commitment = replace(GB_PRO_TASKS[0], answer_key_commitment="0" * 64)
    with pytest.raises(ModelValidationError, match="does not match the family"):
        _lock_with_verified_records(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=_season(baseline=baseline),
            tasks=(wrong_commitment, *GB_PRO_TASKS[1:]),
            authored_records=(authored_record,),
        )

    held_out = GB_PRO_TASKS[-1]
    assert held_out.answer_key_blinding_nonce is not None
    attacker_commitment = sealed_answer_key_commitment(
        family=GB_PRO_FAMILY.to_dict(),
        task=held_out.to_dict(),
        grader_source=GB_PRO_GRADER_SOURCE,
        answer_key={"accepted": True, "answer": "attacker-controls-score"},
        blinding_nonce=held_out.answer_key_blinding_nonce,
    )
    attacker_scoring_task = replace(held_out, answer_key_commitment=attacker_commitment)
    with pytest.raises(ModelValidationError, match="held_out_answer_commitment_mismatch"):
        lock_benchmark_protocol(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=_season(baseline=baseline),
            tasks=(*GB_PRO_TASKS[:-1], attacker_scoring_task),
            authored_records=(authored_record,),
        )

    pending = _authored_draft(GB_PRO_TASKS[-1], answer_key={"accepted": True, "answer": "not-published"})
    with pytest.raises(ModelValidationError, match="authored_question_validation_pending"):
        lock_benchmark_protocol(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=_season(baseline=baseline),
            tasks=GB_PRO_TASKS,
            authored_records=(pending.to_dict(),),
        )


def test_lock_rejects_reference_content_alias_and_missing_or_forged_authorship(monkeypatch) -> None:
    baseline, candidate = _capsules()
    season = _season(baseline=baseline)
    authored_record = _authored_record(
        GB_PRO_TASKS[-1],
        answer_key={"accepted": True, "answer": "fixture"},
    )

    aliased_reference = replace(GB_PRO_TASKS[0], task_id="attacker-renamed-reference", provenance="held_out")
    with pytest.raises(ModelValidationError, match="input digest matches a pinned public reference"):
        _lock_with_verified_records(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=season,
            tasks=(aliased_reference, *GB_PRO_TASKS[1:]),
            authored_records=(authored_record,),
        )

    with pytest.raises(ModelValidationError, match="every held_out task requires"):
        lock_benchmark_protocol(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=season,
            tasks=GB_PRO_TASKS,
        )

    assert [field.name for field in fields(AuthoredQuestion)] == [
        "schema_version",
        "question_id",
        "task_input_digest",
        "author_identity",
        "pinned_data_revision",
        "deterministic_answer_key",
        "acceptance_decision",
    ]
    assert not hasattr(public_model, "PublisherStamp")
    assert not hasattr(public_model, "validate_authored_question")
    assert importlib.util.find_spec("verify_runtime._publication") is None
    with pytest.raises(ModuleNotFoundError):
        importlib.import_module("verify_runtime._publication")

    forged = AuthoredQuestion(
        schema_version=1,
        question_id="pending",
        task_input_digest=GB_PRO_TASKS[-1].input_digest,
        author_identity="agent://attacker/forged-author",
        pinned_data_revision=f"huggingface://datasets/attacker/forged@{'f' * 40}",
        deterministic_answer_key={"answer": "attacker-selected"},
        acceptance_decision="accepted",
    )
    forged = replace(forged, question_id=forged.expected_question_id())

    # The reviewer's exact trust-flag constructor attack no longer constructs.
    with pytest.raises(TypeError):
        AuthoredQuestion(  # type: ignore[call-arg]
            **forged.to_dict(),
            _publisher_stamped=True,
            _validator_accepted=True,
            _validator_record_digest=sha256_bytes(canonical_json_bytes(forged.to_dict())),
        )

    class LegacyPublication:
        __slots__ = ("question", "publisher_identity")

        def __init__(self, question, publisher_identity) -> None:
            self.question = question
            self.publisher_identity = publisher_identity

    class SubclassForgery(LegacyPublication):
        pass

    helper_forgery = LegacyPublication(forged, forged.author_identity)
    subclass_forgery = SubclassForgery(forged, forged.author_identity)
    slot_forgery = object.__new__(LegacyPublication)
    object.__setattr__(slot_forgery, "question", forged)
    object.__setattr__(slot_forgery, "publisher_identity", forged.author_identity)

    # The verifier's exact three wrapper attacks are now inert: lock accepts
    # raw dictionaries only and never branches on wrapper type or attributes.
    for wrapper_forgery in (helper_forgery, subclass_forgery, slot_forgery):
        with pytest.raises(ModelValidationError, match="must be an object"):
            lock_benchmark_protocol(
                baseline,
                candidate,
                family=GB_PRO_FAMILY,
                season=season,
                tasks=GB_PRO_TASKS,
                authored_records=(wrapper_forgery,),  # type: ignore[arg-type]
            )

    public_constructor_results = (
        forged,
        forged.to_dict(),
        AuthoredQuestion.from_dict(forged.to_dict()).to_dict(),
        replace(_authored_draft(), acceptance_decision="accepted").to_dict(),
    )
    for caller_supplied_acceptance in public_constructor_results:
        with pytest.raises(ModelValidationError, match="(must be an object|absent from local development publication context)"):
            lock_benchmark_protocol(
                baseline,
                candidate,
                family=GB_PRO_FAMILY,
                season=season,
                tasks=GB_PRO_TASKS,
                authored_records=(caller_supplied_acceptance,),  # type: ignore[arg-type]
            )

    rejected_record = authored_record | {"acceptance_decision": "rejected"}
    with pytest.raises(ModelValidationError, match="authored_question_validation_rejected"):
        lock_benchmark_protocol(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=season,
            tasks=GB_PRO_TASKS,
            authored_records=(rejected_record,),
        )

    # The local development publication context admits its exact fixture, but
    # makes no in-process authenticity claim.
    locked = _lock_with_verified_records(
        baseline,
        candidate,
        family=GB_PRO_FAMILY,
        season=season,
        tasks=GB_PRO_TASKS,
        authored_records=(authored_record,),
    )
    assert locked.scored_task_ids == (GB_PRO_TASKS[-1].task_id,)
    authoritative_binding = _authoritative_binding(
        authored_record,
        GB_PRO_TASKS[-1],
        GB_PRO_TASKS[-1].answer_key_commitment,
    )
    genuine_package = package_taskset(
        family=GB_PRO_FAMILY,  # type: ignore[arg-type]
        selection=locked.selections[-1],
        task=GB_PRO_TASKS[-1],
        side="candidate",
        skill_bytes=CANDIDATE_SKILL,
        task_input=b"gb-pro-authored-held-out-input-01\n",
        grader_source=GB_PRO_GRADER_SOURCE,
        max_spend_usd_cents=1_000,
        answer_key={"accepted": True, "answer": "fixture"},
        blinding_nonce=GB_PRO_TASKS[-1].answer_key_blinding_nonce,
        publication_binding=_protocol_publication_bindings(locked)[-1],
    )
    assert _external_publication_verifies(locked, genuine_package, authoritative_binding)

    # The external check derives evidence from the packet itself. Copying both
    # genuine publication-binding dictionaries into a package with an
    # attacker-controlled sealed answer cannot satisfy the authoritative
    # commitment, even when the protocol selection carries the attacker value.
    spoofed_packet = strict_json_loads(genuine_package.sealed_verifier_packet)
    spoofed_packet["answer_key"] = {"accepted": True, "answer": "attacker-controls-score"}
    spoofed_commitment = sealed_answer_key_commitment(
        family=spoofed_packet["family"],
        task=spoofed_packet["task"],
        grader_source=spoofed_packet["grader"]["content"].encode("utf-8"),
        answer_key=spoofed_packet["answer_key"],
        blinding_nonce=bytes.fromhex(spoofed_packet["blinding_nonce"]),
    )
    spoofed_protocol = replace(
        locked,
        protocol_id="pending",
        selections=(
            *locked.selections[:-1],
            replace(locked.selections[-1], answer_key_commitment=spoofed_commitment),
        ),
    )
    spoofed_protocol = replace(spoofed_protocol, protocol_id=spoofed_protocol.expected_protocol_id())
    spoofed_package = replace(
        genuine_package,
        sealed_verifier_packet=canonical_json_bytes(spoofed_packet),
    )
    assert _protocol_publication_bindings(spoofed_protocol) == (authoritative_binding,)
    assert spoofed_packet["publication_binding"] == authoritative_binding
    assert spoofed_packet["answer_key"]["answer"] == "attacker-controls-score"
    assert spoofed_protocol.selections[-1].answer_key_commitment != authoritative_binding["answer_key_commitment"]
    assert not _external_publication_verifies(spoofed_protocol, spoofed_package, authoritative_binding)

    with pytest.raises(ValueError, match="requires a publication binding"):
        package_taskset(
            family=GB_PRO_FAMILY,  # type: ignore[arg-type]
            selection=locked.selections[-1],
            task=GB_PRO_TASKS[-1],
            side="candidate",
            skill_bytes=CANDIDATE_SKILL,
            task_input=b"gb-pro-authored-held-out-input-01\n",
            grader_source=GB_PRO_GRADER_SOURCE,
            max_spend_usd_cents=1_000,
            answer_key={"accepted": True, "answer": "fixture"},
            blinding_nonce=GB_PRO_TASKS[-1].answer_key_blinding_nonce,
        )

    task = GB_PRO_TASKS[-1]
    assert task.answer_key_blinding_nonce is not None
    forged_task_input = b"attacker-created-held-out-input\n"
    forged_task_without_commitment = replace(
        task,
        task_id="attacker-created-held-out-01",
        input_digest=sha256_bytes(forged_task_input),
        answer_key_commitment=None,
    )
    forged_answer = _authored_record(
        forged_task_without_commitment,
        answer_key={"accepted": True, "answer": "attacker-selected"},
    )
    forged_commitment = sealed_answer_key_commitment(
        family=GB_PRO_FAMILY.to_dict(),
        task=forged_task_without_commitment.to_dict(),
        grader_source=GB_PRO_GRADER_SOURCE,
        answer_key={"accepted": True, "answer": "attacker-selected"},
        blinding_nonce=task.answer_key_blinding_nonce,
    )
    forged_task = replace(forged_task_without_commitment, answer_key_commitment=forged_commitment)
    forged_tasks = (*GB_PRO_TASKS[:-1], forged_task)
    with pytest.raises(ModelValidationError, match="absent from local development publication context"):
        lock_benchmark_protocol(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=season,
            tasks=forged_tasks,
            authored_records=(forged_answer,),
        )

    def forged_package(protocol):
        return package_taskset(
            family=GB_PRO_FAMILY,  # type: ignore[arg-type]
            selection=protocol.selections[-1],
            task=forged_task,
            side="candidate",
            skill_bytes=CANDIDATE_SKILL,
            task_input=forged_task_input,
            grader_source=GB_PRO_GRADER_SOURCE,
            max_spend_usd_cents=1_000,
            answer_key={"accepted": True, "answer": "attacker-selected"},
            blinding_nonce=task.answer_key_blinding_nonce,
            publication_binding=_protocol_publication_bindings(protocol)[-1],
        )

    original_lookup = protocol_lock._publication_from_local_development_context
    monkeypatch.setattr(
        protocol_lock,
        "_publication_from_local_development_context",
        lambda _record: (
            PUBLISHER_IDENTITY,
            "local-development://publications/replaced-lookup-forgery",
        ),
    )
    lookup_forged_protocol = lock_benchmark_protocol(
        baseline,
        candidate,
        family=GB_PRO_FAMILY,
        season=season,
        tasks=forged_tasks,
        authored_records=(forged_answer,),
    )
    assert not _external_publication_verifies(
        lookup_forged_protocol,
        forged_package(lookup_forged_protocol),
        authoritative_binding,
    )
    monkeypatch.setattr(protocol_lock, "_publication_from_local_development_context", original_lookup)

    monkeypatch.setattr(
        protocol_lock,
        "_LOCAL_DEVELOPMENT_PUBLICATIONS",
        protocol_lock._LOCAL_DEVELOPMENT_PUBLICATIONS
        + (
            (
                forged_answer,
                PUBLISHER_IDENTITY,
                "local-development://publications/appended-context-forgery",
            ),
        ),
    )
    appended_forged_protocol = lock_benchmark_protocol(
        baseline,
        candidate,
        family=GB_PRO_FAMILY,
        season=season,
        tasks=forged_tasks,
        authored_records=(forged_answer,),
    )
    assert not _external_publication_verifies(
        appended_forged_protocol,
        forged_package(appended_forged_protocol),
        authoritative_binding,
    )

    wrong_publisher = _authored_record(
        GB_PRO_TASKS[-1],
        answer_key={"accepted": True, "answer": "fixture"},
        author_identity="agent://attacker/forged-author",
    )
    with pytest.raises(ModelValidationError, match="identity does not match its publication publisher"):
        lock_benchmark_protocol(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=season,
            tasks=GB_PRO_TASKS,
            authored_records=(wrong_publisher,),
        )

    invalid_revision = authored_record | {
        "pinned_data_revision": "huggingface://datasets/regent-gb-pro@main",
    }
    with pytest.raises(ModelValidationError, match="immutable HuggingFace dataset locator"):
        lock_benchmark_protocol(
            baseline,
            candidate,
            family=GB_PRO_FAMILY,
            season=season,
            tasks=GB_PRO_TASKS,
            authored_records=(invalid_revision,),
        )


def test_reusable_family_shape_allows_zero_reference_calibration() -> None:
    baseline, candidate = _capsules()
    family = BenchmarkFamily.create(
        challenge_contract=GB_PRO_FAMILY.challenge_contract,
        taskset_package=GB_PRO_TASKSET_PACKAGE,
        held_out_source=GB_PRO_HELD_OUT_SOURCE,
    )
    zero_nonce = new_answer_key_blinding_nonce()
    task = TaskInstance(
        1,
        "zero-reference-held-out-01",
        family.family_id,
        "zero-reference.held-out",
        "validation",
        "gb-pro-agent",
        sha256_bytes(b"zero-reference-input\n"),
        sha256_bytes(GB_PRO_GRADER_SOURCE),
        "held_out",
        sealed_answer_key_commitment(
            family=family.to_dict(),
            task={
                "schema_version": 1,
                "task_id": "zero-reference-held-out-01",
                "family_id": family.family_id,
                "slice_id": "zero-reference.held-out",
                "partition": "validation",
                "role_id": "gb-pro-agent",
                "input_digest": sha256_bytes(b"zero-reference-input\n"),
                "grader_digest": sha256_bytes(GB_PRO_GRADER_SOURCE),
                "provenance": "held_out",
            },
            grader_source=GB_PRO_GRADER_SOURCE,
            answer_key={"answer": "zero-reference"},
            blinding_nonce=zero_nonce,
        ),
        answer_key_blinding_nonce=zero_nonce,
    )
    authored_record = _authored_record(task, answer_key={"answer": "zero-reference"})
    protocol = _lock_with_verified_records(
        baseline,
        candidate,
        family=family,
        season=_season(family, baseline),
        tasks=(task,),
        authored_records=(authored_record,),
    )
    assert protocol.calibration_task_ids == ()
    assert protocol.scored_task_ids == (task.task_id,)


def test_season_manifest_pins_verifiers_benchmark_identity_and_three_splits() -> None:
    baseline, _ = _capsules()
    manifest = SeasonManifest.create(
        family=GB_PRO_FAMILY,
        verifiers=VerifiersPin("v1", "0.2.1", "e" * 40, "trace-v1"),
        benchmark_public_name="Gene Bench Pro",
        benchmark_category="computational-biology",
        capsule_template=baseline.declared,
    )
    record = manifest.to_dict()
    assert strict_json_loads(canonical_json_bytes(record)) == record
    assert {
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
    } == set(record)
    assert record["mutable_paths"] == ["SKILL.md"]
    assert record["capsule_template"] == baseline.declared.to_dict()
    assert record["verifiers"] == {
        "api": "v1",
        "package_version": "0.2.1",
        "git_commit": "e" * 40,
        "trace_version": "trace-v1",
    }
    assert record["splits"] == {
        "development": {"visibility": "public", "reward_bearing": False, "purpose": "development"},
        "certification": {"visibility": "hidden", "reward_bearing": True, "purpose": "certification"},
        "successor": {"visibility": "hidden", "reward_bearing": False, "purpose": "anti-overfit"},
    }
    assert SeasonManifest.from_dict(record, family=GB_PRO_FAMILY) == manifest

    tampered = {**record, "splits": {**record["splits"], "successor": {**record["splits"]["successor"], "reward_bearing": True}}}
    with pytest.raises(ModelValidationError, match="fixed three-split policy"):
        SeasonManifest.from_dict(tampered, family=GB_PRO_FAMILY)

    for invalid in (
        {**record, "verifiers": {**record["verifiers"], "api": "v2"}},
        {**record, "verifiers": {**record["verifiers"], "package_version": "latest"}},
        {**record, "verifiers": {**record["verifiers"], "git_commit": "not-a-sha"}},
        {**record, "verifiers": {**record["verifiers"], "trace_version": ""}},
    ):
        with pytest.raises(ModelValidationError):
            SeasonManifest.from_dict(invalid, family=GB_PRO_FAMILY)

    with pytest.raises(ModelValidationError):
        VerifiersPin("v2", "latest", "not-a-sha", "")
