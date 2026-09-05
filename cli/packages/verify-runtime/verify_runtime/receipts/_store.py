"""Runner-internal receipt emission and store identity handling."""

from __future__ import annotations

import os
import secrets
import stat
import tempfile
from pathlib import Path
from typing import Any

from verify_runtime.model import EvaluationReceipt, canonical_json_bytes, sha256_bytes, strict_json_loads
from verify_runtime.model.base import require_exact_keys, require_record, require_schema_version, require_sha256


def _receipt_root(state_dir: Path) -> Path:
    return state_dir / "verify" / "receipts"


def _receipt_directory(state_dir: Path) -> Path:
    return _receipt_root(state_dir) / "sha256"


def _store_identity_path(state_dir: Path) -> Path:
    return _receipt_root(state_dir) / "store.json"


def _reject_symlink(path: Path) -> None:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return
    if stat.S_ISLNK(mode):
        raise ValueError(f"receipt store directory must not be a symlink: {path}")
    if not stat.S_ISDIR(mode):
        raise ValueError(f"receipt store path is not a directory: {path}")


def _prepare_directories(state_dir: Path, *, create: bool) -> None:
    paths = (state_dir, state_dir / "verify", _receipt_root(state_dir), _receipt_directory(state_dir))
    for path in paths:
        _reject_symlink(path)
        if not path.exists():
            if not create:
                raise FileNotFoundError(f"receipt store not found: {state_dir}")
            path.mkdir(parents=True, exist_ok=True)
        _reject_symlink(path)


def _parse_store_identity(payload: bytes) -> str:
    record = require_record(strict_json_loads(payload), "receipt_store")
    require_exact_keys(record, {"schema_version", "store_id"}, "receipt_store")
    require_schema_version(record["schema_version"], "receipt_store.schema_version")
    return require_sha256(record["store_id"], "receipt_store.store_id")


def _read_store_identity(state_dir: Path) -> str:
    path = _store_identity_path(state_dir)
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as error:
        raise ValueError(f"receipt store identity is missing: {path}") from error
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise ValueError(f"receipt store identity must be a regular file: {path}")
    return _parse_store_identity(path.read_bytes())


def _initialize_store_identity(state_dir: Path) -> str:
    path = _store_identity_path(state_dir)
    try:
        return _read_store_identity(state_dir)
    except ValueError as error:
        if path.exists() or path.is_symlink():
            raise error

    store_id = secrets.token_hex(32)
    payload = canonical_json_bytes({"schema_version": 1, "store_id": store_id})
    descriptor, temporary_name = tempfile.mkstemp(prefix=".store.", suffix=".tmp", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path)
        except FileExistsError:
            return _read_store_identity(state_dir)
        if path.read_bytes() != payload:
            raise ValueError("receipt store identity finalize verification failed")
        return store_id
    finally:
        temporary.unlink(missing_ok=True)


def _receipt_store_id(state_dir: Path, *, create: bool = True) -> str:
    _prepare_directories(state_dir, create=create)
    return _initialize_store_identity(state_dir) if create else _read_store_identity(state_dir)


def _emit_receipt(state_dir: Path, receipt: EvaluationReceipt) -> dict[str, Any]:
    """Internal test seam; production calls this only from runner execution."""

    store_id = _receipt_store_id(state_dir)
    validated_receipt = EvaluationReceipt.from_dict(receipt.to_dict())
    if validated_receipt.store_id != store_id:
        raise ValueError("receipt store identity does not match the emitting store")
    receipt_bytes = canonical_json_bytes(validated_receipt.to_dict())
    digest = sha256_bytes(receipt_bytes)
    path = _receipt_directory(state_dir) / f"{digest}.json"
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        if path.read_bytes() != receipt_bytes:
            raise RuntimeError(f"immutable receipt collision for {digest}")
    else:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(receipt_bytes)
    return {"digest": digest, "algorithm": "sha256", "path": str(path)}


def _load_receipt(state_dir: Path, digest: str) -> EvaluationReceipt:
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise ValueError("receipt digest must be 64 lowercase hexadecimal characters")
    store_id = _receipt_store_id(state_dir, create=False)
    path = _receipt_directory(state_dir) / f"{digest}.json"
    if not path.is_file() or path.is_symlink():
        raise FileNotFoundError(f"receipt not found: {digest}")
    receipt_bytes = path.read_bytes()
    observed_digest = sha256_bytes(receipt_bytes)
    if observed_digest != digest:
        raise ValueError(f"receipt digest mismatch: expected {digest}, observed {observed_digest}")
    receipt = EvaluationReceipt.from_dict(strict_json_loads(receipt_bytes))
    if receipt.store_id != store_id:
        raise ValueError(f"receipt store identity mismatch: receipt {receipt.store_id}, store {store_id}")
    return receipt
