"""Immutable content-addressed stores for Uplift reports and packages."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Any

from verify_runtime.model import EvaluationReceipt, ReproductionPackage, UpliftReport, canonical_json_bytes, sha256_bytes, strict_json_loads
from verify_runtime.receipts import show_receipt

from .errors import UpliftReportCollisionError, UpliftReportConflictError
from .package import reproduction_package_bytes, reproduction_package_digest, validated_reproduction_package


def _report_directory(state_dir: Path) -> Path:
    return state_dir / "verify" / "uplift" / "reports" / "sha256"


def _package_directory(state_dir: Path) -> Path:
    return state_dir / "verify" / "uplift" / "packages" / "sha256"


def _set_index_directory(state_dir: Path) -> Path:
    return state_dir / "verify" / "uplift" / "sets" / "sha256"


def _set_key(receipt_digests: tuple[str, ...]) -> str:
    return sha256_bytes(canonical_json_bytes(list(sorted(receipt_digests))))


def _emit(directory: Path, payload: bytes, *, kind: str) -> dict[str, Any]:
    digest = sha256_bytes(payload)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{digest}.json"
    if path.exists():
        if path.read_bytes() != payload:
            raise UpliftReportCollisionError(f"immutable {kind} collision for {digest}")
        return {"algorithm": "sha256", "digest": digest, "path": str(path)}

    # The temporary name is deterministic so a retry can finish a write that
    # was interrupted before the atomic finalize.  The final name remains
    # content-addressed and is never replaced with different bytes.
    temporary = path.with_name(f".{path.name}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    if path.exists():
        if path.read_bytes() != payload:
            raise UpliftReportCollisionError(f"immutable {kind} collision for {digest}")
        temporary.unlink(missing_ok=True)
    else:
        os.replace(temporary, path)
    return {"algorithm": "sha256", "digest": digest, "path": str(path)}


def _show(directory: Path, digest: str, *, kind: str) -> dict[str, Any]:
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise ValueError(f"{kind} digest must be 64 lowercase hexadecimal characters")
    path = directory / f"{digest}.json"
    if not path.is_file():
        raise FileNotFoundError(f"{kind} not found: {digest}")
    payload = path.read_bytes()
    observed = sha256_bytes(payload)
    if observed != digest:
        raise ValueError(f"{kind} digest mismatch: expected {digest}, observed {observed}")
    return {"algorithm": "sha256", "digest": digest, "path": str(path), "verified": True, "payload": strict_json_loads(payload)}


def emit_reproduction_package(state_dir: Path, package: ReproductionPackage) -> dict[str, Any]:
    validated = validated_reproduction_package(package)
    return _emit(_package_directory(state_dir), reproduction_package_bytes(validated), kind="reproduction package")


def show_reproduction_package(state_dir: Path, digest: str) -> dict[str, Any]:
    shown = _show(_package_directory(state_dir), digest, kind="reproduction package")
    package = ReproductionPackage.from_dict(shown["payload"])
    return {
        "schema_version": 1,
        "algorithm": shown["algorithm"],
        "digest": digest,
        "path": shown["path"],
        "verified": True,
        "package": package.to_dict(),
    }


def _set_index_path(state_dir: Path, receipt_digests: tuple[str, ...]) -> Path:
    return _set_index_directory(state_dir) / f"{_set_key(receipt_digests)}.json"


def _read_set_index(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    record = strict_json_loads(path.read_bytes())
    if type(record) is not dict or set(record) != {"schema_version", "receipt_digests", "report", "package"} or record["schema_version"] != 1:
        raise UpliftReportConflictError(f"uplift report set index is malformed: {path}")
    return record


def _sweep_stale_set_links(path: Path) -> None:
    try:
        final = os.stat(path, follow_symlinks=False)
    except FileNotFoundError:
        return
    for temporary in path.parent.glob(f".{path.name}.*.tmp"):
        try:
            candidate = os.stat(temporary, follow_symlinks=False)
        except FileNotFoundError:
            continue
        if (candidate.st_dev, candidate.st_ino) == (final.st_dev, final.st_ino):
            temporary.unlink(missing_ok=True)


def _reserve_set_index(path: Path, payload: bytes) -> tuple[dict[str, Any], bool]:
    """Atomically create or recover the receipt-set reservation.

    Each writer flushes a private temporary file, then links it into the final
    no-overwrite path.  The winner verifies the installed bytes before its
    temporary link is removed; the loser reads the winner's index.
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    existing = _read_set_index(path)
    if existing is not None:
        _sweep_stale_set_links(path)
        return existing, False

    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path)
        except FileExistsError:
            existing = _read_set_index(path)
            if existing is None:
                raise UpliftReportConflictError("uplift report set reservation disappeared")
            _sweep_stale_set_links(path)
            return existing, False
        installed = path.read_bytes()
        if installed != payload:
            raise UpliftReportConflictError("uplift report set reservation finalize verification failed")
        installed_record = _read_set_index(path)
        if installed_record is None:
            raise UpliftReportConflictError("uplift report set reservation disappeared after finalize")
        return installed_record, True
    finally:
        temporary.unlink(missing_ok=True)


