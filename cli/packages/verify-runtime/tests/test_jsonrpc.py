from __future__ import annotations

import json
import os
import subprocess
import sys
from copy import deepcopy
from pathlib import Path

import pytest

from verify_runtime import FAMILY_CONTRACT


def call(request: object, *, env: dict[str, str] | None = None) -> dict[str, object]:
    result = subprocess.run(
        [sys.executable, "-m", "verify_runtime"],
        input=json.dumps(request),
        text=True,
        capture_output=True,
        check=True,
        env=None if env is None else os.environ | env,
    )
    assert result.stderr == ""
    return json.loads(result.stdout)


def test_show_is_stable_json() -> None:
    request = {
        "jsonrpc": "2.0",
        "id": "show",
        "method": "techtree.forge.family.show",
    }
    first = call(request)
    second = call(request)

    assert first == second == {"jsonrpc": "2.0", "id": "show", "result": FAMILY_CONTRACT}


def test_validate_is_stable_json() -> None:
    request = {
        "jsonrpc": "2.0",
        "id": "validate",
        "method": "techtree.forge.family.validate",
        "params": {
            "input": {
                "family": deepcopy(FAMILY_CONTRACT),
                "baseline": {"files": {"SKILL.md": "before"}},
                "candidate": {"files": {"SKILL.md": "after"}},
            }
        },
    }

    assert call(request) == call(request)


def test_rejects_unknown_methods_and_extra_envelope_fields() -> None:
    assert call({"jsonrpc": "2.0", "id": "x", "method": "verify.run"})["error"] == {
        "code": -32601,
        "message": "method not found",
    }
    assert call(
        {
            "jsonrpc": "2.0",
            "id": "x",
            "method": "techtree.forge.family.show",
            "extra": True,
        }
    )["error"] == {"code": -32600, "message": "request has additional fields"}


def test_verify_run_status_and_receipt_show(tmp_path: Path) -> None:
    run = call({
        "jsonrpc": "2.0",
        "id": "run",
        "method": "techtree.verify.run",
        "params": {
            "state_dir": str(tmp_path),
            "builtin": True,
            "executor": "fixture",
            "hermes_command": None,
        },
    })["result"]
    assert run["status"] == "completed"
    assert len(run["receipts"]) == 11
    status = call({
        "jsonrpc": "2.0",
        "id": "status",
        "method": "techtree.verify.status",
        "params": {"state_dir": str(tmp_path), "comparison_id": run["comparison_id"]},
    })["result"]
    assert status == run
    for pointer in run["receipts"]:
        shown = call({
            "jsonrpc": "2.0",
            "id": "show",
            "method": "techtree.verify.receipt.show",
            "params": {"state_dir": str(tmp_path), "digest": pointer["digest"]},
        })["result"]
        assert shown["verified"] is True
        assert shown["receipt"]["capsules"].keys() == {"baseline", "candidate"}


def test_uplift_rpc_rejects_an_empty_receipt_set(tmp_path: Path) -> None:
    response = call({
        "jsonrpc": "2.0",
        "id": "uplift",
        "method": "techtree.uplift.report",
        "params": {"state_dir": str(tmp_path), "receipt_digests": [], "tolerance": None},
    })
    assert response["error"] == {
        "code": -32602,
        "message": "receipt_digests must be a non-empty string array",
    }


def test_hermes_runner_is_config_gated(tmp_path: Path) -> None:
    response = call({
        "jsonrpc": "2.0",
        "id": "run",
        "method": "techtree.verify.run",
        "params": {
            "state_dir": str(tmp_path),
            "builtin": True,
            "executor": "hermes",
            "hermes_command": None,
        },
    })
    assert response["error"] == {
        "code": -32602,
        "message": "Hermes execution requires a non-empty command string array",
    }


def test_prime_runner_is_config_gated_and_reachable(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    request = {
        "jsonrpc": "2.0",
        "id": "run",
        "method": "techtree.verify.run",
        "params": {
            "state_dir": str(tmp_path),
            "builtin": True,
            "executor": "prime",
            "hermes_command": None,
        },
    }
    monkeypatch.delenv("REGENT_VERIFY_PRIME_FACTORY", raising=False)
    unconfigured = call(request)
    assert unconfigured["error"]["code"] == -32602
    assert "REGENT_VERIFY_PRIME_FACTORY=module:function" in unconfigured["error"]["message"]
    tests_path = str(Path(__file__).parent)
    python_path = tests_path if not os.environ.get("PYTHONPATH") else f"{tests_path}{os.pathsep}{os.environ['PYTHONPATH']}"
    configured = call(
        request,
        env={"REGENT_VERIFY_PRIME_FACTORY": "prime_fixture_factory:create_executor", "PYTHONPATH": python_path},
    )
    assert configured["result"]["status"] == "completed"
    assert len(configured["result"]["receipts"]) == 11


def test_hermes_resolution_failure_is_truthful_infrastructure_error(tmp_path: Path) -> None:
    response = call({
        "jsonrpc": "2.0",
        "id": "run",
        "method": "techtree.verify.run",
        "params": {
            "state_dir": str(tmp_path),
            "builtin": True,
            "executor": "hermes",
            "hermes_command": [str(tmp_path / "missing-hermes")],
        },
    })
    assert response["error"]["code"] == -32003
    assert "not found" in response["error"]["message"]


@pytest.mark.parametrize("probe", ["status-list", "huge-cost"])
def test_malformed_hermes_result_is_receipted_through_runtime_entrypoint(tmp_path: Path, probe: str) -> None:
    script = tmp_path / "fake_hermes.py"
    script.write_text("""
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
""", encoding="utf-8")

    response = call({
        "jsonrpc": "2.0",
        "id": "run",
        "method": "techtree.verify.run",
        "params": {
            "state_dir": str(tmp_path / "state"),
            "builtin": True,
            "executor": "hermes",
            "hermes_command": [sys.executable, str(script), "--probe", probe],
        },
    })

    assert response["result"]["status"] == "invalid"
    assert response["result"]["receipts"]
