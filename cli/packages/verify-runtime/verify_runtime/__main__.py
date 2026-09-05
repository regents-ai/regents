"""One-request JSON-RPC entrypoint for the local Verify runtime."""

from __future__ import annotations

import importlib
import json
import os
import sys
from pathlib import Path
from typing import Any

from .forge_family import FAMILY_CONTRACT, ValidationError, validate_family
from .receipts import show_receipt
from .runner import ComparisonBusyError, ComparisonSpendExhaustedError, ComparisonStateError, Executor, FixtureExecutor, HermesExecutor, run_builtin_comparison, show_comparison_status
from .runner.executors import RuntimeResolutionError
from .uplift import UpliftInputError, UpliftReceiptNotFound, UpliftReportCollisionError, UpliftReportConflictError, generate_uplift_report


METHOD_SHOW = "techtree.forge.family.show"
METHOD_VALIDATE = "techtree.forge.family.validate"
METHOD_VERIFY_RUN = "techtree.verify.run"
METHOD_VERIFY_STATUS = "techtree.verify.status"
METHOD_RECEIPT_SHOW = "techtree.verify.receipt.show"
METHOD_UPLIFT_REPORT = "techtree.uplift.report"
PRIME_FACTORY_ENV = "REGENT_VERIFY_PRIME_FACTORY"


def _prime_executor(state_dir: Path) -> Executor:
    reference = os.environ.get(PRIME_FACTORY_ENV)
    if reference is None:
        raise ValidationError(
            "Prime execution is not configured. Set "
            f"{PRIME_FACTORY_ENV}=module:function in the local runtime process, "
            "install the adapters-prime dependency group for live use, and retry."
        )
    module_name, separator, attribute_name = reference.partition(":")
    if separator != ":" or not module_name or not attribute_name or ":" in attribute_name:
        raise ValidationError(f"{PRIME_FACTORY_ENV} must use module:function syntax")
    try:
        factory = getattr(importlib.import_module(module_name), attribute_name)
    except (ImportError, AttributeError) as error:
        raise ValidationError(
            f"{PRIME_FACTORY_ENV} could not be loaded; verify the configured module:function and retry"
        ) from error
    if not callable(factory):
        raise ValidationError(f"{PRIME_FACTORY_ENV} must resolve to a callable")
    try:
        executor = factory(state_dir)
    except ModuleNotFoundError as error:
        raise ValidationError(
            "Prime executor configuration could not start; install the adapters-prime dependency group, "
            "verify the configured module:function, and retry"
        ) from error
    if getattr(executor, "name", None) != "prime":
        raise ValidationError("Prime executor configuration returned the wrong executor")
    return executor


def _error(request_id: str | None, code: int, message: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": code, "message": message},
    }