def _validated_receipts(state_dir: Path, receipt_digests: tuple[str, ...]) -> tuple[EvaluationReceipt, ...]:
    return tuple(
        EvaluationReceipt.from_dict(show_receipt(state_dir, digest)["receipt"])
        for digest in sorted(receipt_digests)
    )


def _existing_set_result(
    state_dir: Path,
    index: dict[str, Any],
    report_payload: bytes,
    package_payload: bytes,
    receipts: tuple[EvaluationReceipt, ...],
    package_digest: str,
) -> dict[str, Any]:
    expected_receipt_digests = tuple(sorted(receipt.content_digest() for receipt in receipts))
    indexed_receipt_digests = index.get("receipt_digests")
    if (
        type(indexed_receipt_digests) is not list
        or any(type(digest) is not str for digest in indexed_receipt_digests)
        or tuple(indexed_receipt_digests) != expected_receipt_digests
    ):
        raise UpliftReportConflictError("uplift report set index is anchored to different receipts")
    report_record = index["report"]
    package_record = index["package"]
    if type(report_record) is not dict or type(package_record) is not dict:
        raise UpliftReportConflictError("uplift report set index is malformed")
    existing_report_digest = report_record.get("digest")
    existing_package_digest = package_record.get("digest")
    existing_report_id = report_record.get("id")
    if type(existing_report_id) is not str or type(existing_report_digest) is not str or type(existing_package_digest) is not str:
        raise UpliftReportConflictError("uplift report set index is malformed")

    expected_report_digest = sha256_bytes(report_payload)
    if existing_report_digest != expected_report_digest or existing_package_digest != package_digest:
        raise UpliftReportConflictError(
            f"receipt set already has report {existing_report_id} ({existing_report_digest}); supplied auxiliary inputs conflict"
        )

    # An index is a recoverable reservation, not a dead end.  Re-emitting the
    # same deterministic bytes completes whichever archive boundary was
    # interrupted, and is idempotent when both archives already exist.
    package_pointer = _emit(_package_directory(state_dir), package_payload, kind="reproduction package")
    report_pointer = _emit(_report_directory(state_dir), report_payload, kind="Uplift report")
    shown = _show(_report_directory(state_dir), existing_report_digest, kind="Uplift report")
    package_shown = _show(_package_directory(state_dir), existing_package_digest, kind="reproduction package")
    existing_report = UpliftReport.from_dict(shown["payload"])
    if existing_report.report_id != existing_report_id:
        raise UpliftReportConflictError("uplift report set index does not name its stored report")
    existing_package = ReproductionPackage.from_dict(package_shown["payload"])
    if existing_package.receipt_digests != expected_receipt_digests:
        raise UpliftReportConflictError("uplift report set index package is anchored to different receipts")
    existing_report.validate_against_receipts(receipts)
    if existing_package_digest == package_digest and canonical_json_bytes(existing_report.to_dict()) == report_payload:
        return {
            "report_pointer": report_pointer,
            "reproduction_package": package_pointer,
            "report": existing_report.to_dict(),
            "idempotent": True,
        }
    raise UpliftReportConflictError(
        f"receipt set already has report {existing_report.report_id} ({existing_report_digest}); supplied auxiliary inputs conflict"
    )


