from __future__ import annotations

from dataclasses import replace

import pytest

from verify_runtime.capsule import HOSTED_HERMES_DEFAULT, declared_capsule, resolve_capsule
from verify_runtime.families import BASELINE_SKILL, CANDIDATE_SKILL
from verify_runtime.protocol import FOUNDER_DEFAULT_POLICY, lock_builtin_protocol
from verify_runtime.runner import FixtureExecutor


def capsules():
    identity = FixtureExecutor().resolve_identity()
    return (
        resolve_capsule(declared_capsule("builtin://baseline/SKILL.md", executor="fixture"), BASELINE_SKILL, identity=identity),
        resolve_capsule(declared_capsule("builtin://candidate/SKILL.md", executor="fixture"), CANDIDATE_SKILL, identity=identity),
    )


def test_fixture_resolution_uses_pinned_fixture_identity_and_skill_content() -> None:
    baseline, candidate = capsules()
    assert baseline.declared.model == "contract-drift-fixture-v1"
    assert baseline.resolved.model_identifier == "contract-drift-fixture-v1"
    assert baseline.resolved.provider == "fixture"
    assert baseline.resolved.behavioral_fingerprint is not None
    assert baseline.resolved.model_mutability == "content-pinned"
    assert baseline.resolved.skill_mutability == "content-pinned"
    assert baseline.resolved.skill_digest != candidate.resolved.skill_digest
    assert HOSTED_HERMES_DEFAULT["declared_model"] == "current-default"


def test_founder_hosted_default_is_only_the_unspecified_declared_input() -> None:
    declared = declared_capsule("builtin://baseline/SKILL.md", executor="hermes")
    assert declared.provider == "hermes-hosted"
    assert declared.model == "current-default"


def test_locks_founder_policy_and_partitioned_matched_selection() -> None:
    protocol = lock_builtin_protocol(*capsules())
    assert protocol.policy == FOUNDER_DEFAULT_POLICY
    assert protocol.policy.attempts_per_task == 1
    assert protocol.policy.max_task_wall_seconds == 600
    assert protocol.policy.max_comparison_spend_usd_cents == 1_000
    assert protocol.development_task_ids
    assert protocol.validation_task_ids
    assert protocol.untouched_task_ids
    assert [selection.partition for selection in protocol.selections] == ["validation", *(["untouched"] * 10)]
    assert [selection.matched_order for selection in protocol.selections] == list(range(11))
    assert protocol.optimizer_method == "manual"
    assert protocol.optimizer_candidate_count == 1


def test_rejects_a_system_level_change_as_an_isolated_skill_comparison() -> None:
    baseline, candidate = capsules()
    changed_declared = replace(candidate.declared, tools=("filesystem", "browser"))
    changed_candidate = replace(candidate, declared=changed_declared)
    with pytest.raises(ValueError, match="only SKILL.md"):
        lock_builtin_protocol(baseline, changed_candidate)

    changed_resolved = replace(candidate.resolved, model_identifier="different-hosted-model")
    with pytest.raises(ValueError, match="resolved more than SKILL.md"):
        lock_builtin_protocol(baseline, replace(candidate, resolved=changed_resolved))
