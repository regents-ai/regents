"""Digest-pinned references to external Verifiers v1 Taskset packages."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .base import ModelValidationError, require_exact_keys, require_identifier, require_record, require_schema_version, require_sha256, sha256_bytes


@dataclass(frozen=True)
class TasksetPackageReference:
    """Reference to a v1 Taskset package, never its task shapes."""

    schema_version: int
    package: str
    version: str
    content_hash: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "package": self.package,
            "version": self.version,
            "content_hash": self.content_hash,
        }

    def verify_content(self, content: bytes | bytearray) -> bytes:
        if not isinstance(content, (bytes, bytearray)):
            raise ModelValidationError("taskset package content must be bytes")
        loaded = bytes(content)
        if sha256_bytes(loaded) != self.content_hash:
            raise ModelValidationError("taskset package content hash mismatch")
        return loaded

    @classmethod
    def from_dict(cls, value: Any) -> "TasksetPackageReference":
        record = require_record(value, "taskset_package")
        require_exact_keys(record, {"schema_version", "package", "version", "content_hash"}, "taskset_package")
        return cls(
            require_schema_version(record["schema_version"], "taskset_package.schema_version"),
            require_identifier(record["package"], "taskset_package.package"),
            require_identifier(record["version"], "taskset_package.version"),
            require_sha256(record["content_hash"], "taskset_package.content_hash"),
        )
