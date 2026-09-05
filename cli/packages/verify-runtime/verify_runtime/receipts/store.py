"""Public read-only access to runner-emitted receipts."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from ._store import _load_receipt


def show_receipt(state_dir: Path, digest: str) -> dict[str, Any]:
    receipt = _load_receipt(state_dir, digest)
    return {"schema_version": 1, "digest": digest, "algorithm": "sha256", "verified": True, "receipt": receipt.to_dict()}
