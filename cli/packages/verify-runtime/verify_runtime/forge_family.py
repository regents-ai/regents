"""Strict Forge family contract and deterministic drift validation."""

from __future__ import annotations

from typing import Any

from .families import FAMILY_CONTRACT


class ValidationError(ValueError):
    """The supplied Forge family validation input is outside the closed contract."""


def _require_record(value: Any, path: str) -> dict[str, Any]:
    if type(value) is not dict:
        raise ValidationError(f"{path} must be an object")
    return value


def _require_exact_keys(value: dict[str, Any], expected: set[str], path: str) -> None:
    actual = set(value)
    missing = sorted(expected - actual)
    additional = sorted(actual - expected)
    if missing:
        raise ValidationError(f"{path} is missing fields: {', '.join(missing)}")
    if additional:
        raise ValidationError(f"{path} has additional fields: {', '.join(additional)}")


def _require_exact_value(value: Any, expected: Any, path: str) -> None:
    if type(value) is not type(expected) or value != expected:
        raise ValidationError(f"{path} must equal {expected!r}")


def _validate_family(value: Any) -> dict[str, Any]:
    family = _require_record(value, "family")
    _require_exact_keys(family, set(FAMILY_CONTRACT), "family")

    for field in ("schema_version", "family_id", "product_status", "kind", "executor"):
        _require_exact_value(family[field], FAMILY_CONTRACT[field], f"family.{field}")

    intervention = _require_record(family["intervention"], "family.intervention")
    expected_intervention = FAMILY_CONTRACT["intervention"]
    _require_exact_keys(intervention, set(expected_intervention), "family.intervention")
    for field, expected in expected_intervention.items():
        _require_exact_value(intervention[field], expected, f"family.intervention.{field}")

    verifier = _require_record(family["verifier"], "family.verifier")
    expected_verifier = FAMILY_CONTRACT["verifier"]
    _require_exact_keys(verifier, set(expected_verifier), "family.verifier")
    for field, expected in expected_verifier.items():
        _require_exact_value(verifier[field], expected, f"family.verifier.{field}")

    return family


def _validate_snapshot(value: Any, path: str) -> str:
    snapshot = _require_record(value, path)
    _require_exact_keys(snapshot, {"files"}, path)
    files = _require_record(snapshot["files"], f"{path}.files")
    _require_exact_keys(files, {"SKILL.md"}, f"{path}.files")
    digest = files["SKILL.md"]
    if type(digest) is not str or not digest:
        raise ValidationError(f"{path}.files.SKILL.md must be a non-empty string")
    return digest


def validate_family(value: Any) -> dict[str, Any]:
    """Validate the one allowed deterministic contract-drift family request."""

    request = _require_record(value, "input")
    _require_exact_keys(request, {"family", "baseline", "candidate"}, "input")
    family = _validate_family(request["family"])
    baseline_digest = _validate_snapshot(request["baseline"], "baseline")
    candidate_digest = _validate_snapshot(request["candidate"], "candidate")

    if baseline_digest == candidate_digest:
        raise ValidationError("baseline and candidate must differ in SKILL.md")

    return {
        "schema_version": 1,
        "valid": True,
        "family_id": family["family_id"],
        "changed_files": ["SKILL.md"],
    }
