from __future__ import annotations

from copy import deepcopy

import pytest

from verify_runtime import FAMILY_CONTRACT, ValidationError, validate_family


def valid_input() -> dict[str, object]:
    return {
        "family": deepcopy(FAMILY_CONTRACT),
        "baseline": {"files": {"SKILL.md": "baseline"}},
        "candidate": {"files": {"SKILL.md": "candidate"}},
    }


def test_accepts_exact_skill_only_contract_drift() -> None:
    assert validate_family(valid_input()) == {
        "schema_version": 1,
        "valid": True,
        "family_id": "techtree.contract-drift-repair.v1",
        "changed_files": ["SKILL.md"],
    }


@pytest.mark.parametrize(
    ("path", "value"),
    [
        (("family", "schema_version"), "1"),
        (("family", "family_id"), "provider.family.v1"),
        (("family", "product_status"), "live"),
        (("family", "kind"), "optimization"),
        (("family", "executor"), "alternate"),
        (("family", "intervention", "artifact"), "prompt.md"),
        (("family", "intervention", "changed_file_count"), 2),
        (("family", "verifier", "protocol"), "provider_protocol"),
        (("family", "verifier", "protocol_version"), "1"),
    ],
)
def test_rejects_alternate_or_differently_typed_contract_fields(
    path: tuple[str, ...], value: object
) -> None:
    payload = valid_input()
    target = payload
    for key in path[:-1]:
        target = target[key]  # type: ignore[index,assignment]
    target[path[-1]] = value  # type: ignore[index]

    with pytest.raises(ValidationError):
        validate_family(payload)


@pytest.mark.parametrize("field", list(FAMILY_CONTRACT))
def test_rejects_missing_family_fields(field: str) -> None:
    payload = valid_input()
    del payload["family"][field]  # type: ignore[index]

    with pytest.raises(ValidationError, match="missing fields"):
        validate_family(payload)


def test_rejects_additional_fields_at_every_record_boundary() -> None:
    mutations = [
        lambda value: value.update({"extra": True}),
        lambda value: value["family"].update({"extra": True}),
        lambda value: value["family"]["intervention"].update({"extra": True}),
        lambda value: value["family"]["verifier"].update({"extra": True}),
        lambda value: value["baseline"].update({"extra": True}),
        lambda value: value["candidate"]["files"].update({"README.md": "same"}),
    ]

    for mutate in mutations:
        payload = valid_input()
        mutate(payload)
        with pytest.raises(ValidationError, match="additional fields"):
            validate_family(payload)


def test_rejects_unchanged_skill() -> None:
    payload = valid_input()
    payload["candidate"] = {"files": {"SKILL.md": "baseline"}}

    with pytest.raises(ValidationError, match="must differ"):
        validate_family(payload)


@pytest.mark.parametrize(
    "files",
    [
        {},
        {"README.md": "candidate"},
        {"SKILL.md": "candidate", "README.md": "candidate"},
        {"SKILL.md": 1},
    ],
)
def test_rejects_missing_non_skill_multifile_and_wrongly_typed_interventions(
    files: dict[str, object]
) -> None:
    payload = valid_input()
    payload["candidate"] = {"files": files}

    with pytest.raises(ValidationError):
        validate_family(payload)