def emit_uplift_result(
    state_dir: Path,
    report: UpliftReport,
    package: ReproductionPackage,
    receipt_digests: tuple[str, ...],
) -> dict[str, Any]:
    validated_report = UpliftReport.from_dict(report.to_dict())
    if not receipt_digests or any(type(digest) is not str for digest in receipt_digests):
        raise UpliftReportConflictError("uplift result requires a non-empty receipt set from the immutable receipt store")
    normalized_receipt_digests = tuple(sorted(receipt_digests))
    if len(set(normalized_receipt_digests)) != len(normalized_receipt_digests):
        raise UpliftReportConflictError("uplift result requires distinct receipt digests")
    receipts = _validated_receipts(state_dir, normalized_receipt_digests)
    if validated_report.receipt_digests != normalized_receipt_digests:
        raise UpliftReportConflictError("uplift report is not keyed to the canonical receipt set")
    validated_report.validate_against_receipts(receipts)
    validated_package = validated_reproduction_package(package)
    if validated_package.receipt_digests != normalized_receipt_digests:
        raise UpliftReportConflictError("reproduction package is not keyed to the canonical receipt set")
    package_digest = reproduction_package_digest(validated_package)
    if validated_report.reproduction_package_digest != package_digest:
        raise UpliftReportConflictError("uplift report does not reference the assembled reproduction package")
    report_payload = canonical_json_bytes(validated_report.to_dict())
    package_payload = reproduction_package_bytes(validated_package)
    report_digest = sha256_bytes(report_payload)
    index_path = _set_index_path(state_dir, validated_report.receipt_digests)
    existing = _read_set_index(index_path)
    if existing is not None:
        _sweep_stale_set_links(index_path)
        return _existing_set_result(state_dir, existing, report_payload, package_payload, receipts, package_digest)

    index_record = {
        "schema_version": 1,
        "receipt_digests": list(validated_report.receipt_digests),
        "report": {"id": validated_report.report_id, "digest": report_digest},
        "package": {"digest": package_digest},
    }
    index_bytes = canonical_json_bytes(index_record)
    reserved, created = _reserve_set_index(index_path, index_bytes)
    if not created:
        return _existing_set_result(state_dir, reserved, report_payload, package_payload, receipts, package_digest)
    package_pointer = _emit(_package_directory(state_dir), package_payload, kind="reproduction package")
    report_pointer = _emit(_report_directory(state_dir), report_payload, kind="Uplift report")
    return {"report_pointer": report_pointer, "reproduction_package": package_pointer, "report": validated_report.to_dict(), "idempotent": False}


def show_uplift_report(state_dir: Path, digest: str) -> dict[str, Any]:
    shown = _show(_report_directory(state_dir), digest, kind="Uplift report")
    report = UpliftReport.from_dict(shown["payload"])
    receipts = _validated_receipts(state_dir, report.receipt_digests)
    report.validate_against_receipts(receipts)
    if report.reproduction_package_status == "available":
        package_record = report.reproduction_package_digest
        if package_record is None:
            raise ValueError("Uplift report package status is available without a package digest")
        package = _show(_package_directory(state_dir), package_record, kind="reproduction package")
        archived_package = ReproductionPackage.from_dict(package["payload"])
        if archived_package.receipt_digests != report.receipt_digests:
            raise ValueError("Uplift report package is not keyed to the canonical receipt set")
    return {
        "schema_version": 1,
        "algorithm": shown["algorithm"],
        "digest": digest,
        "path": shown["path"],
        "verified": True,
        "report": report.to_dict(),
    }
