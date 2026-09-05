"""Receipt-only uplift report generation and archival orchestration."""

from __future__ import annotations

from dataclasses import replace
from pathlib import Path
from typing import Any, Sequence

from verify_runtime.model import ActionReceipt, content_id

from .compare import compare_receipts, make_report_without_package
from .errors import UpliftInputError
from .package import assemble_reproduction_package, reproduction_package_digest
from .store import emit_uplift_result


def _validate_digest(value: Any, path: str) -> str:
    if type(value) is not str or len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise UpliftInputError(f"{path} must be a lowercase SHA-256 digest")
    return value


def _next_action(digests: tuple[str, ...]) -> str:
    flags = " ".join(f"--receipt-digest {digest}" for digest in digests)
    return f"regents techtree uplift report {flags} --json"


def generate_uplift_report(
    state_dir: Path,
    receipt_digests: Sequence[str],
    tolerance: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Verify a receipt set, assemble a package, and archive one report."""

    if not receipt_digests:
        raise UpliftInputError("uplift report requires a non-empty receipt set")
    digests = tuple(sorted(_validate_digest(value, f"receipt_digests[{index}]") for index, value in enumerate(receipt_digests)))
    if len(set(digests)) != len(digests):
        raise UpliftInputError("uplift report requires distinct receipt digests")
    comparison = compare_receipts(state_dir, digests)
    package = assemble_reproduction_package(comparison, tolerance)
    package_digest = reproduction_package_digest(package)
    report = make_report_without_package(comparison, package_digest, tolerance_supplied=tolerance is not None)
    action = ActionReceipt(
        action_id=content_id("action", {"report_id": report.report_id, "package_digest": package_digest}),
        capability_id="techtree.uplift",
        action_kind="report",
        resource_type="uplift_report",
        resource_id=report.report_id,
        status="completed",
        idempotency_key=content_id("uplift-action", {"receipt_digests": list(comparison.receipt_digests)}),
        created_at=None,
        updated_at=None,
        public_url=None,
        next_recommended_action=_next_action(comparison.receipt_digests),
        next_poll_at=None,
        approval_required=False,
        chain_id=None,
        transaction_hash=None,
        error_code=None,
    )
    report = replace(report, action_receipt=action)
    stored = emit_uplift_result(state_dir, report, package, comparison.receipt_digests)
    stored_report = stored["report"]
    package_pointer = stored["reproduction_package"]
    report_pointer = stored["report_pointer"]
    return {
        "schema_version": 1,
        "status": "completed",
        "report": stored_report,
        "report_pointer": report_pointer,
        "reproduction_package": package_pointer,
        "action_receipt": stored_report["action_receipt"],
        "next_steps": [],
    }
