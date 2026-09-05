from __future__ import annotations

from pathlib import Path

import pytest

from verify_runtime.capsule import declared_capsule, resolve_capsule
from verify_runtime.families import BASELINE_SKILL
from verify_runtime.receipts import show_receipt
from verify_runtime.runner import run_builtin_comparison
from verify_runtime.runner.executors import MAX_CAPTURE_BYTES, HermesExecutor, RuntimeResolutionError


def executable(tmp_path: Path, body: str) -> Path:
    target = tmp_path / "fake-hermes"
    target.write_text("#!/usr/bin/env python3\n" + body)
    target.chmod(0o755)
    return target


def test_hermes_resolution_interrogates_non_default_effective_model(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
import sys
arguments = sys.argv[1:]
model = arguments[arguments.index('--model') + 1]
if arguments[-1:] == ['--version']:
    print('Hermes Agent v9.9.9 (2026.8.4) · upstream abcdef1')
elif arguments[-2:] == ['config', 'show']:
    print(f"  Model:        {{'provider': 'configured-provider', 'default': '{model}'}}")
else:
    raise SystemExit(2)
""")
    identity = HermesExecutor((str(binary), "--model", "configured-model")).resolve_identity()
    assert identity.provider == "configured-provider"
    assert identity.model_identifier == "configured-model"
    assert identity.model_identifier != "current-default"
    assert identity.hermes_version == "Hermes Agent v9.9.9"
    assert identity.behavioral_fingerprint is None
    assert identity.model_mutability == "mutable-hosted"
    capsule = resolve_capsule(declared_capsule("builtin://baseline/SKILL.md"), BASELINE_SKILL, identity=identity)
    assert capsule.declared.model == "current-default"
    assert capsule.resolved.model_identifier == "configured-model"


@pytest.mark.parametrize("garbage_target", ["version", "config"])
def test_hermes_resolution_rejects_garbage_introspection(tmp_path: Path, garbage_target: str) -> None:
    binary = executable(tmp_path, """
import sys
arguments = sys.argv[1:]
target = arguments[arguments.index('--garbage') + 1]
if arguments[-1:] == ['--version']:
    print('garbage' if target == 'version' else 'Hermes Agent v9.9.9')
elif arguments[-2:] == ['config', 'show']:
    print('garbage' if target == 'config' else "  Model:        {'provider': 'configured-provider', 'default': 'configured-model'}")
""")
    with pytest.raises(RuntimeResolutionError, match="introspection"):
        HermesExecutor((str(binary), "--garbage", garbage_target)).resolve_identity()


def test_hermes_resolution_rejects_duplicate_provider_keys(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
import sys
arguments = sys.argv[1:]
if arguments[-1:] == ['--version']:
    print('Hermes Agent v9.9.9')
elif arguments[-2:] == ['config', 'show']:
    print("  Model:        {'provider': 'first', 'provider': 'second', 'default': 'configured-model'}")
""")
    with pytest.raises(RuntimeResolutionError, match="unreadable model"):
        HermesExecutor((str(binary),)).resolve_identity()


@pytest.mark.parametrize("status", ["completed", "timeout", "invalid", "agent_failure", "infrastructure_failure"])
def test_structured_terminal_status_is_authoritative_with_nonzero_exit(tmp_path: Path, status: str) -> None:
    binary = executable(tmp_path, """
import json, sys
status = sys.argv[1]
score = 100 if status == 'completed' else None
print(json.dumps({'status': status, 'score_millis': score, 'cost_usd_cents': 7, 'detail': 'structured'}))
raise SystemExit(17)
""")
    result = HermesExecutor((str(binary), status)).execute(side="baseline", task_id="task", workspace=tmp_path, timeout_seconds=5, max_spend_usd_cents=100)
    assert result.status == status
    assert result.process_exit_code == 17
    assert result.cost_usd_cents == 7