def _dispatch(request: Any) -> dict[str, Any]:
    if type(request) is not dict:
        return _error(None, -32600, "request must be an object")

    request_id = request.get("id") if type(request.get("id")) is str else None
    if set(request) - {"jsonrpc", "id", "method", "params"}:
        return _error(request_id, -32600, "request has additional fields")
    if request.get("jsonrpc") != "2.0" or request_id is None or type(request.get("method")) is not str:
        return _error(request_id, -32600, "invalid JSON-RPC request")

    method = request["method"]
    params = request.get("params")
    try:
        if method == METHOD_SHOW:
            if params is not None:
                raise ValidationError("show params must be omitted")
            result = FAMILY_CONTRACT
        elif method == METHOD_VALIDATE:
            if type(params) is not dict or set(params) != {"input"}:
                raise ValidationError("validate params must contain only input")
            result = validate_family(params["input"])
        elif method == METHOD_VERIFY_RUN:
            if type(params) is not dict or set(params) != {"state_dir", "builtin", "executor", "hermes_command"}:
                raise ValidationError("verify run params must contain only state_dir, builtin, executor, and hermes_command")
            if type(params["state_dir"]) is not str or not params["state_dir"]:
                raise ValidationError("state_dir must be a non-empty string")
            if params["builtin"] is not True:
                raise ValidationError("only the built-in family is available")
            if params["executor"] == "fixture":
                if params["hermes_command"] is not None:
                    raise ValidationError("fixture execution does not accept a Hermes command")
                executor = FixtureExecutor()
            elif params["executor"] == "hermes":
                command = params["hermes_command"]
                if type(command) is not list or not command or any(type(part) is not str or not part for part in command):
                    raise ValidationError("Hermes execution requires a non-empty command string array")
                executor = HermesExecutor(tuple(command))
            elif params["executor"] == "prime":
                if params["hermes_command"] is not None:
                    raise ValidationError("Prime execution does not accept a Hermes command")
                executor = _prime_executor(Path(params["state_dir"]))
            else:
                raise ValidationError("executor must be fixture, hermes, or configured prime")
            result = run_builtin_comparison(Path(params["state_dir"]), executor)
        elif method == METHOD_VERIFY_STATUS:
            if type(params) is not dict or set(params) != {"state_dir", "comparison_id"}:
                raise ValidationError("verify status params must contain only state_dir and comparison_id")
            if type(params["state_dir"]) is not str or type(params["comparison_id"]) is not str:
                raise ValidationError("state_dir and comparison_id must be strings")
            result = show_comparison_status(Path(params["state_dir"]), params["comparison_id"])
        elif method == METHOD_RECEIPT_SHOW:
            if type(params) is not dict or set(params) != {"state_dir", "digest"}:
                raise ValidationError("receipt show params must contain only state_dir and digest")
            if type(params["state_dir"]) is not str or type(params["digest"]) is not str:
                raise ValidationError("state_dir and digest must be strings")
            result = show_receipt(Path(params["state_dir"]), params["digest"])
        elif method == METHOD_UPLIFT_REPORT:
            if type(params) is not dict or set(params) != {"state_dir", "receipt_digests", "tolerance"}:
                raise ValidationError("uplift report params must contain only state_dir, receipt_digests, and tolerance")
            if type(params["state_dir"]) is not str or not params["state_dir"]:
                raise ValidationError("state_dir must be a non-empty string")
            if type(params["receipt_digests"]) is not list or not params["receipt_digests"] or any(type(digest) is not str for digest in params["receipt_digests"]):
                raise ValidationError("receipt_digests must be a non-empty string array")
            if params["tolerance"] is not None and type(params["tolerance"]) is not dict:
                raise ValidationError("tolerance must be an object or null")
            result = generate_uplift_report(Path(params["state_dir"]), params["receipt_digests"], params["tolerance"])
        else:
            return _error(request_id, -32601, "method not found")
    except UpliftReceiptNotFound as error:
        return _error(request_id, -32007, str(error))
    except UpliftReportCollisionError as error:
        return _error(request_id, -32009, str(error))
    except UpliftReportConflictError as error:
        return _error(request_id, -32010, str(error))
    except UpliftInputError as error:
        return _error(request_id, -32008, str(error))
    except (ValidationError, ValueError) as error:
        return _error(request_id, -32602, str(error))
    except FileNotFoundError as error:
        return _error(request_id, -32004, str(error))
    except RuntimeResolutionError as error:
        return _error(request_id, -32003, str(error))
    except ComparisonBusyError as error:
        return _error(request_id, -32005, str(error))
    except ComparisonSpendExhaustedError as error:
        return _error(request_id, -32006, str(error))
    except ComparisonStateError as error:
        return _error(request_id, -32003, str(error))

    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def main() -> int:
    try:
        request = json.loads(sys.stdin.read())
    except json.JSONDecodeError:
        response = _error(None, -32700, "invalid JSON")
    else:
        response = _dispatch(request)

    sys.stdout.write(json.dumps(response, sort_keys=True, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
