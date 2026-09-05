"""Shared validation and stable JSON helpers for canonical Verify records."""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from typing import Any


class ModelValidationError(ValueError):
    """A canonical record does not match its closed versioned shape."""


MAX_RECORD_INTEGER = 1_000_000_000
MAX_IDENTIFIER_LENGTH = 256


def require_record(value: Any, path: str) -> dict[str, Any]:
    if type(value) is not dict:
        raise ModelValidationError(f"{path} must be an object")
    return value


def require_exact_keys(value: Mapping[str, Any], expected: set[str], path: str) -> None:
    actual = set(value)
    missing = sorted(expected - actual)
    additional = sorted(actual - expected)
    if missing:
        raise ModelValidationError(f"{path} is missing fields: {', '.join(missing)}")
    if additional:
        raise ModelValidationError(f"{path} has additional fields: {', '.join(additional)}")


def require_type(value: Any, expected: type, path: str) -> Any:
    if type(value) is not expected:
        raise ModelValidationError(f"{path} must be {expected.__name__}")
    return value


def require_bool(value: Any, path: str) -> bool:
    if type(value) is not bool:
        raise ModelValidationError(f"{path} must be bool")
    return value


def require_string(value: Any, path: str, *, allow_empty: bool = False) -> str:
    require_type(value, str, path)
    if not allow_empty and not value:
        raise ModelValidationError(f"{path} must not be empty")
    try:
        value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise ModelValidationError(f"{path} must be UTF-8 encodable") from error
    return value


def require_identifier(value: Any, path: str) -> str:
    identifier = require_string(value, path)
    if identifier != identifier.strip():
        raise ModelValidationError(f"{path} must be trimmed")
    if len(identifier) > MAX_IDENTIFIER_LENGTH:
        raise ModelValidationError(f"{path} must be at most {MAX_IDENTIFIER_LENGTH} characters")
    if not identifier.isprintable():
        raise ModelValidationError(f"{path} must contain only printable characters")
    return identifier


def require_identifier_list(value: Any, path: str) -> list[str]:
    require_type(value, list, path)
    return [require_identifier(item, f"{path}[{index}]") for index, item in enumerate(value)]


def require_sha256(value: Any, path: str) -> str:
    digest = require_string(value, path)
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise ModelValidationError(f"{path} must be a lowercase SHA-256 digest")
    return digest


def require_nullable_sha256(value: Any, path: str) -> str | None:
    if value is None:
        return None
    return require_sha256(value, path)


def require_int(value: Any, path: str, *, minimum: int = 0) -> int:
    require_type(value, int, path)
    if value < minimum:
        raise ModelValidationError(f"{path} must be at least {minimum}")
    return value


def require_bounded_int(
    value: Any,
    path: str,
    *,
    minimum: int = -MAX_RECORD_INTEGER,
    maximum: int = MAX_RECORD_INTEGER,
) -> int:
    require_type(value, int, path)
    if not minimum <= value <= maximum:
        raise ModelValidationError(f"{path} must be between {minimum} and {maximum}")
    return value


def require_schema_version(value: Any, path: str) -> int:
    version = require_int(value, path, minimum=1)
    if version != 1:
        raise ModelValidationError(f"{path} must equal 1")
    return version


def require_nullable_string(value: Any, path: str) -> str | None:
    if value is None:
        return None
    return require_string(value, path)


def require_nullable_int(value: Any, path: str, *, minimum: int = -MAX_RECORD_INTEGER) -> int | None:
    if value is None:
        return None
    return require_bounded_int(value, path, minimum=minimum)


def require_string_list(value: Any, path: str) -> list[str]:
    require_type(value, list, path)
    return [require_string(item, f"{path}[{index}]") for index, item in enumerate(value)]


def require_json_value(value: Any, path: str) -> Any:
    """Validate the closed JSON value shape used by sealed answer keys."""

    if value is None or type(value) in {bool, int, str}:
        return value
    if type(value) is list:
        return [require_json_value(item, f"{path}[{index}]") for index, item in enumerate(value)]
    if type(value) is dict:
        for key, item in value.items():
            if type(key) is not str:
                raise ModelValidationError(f"{path} object keys must be strings")
        return {key: require_json_value(item, f"{path}.{key}") for key, item in value.items()}
    raise ModelValidationError(f"{path} must be a JSON value without floating-point numbers")


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n"


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ModelValidationError(f"duplicate JSON object key: {key}")
        value[key] = item
    return value


def strict_json_loads(value: str | bytes | bytearray) -> Any:
    return json.loads(value, object_pairs_hook=_strict_object)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def content_id(prefix: str, value: Any) -> str:
    return f"{prefix}-{sha256_bytes(canonical_json_bytes(value))[:24]}"