def test_exact_completed_null_score_response_is_accepted_for_policy_normalization(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
print('{"status":"completed","score_millis":null,"cost_usd_cents":0,"detail":"accepted"}')
""")
    result = HermesExecutor((str(binary),)).execute(side="baseline", task_id="task", workspace=tmp_path, timeout_seconds=5, max_spend_usd_cents=100)
    assert result.status == "completed"
    assert result.score_millis is None


def test_duplicate_structured_result_keys_are_invalid(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
print('{"status":"completed","status":"invalid","score_millis":1,"cost_usd_cents":0,"detail":"ambiguous"}')
""")
    result = HermesExecutor((str(binary),)).execute(side="baseline", task_id="task", workspace=tmp_path, timeout_seconds=5, max_spend_usd_cents=100)
    assert result.status == "invalid"


def test_structured_observations_are_preserved(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
import json
print(json.dumps({
    'status': 'completed',
    'score_millis': 10,
    'cost_usd_cents': 1,
    'detail': 'observed',
    'observed': {
        'provider': 'reported-provider',
        'model': 'reported-model',
        'timings': {'provider_ms': 12},
        'retries': 1,
        'tool_behavior': {'filesystem': 'used'},
    },
}))
""")
    result = HermesExecutor((str(binary),)).execute(side="baseline", task_id="task", workspace=tmp_path, timeout_seconds=5, max_spend_usd_cents=100)
    assert dict(result.provider_facts) == {"reported_provider": "reported-provider", "reported_model": "reported-model"}
    assert dict(result.runtime_facts) == {"provider_ms": "12"}
    assert dict(result.tool_facts) == {"filesystem": "used"}
    assert result.retry_count == 1


def test_unstructured_nonzero_exit_is_agent_failure(tmp_path: Path) -> None:
    binary = executable(tmp_path, "raise SystemExit(9)\n")
    result = HermesExecutor((str(binary),)).execute(side="baseline", task_id="task", workspace=tmp_path, timeout_seconds=5, max_spend_usd_cents=100)
    assert result.status == "agent_failure"


def test_launcher_failure_is_infrastructure_failure(tmp_path: Path) -> None:
    result = HermesExecutor((str(tmp_path / "missing"),)).execute(side="baseline", task_id="task", workspace=tmp_path, timeout_seconds=5, max_spend_usd_cents=100)
    assert result.status == "infrastructure_failure"


@pytest.mark.parametrize("probe", ["status-list", "huge-cost"])
def test_malformed_structured_result_is_invalid_and_emits_receipts(tmp_path: Path, probe: str) -> None:
    binary = executable(tmp_path, """
import sys
arguments = sys.argv[1:]
probe = arguments[arguments.index('--probe') + 1]
if arguments[-1:] == ['--version']:
    print('Hermes Agent v9.9.9')
elif arguments[-2:] == ['config', 'show']:
    print("  Model:        {'provider': 'configured-provider', 'default': 'configured-model'}")
elif probe == 'status-list':
    print('{"status":[],"score_millis":null,"cost_usd_cents":0,"detail":"bad"}')
else:
    print('{"status":"completed","score_millis":1,"cost_usd_cents":' + ('9' * 5000) + ',"detail":"bad"}')
""")
    result = run_builtin_comparison(tmp_path / "state", HermesExecutor((str(binary), "--probe", probe)))
    assert result["status"] == "invalid"
    assert result["receipts"]
    receipt = show_receipt(tmp_path / "state", result["receipts"][0]["digest"])["receipt"]
    assert receipt["runs"]["baseline"]["status"] == "invalid"


def test_oversized_executor_stdout_is_bounded_invalid_and_receipted(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
import sys
arguments = sys.argv[1:]
if arguments[-1:] == ['--version']:
    print('Hermes Agent v9.9.9')
elif arguments[-2:] == ['config', 'show']:
    print("  Model:        {'provider': 'configured-provider', 'default': 'configured-model'}")
else:
    sys.stdout.write('x' * (4 * 1024 * 1024 + 1))
""")
    state = tmp_path / "state"
    result = run_builtin_comparison(state, HermesExecutor((str(binary),)))
    assert result["status"] == "invalid"
    receipt = show_receipt(state, result["receipts"][0]["digest"])["receipt"]
    baseline_run = receipt["runs"]["baseline"]
    assert baseline_run["status"] == "invalid"
    assert baseline_run["artifacts"][0]["size_bytes"] == MAX_CAPTURE_BYTES


