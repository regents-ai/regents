"""Canonical sealed verifier material and answer-key commitments."""

from __future__ import annotations

from collections.abc import Mapping
import hmac
import secrets
from typing import Any

from .base import ModelValidationError, canonical_json_bytes, require_json_value, require_sha256, sha256_bytes


SEALED_VERIFIER_PACKET_FORMAT = "regent-forge-prime-v1"
MIN_BLINDING_NONCE_BYTES = 32


def new_answer_key_blinding_nonce() -> bytes:
    """Create the high-entropy nonce kept with a sealed answer key."""

    return secrets.token_bytes(MIN_BLINDING_NONCE_BYTES)


def require_blinding_nonce(value: Any, path: str = "sealed.blinding_nonce") -> bytes:
    """Require a secret nonce large enough to defeat offline answer guessing."""

    if not isinstance(value, (bytes, bytearray)):
        raise ModelValidationError(f"{path} must be bytes")
    nonce = bytes(value)
    if len(nonce) < MIN_BLINDING_NONCE_BYTES:
        raise ModelValidationError(f"{path} must contain at least {MIN_BLINDING_NONCE_BYTES} random bytes")
    return nonce


def sealed_verifier_material(
    *,
    family: Mapping[str, Any],
    task: Mapping[str, Any],
    grader_source: bytes,
    answer_key: Any,
) -> bytes:
    """Build the canonical verifier material whose digest commits the answer key.

    The public reference-commitment index and the task commitment are
    deliberately omitted from this input: including either would make
    commitment creation circular.  The raw answer key exists only in the
    separately constructed sealed packet.
    """

    if not isinstance(grader_source, bytes):
        raise ModelValidationError("sealed verifier grader source must be bytes")
    answer_key = require_json_value(answer_key, "sealed.answer_key")
    family_without_identity = dict(family)
    family_without_identity.pop("family_id", None)
    # The reference commitment list is the public index of these commitments;
    # including it would make each reference commitment circular.
    family_without_identity.pop("reference_questions", None)
    task_without_commitment = dict(task)
    task_without_commitment.pop("family_id", None)
    task_without_commitment.pop("answer_key_commitment", None)
    return canonical_json_bytes(
        {
            "schema_version": 1,
            "format": SEALED_VERIFIER_PACKET_FORMAT,
            "family": family_without_identity,
            "task": task_without_commitment,
            "grader": {
                "content": grader_source.decode("utf-8"),
                "digest": sha256_bytes(grader_source),
            },
            "answer_key": answer_key,
        }
    )


def sealed_verifier_packet(
    *,
    family: Mapping[str, Any],
    task: Mapping[str, Any],
    grader_source: bytes,
    answer_key: Any,
    blinding_nonce: bytes,
    publication_binding: Mapping[str, Any] | None = None,
) -> bytes:
    """Build the private packet sent to the verifier boundary.

    The packet retains the full family and task identities for provider-side
    validation.  The lock commitment is computed from
    :func:`sealed_verifier_material`, whose circular public commitment fields
    are excluded from the digest input.
    """

    if not isinstance(grader_source, bytes):
        raise ModelValidationError("sealed verifier grader source must be bytes")
    answer_key = require_json_value(answer_key, "sealed.answer_key")
    blinding_nonce = require_blinding_nonce(blinding_nonce)
    packet = {
        "schema_version": 1,
        "format": SEALED_VERIFIER_PACKET_FORMAT,
        "family": dict(family),
        "task": dict(task),
        "grader": {
            "content": grader_source.decode("utf-8"),
            "digest": sha256_bytes(grader_source),
        },
        "answer_key": answer_key,
        # This is sealed verifier material.  It must never be copied into
        # a public task, family, protocol, receipt, or authored projection.
        "blinding_nonce": blinding_nonce.hex(),
    }
    if publication_binding is not None:
        packet["publication_binding"] = require_json_value(
            dict(publication_binding),
            "sealed.publication_binding",
        )
    return canonical_json_bytes(packet)


def sealed_answer_key_commitment(
    *,
    family: Mapping[str, Any],
    task: Mapping[str, Any],
    grader_source: bytes,
    answer_key: Any,
    blinding_nonce: bytes,
) -> str:
    """Commit to canonical sealed material plus a secret blinding nonce."""

    nonce = require_blinding_nonce(blinding_nonce)
    return sha256_bytes(
        sealed_verifier_material(
            family=family,
            task=task,
            grader_source=grader_source,
            answer_key=answer_key,
        )
        + nonce
    )


def verify_sealed_answer_key_commitment(
    *,
    commitment: str,
    family: Mapping[str, Any],
    task: Mapping[str, Any],
    grader_source: bytes,
    answer_key: Any,
    blinding_nonce: bytes,
) -> bool:
    """Recompute a blinded commitment at the sealed scoring boundary."""

    expected = sealed_answer_key_commitment(
        family=family,
        task=task,
        grader_source=grader_source,
        answer_key=answer_key,
        blinding_nonce=blinding_nonce,
    )
    return hmac.compare_digest(require_sha256(commitment, "commitment"), expected)
