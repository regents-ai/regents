"""Deterministic packaging for the single Prime Verifiers taskset format."""

from __future__ import annotations

import re
import secrets
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from verify_runtime.model import (
    EnvironmentFamily,
    MatchedSelection,
    TaskInstance,
    canonical_json_bytes,
    new_answer_key_blinding_nonce,
    require_blinding_nonce,
    require_exact_keys,
    require_record,
    require_string,
    sealed_verifier_packet,
    sha256_bytes,
    verify_sealed_answer_key_commitment,
)

PRIME_SDK_DISTRIBUTION = "verifiers"
PRIME_SDK_VERSION = "0.2.1"
PRIME_TASKSET_FORMAT = "regent-forge-prime-v1"


@dataclass(frozen=True)
class PrimeTasksetPackage:
    """The agent-visible taskset and the separately sealed verifier packet."""

    agent_taskset: dict
    sealed_verifier_packet: bytes


_VERIFIER_HANDLE_BYTES = 32
_VERIFIER_HANDLE_PATTERN = re.compile(r"[A-Za-z0-9_-]{43}")


def package_taskset(
    *,
    family: EnvironmentFamily,
    selection: MatchedSelection,
    task: TaskInstance,
    side: str,
    skill_bytes: bytes,
    task_input: bytes,
    grader_source: bytes,
    max_spend_usd_cents: int,
    answer_key: Any = None,
    blinding_nonce: bytes | None = None,
    publication_binding: Mapping[str, Any] | None = None,
) -> PrimeTasksetPackage:
    """Package one matched task without exposing verifier material to the agent."""

    if side not in {"baseline", "candidate"}:
        raise ValueError("Prime taskset side must be baseline or candidate")
    if selection.task_id != task.task_id or selection.partition != task.partition:
        raise ValueError("Prime taskset selection does not match its task")
    if task.family_id != family.family_id:
        raise ValueError("Prime taskset family does not match its task")
    if sha256_bytes(task_input) != task.input_digest:
        raise ValueError("Prime task input does not match its canonical digest")
    if sha256_bytes(grader_source) != task.grader_digest:
        raise ValueError("Prime grader does not match its canonical digest")
    if type(max_spend_usd_cents) is not int or max_spend_usd_cents < 0:
        raise ValueError("Prime taskset spend ceiling must be a non-negative integer")

    resolved_nonce = task.answer_key_blinding_nonce if blinding_nonce is None else blinding_nonce
    if resolved_nonce is None:
        if selection.answer_key_commitment is not None:
            raise ValueError("Prime taskset committed answer key is missing its sealed blinding nonce")
        # Uncommitted legacy fixtures have no answer-key claim.  A stable
        # placeholder keeps those public-package tests byte-reproducible; any
        # committed answer must take the high-entropy path above.
        resolved_nonce = bytes(32) if answer_key is None else new_answer_key_blinding_nonce()
    resolved_nonce = require_blinding_nonce(resolved_nonce)

    normalized_binding = None
    if publication_binding is not None:
        binding = require_record(publication_binding, "publication_binding")
        require_exact_keys(
            binding,
            {
                "publication_reference",
                "question_id",
                "publisher_identity",
                "dataset_revision",
                "task_id",
                "task_input_digest",
                "answer_key_commitment",
            },
            "publication_binding",
        )
        normalized_binding = {
            "publication_reference": require_string(binding["publication_reference"], "publication_binding.publication_reference"),
            "question_id": require_string(binding["question_id"], "publication_binding.question_id"),
            "publisher_identity": require_string(binding["publisher_identity"], "publication_binding.publisher_identity"),
            "dataset_revision": require_string(binding["dataset_revision"], "publication_binding.dataset_revision"),
            "task_id": require_string(binding["task_id"], "publication_binding.task_id"),
            "task_input_digest": require_string(binding["task_input_digest"], "publication_binding.task_input_digest"),
            "answer_key_commitment": require_string(binding["answer_key_commitment"], "publication_binding.answer_key_commitment"),
        }
        if normalized_binding["task_id"] != task.task_id:
            raise ValueError("Prime publication binding does not match its task")
        if normalized_binding["task_input_digest"] != task.input_digest:
            raise ValueError("Prime publication binding does not match its task input")
        if normalized_binding["answer_key_commitment"] != selection.answer_key_commitment:
            raise ValueError("Prime publication binding does not match its answer commitment")
    if selection.provenance == "held_out" and selection.answer_key_commitment is not None and normalized_binding is None:
        raise ValueError("Prime held-out committed task requires a publication binding")

    sealed_packet = sealed_verifier_packet(
        family=family.to_dict(),
        task=task.to_dict(),
        grader_source=grader_source,
        answer_key=answer_key,
        blinding_nonce=resolved_nonce,
        publication_binding=normalized_binding,
    )
    if selection.answer_key_commitment is not None:
        if not verify_sealed_answer_key_commitment(
            commitment=selection.answer_key_commitment,
            family=family.to_dict(),
            task=task.to_dict(),
            grader_source=grader_source,
            answer_key=answer_key,
            blinding_nonce=resolved_nonce,
        ):
            raise ValueError("Prime taskset answer-key commitment does not match sealed verifier material")

    agent_taskset = {
        "schema_version": 1,
        "format": PRIME_TASKSET_FORMAT,
        "sdk": {"distribution": PRIME_SDK_DISTRIBUTION, "version": PRIME_SDK_VERSION},
        "family_id": family.family_id,
        "matched_selection": {
            "task_id": selection.task_id,
            "partition": selection.partition,
            "matched_order": selection.matched_order,
            "side": side,
        },
        "task": {
            "identity": {
                "schema_version": task.schema_version,
                "task_id": task.task_id,
                "family_id": task.family_id,
                "slice_id": task.slice_id,
                "partition": task.partition,
                "role_id": task.role_id,
                "input_digest": task.input_digest,
            },
            "input": {"content": task_input.decode("utf-8"), "digest": task.input_digest},
        },
        "intervention": {
            "artifact": "SKILL.md",
            "content": skill_bytes.decode("utf-8"),
            "digest": sha256_bytes(skill_bytes),
        },
        "budget": {"max_spend_usd_cents": max_spend_usd_cents},
    }
    return PrimeTasksetPackage(
        agent_taskset=agent_taskset,
        sealed_verifier_packet=sealed_packet,
    )


def new_verifier_handle() -> str:
    """Return a random, content-independent handle for adapter-memory lookup."""

    verifier_handle = secrets.token_urlsafe(_VERIFIER_HANDLE_BYTES)
    if _VERIFIER_HANDLE_PATTERN.fullmatch(verifier_handle) is None:
        raise RuntimeError("Prime generated an invalid verifier handle")
    return verifier_handle


def taskset_bytes(package: PrimeTasksetPackage) -> bytes:
    """Return the byte-stable agent-visible representation used at rollout."""

    return canonical_json_bytes(package.agent_taskset)