def test_unpaired_surrogate_detail_is_sanitized_and_receipted(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
import json, sys
arguments = sys.argv[1:]
if arguments[-1:] == ['--version']:
    print('Hermes Agent v9.9.9')
elif arguments[-2:] == ['config', 'show']:
    print("  Model:        {'provider': 'configured-provider', 'default': 'configured-model'}")
else:
    print(json.dumps({
        'status': 'completed',
        'score_millis': 1,
        'cost_usd_cents': 0,
        'detail': chr(0xD800),
        'observed': {'provider': 'configured-provider', 'model': 'configured-model', 'timings': {}, 'retries': 0, 'tool_behavior': {}},
    }))
""")
    state = tmp_path / "state"
    result = run_builtin_comparison(state, HermesExecutor((str(binary),)))
    assert result["status"] == "completed"
    receipt = show_receipt(state, result["receipts"][0]["digest"])["receipt"]
    detail = receipt["runs"]["baseline"]["outcome"]["detail"]
    detail.encode("utf-8")
    assert "\ud800" not in detail


def test_negative_score_and_signal_returncode_round_trip_through_receipt(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
import json, os, signal, sys
arguments = sys.argv[1:]
if arguments[-1:] == ['--version']:
    print('Hermes Agent v9.9.9')
elif arguments[-2:] == ['config', 'show']:
    print("  Model:        {'provider': 'configured-provider', 'default': 'configured-model'}")
else:
    print(json.dumps({
        'status': 'completed',
        'score_millis': -25,
        'cost_usd_cents': 0,
        'detail': 'negative evidence',
        'observed': {'provider': 'configured-provider', 'model': 'configured-model', 'timings': {}, 'retries': 0, 'tool_behavior': {}},
    }), flush=True)
    os.kill(os.getpid(), signal.SIGTERM)
""")
    state = tmp_path / "state"
    result = run_builtin_comparison(state, HermesExecutor((str(binary),)))
    assert result["status"] == "completed"
    receipt = show_receipt(state, result["receipts"][0]["digest"])["receipt"]
    assert receipt["runs"]["baseline"]["outcome"]["score_millis"] == -25
    assert receipt["runs"]["baseline"]["execution"]["process_exit_code"] < 0
    assert receipt["outcome"]["baseline_score_millis"] == -25


def test_execution_model_drift_is_terminal_invalid_and_unscored(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
import json, sys
arguments = sys.argv[1:]
if arguments[-1:] == ['--version']:
    print('Hermes Agent v9.9.9')
elif arguments[-2:] == ['config', 'show']:
    print("  Model:        {'provider': 'configured-provider', 'default': 'model-A'}")
else:
    print(json.dumps({
        'status': 'completed',
        'score_millis': 100,
        'cost_usd_cents': 0,
        'detail': 'executed elsewhere',
        'observed': {'provider': 'configured-provider', 'model': 'model-B', 'timings': {}, 'retries': 0, 'tool_behavior': {}},
    }))
""")
    state = tmp_path / "state"
    result = run_builtin_comparison(state, HermesExecutor((str(binary),)))
    assert result["status"] == "invalid"
    receipt = show_receipt(state, result["receipts"][0]["digest"])["receipt"]
    baseline = receipt["runs"]["baseline"]
    assert baseline["status"] == "invalid"
    assert baseline["outcome"]["score_millis"] is None
    assert "matched-comparison violation" in baseline["outcome"]["detail"]


def test_missing_execution_identity_is_terminal_invalid(tmp_path: Path) -> None:
    binary = executable(tmp_path, """
import json, sys
arguments = sys.argv[1:]
if arguments[-1:] == ['--version']:
    print('Hermes Agent v9.9.9')
elif arguments[-2:] == ['config', 'show']:
    print("  Model:        {'provider': 'configured-provider', 'default': 'configured-model'}")
else:
    print(json.dumps({'status': 'completed', 'score_millis': 100, 'cost_usd_cents': 0, 'detail': 'identity omitted'}))
""")
    state = tmp_path / "state"
    result = run_builtin_comparison(state, HermesExecutor((str(binary),)))
    assert result["status"] == "invalid"
    receipt = show_receipt(state, result["receipts"][0]["digest"])["receipt"]
    assert receipt["runs"]["baseline"]["status"] == "invalid"
    assert receipt["runs"]["baseline"]["outcome"]["score_millis"] is None
