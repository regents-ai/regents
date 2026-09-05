from __future__ import annotations

import ast
import json
from dataclasses import replace
from pathlib import Path

import pytest

from verify_runtime.capsule import declared_capsule, resolve_capsule
from verify_runtime.families import BASELINE_SKILL, CANDIDATE_SKILL, FAMILY, ROLES, SLICES, TASKS
from verify_runtime.model import (
    BenchmarkRole,
    BenchmarkSlice,
    Capsule,
    EnvironmentFamily,
    EvaluationProtocol,
    ModelValidationError,
    TaskInstance,
    canonical_json_bytes,
)
from verify_runtime.protocol import lock_builtin_protocol
import verify_runtime.protocol.lock as protocol_lock
from verify_runtime.runner import FixtureExecutor


def test_canonical_records_round_trip_as_stable_json() -> None:
    identity = FixtureExecutor().resolve_identity()
    baseline = resolve_capsule(declared_capsule("builtin://baseline/SKILL.md", executor="fixture"), BASELINE_SKILL, identity=identity)
    candidate = resolve_capsule(declared_capsule("builtin://candidate/SKILL.md", executor="fixture"), CANDIDATE_SKILL, identity=identity)
    protocol = lock_builtin_protocol(baseline, candidate)
    records = [
        (EnvironmentFamily, FAMILY.to_dict()),
        *[(BenchmarkRole, role.to_dict()) for role in ROLES],
        *[(BenchmarkSlice, benchmark_slice.to_dict()) for benchmark_slice in SLICES],
        *[(TaskInstance, task.to_dict()) for task in TASKS],
        (Capsule, baseline.to_dict()),
        (EvaluationProtocol, protocol.to_dict()),
    ]
    for record_type, value in records:
        round_tripped = record_type.from_dict(json.loads(canonical_json_bytes(value)))
        assert round_tripped.to_dict() == value
        assert canonical_json_bytes(round_tripped.to_dict()) == canonical_json_bytes(value)


def test_canonical_records_reject_unknown_fields() -> None:
    value = FAMILY.to_dict() | {"provider_payload": {}}
    with pytest.raises(ModelValidationError, match="additional fields"):
        EnvironmentFamily.from_dict(value)

    unsupported_version = FAMILY.to_dict() | {"schema_version": 2}
    with pytest.raises(ModelValidationError, match="must equal 1"):
        EnvironmentFamily.from_dict(unsupported_version)


@pytest.mark.parametrize(
    ("field", "value", "message"),
    (
        ("input_digest", "not-a-sha256-digest", "task.input_digest must be a lowercase SHA-256 digest"),
        ("grader_digest", "F" * 64, "task.grader_digest must be a lowercase SHA-256 digest"),
        ("task_id", " whitespace ", "task.task_id must be trimmed"),
        ("role_id", "role\x00id", "task.role_id must contain only printable characters"),
    ),
)
def test_protocol_lock_rejects_malformed_task_identity(monkeypatch, field: str, value: str, message: str) -> None:
    identity = FixtureExecutor().resolve_identity()
    baseline = resolve_capsule(
        declared_capsule("builtin://baseline/SKILL.md", executor="fixture"),
        BASELINE_SKILL,
        identity=identity,
    )
    candidate = resolve_capsule(
        declared_capsule("builtin://candidate/SKILL.md", executor="fixture"),
        CANDIDATE_SKILL,
        identity=identity,
    )
    malformed = replace(TASKS[0], **{field: value})
    monkeypatch.setattr(protocol_lock, "TASKS", (malformed, *TASKS[1:]))

    with pytest.raises(ModelValidationError, match=message):
        lock_builtin_protocol(baseline, candidate)


def test_model_layer_imports_neither_runner_nor_adapters() -> None:
    model_directory = Path(__file__).parents[1] / "verify_runtime" / "model"
    forbidden = ("verify_runtime.runner", "verify_runtime.adapters")
    for source_path in model_directory.glob("*.py"):
        tree = ast.parse(source_path.read_text("utf-8"), filename=str(source_path))
        imports = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imports.extend(alias.name for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imports.append(node.module)
        assert not any(name.startswith(forbidden) for name in imports), source_path


@pytest.mark.parametrize("orders", ([0, 0], [0, 2]))
def test_protocol_rejects_duplicate_or_noncanonical_matched_order(orders: list[int]) -> None:
    identity = FixtureExecutor().resolve_identity()
    baseline = resolve_capsule(declared_capsule("builtin://baseline/SKILL.md", executor="fixture"), BASELINE_SKILL, identity=identity)
    candidate = resolve_capsule(declared_capsule("builtin://candidate/SKILL.md", executor="fixture"), CANDIDATE_SKILL, identity=identity)
    record = lock_builtin_protocol(baseline, candidate).to_dict()
    record["matched_selections"] = [dict(selection) for selection in record["matched_selections"]]
    record["matched_selections"][0]["matched_order"] = orders[0]
    record["matched_selections"][1]["matched_order"] = orders[1]
    with pytest.raises(ValueError, match="matched_order positions must be canonical"):
        EvaluationProtocol.from_dict(record)
