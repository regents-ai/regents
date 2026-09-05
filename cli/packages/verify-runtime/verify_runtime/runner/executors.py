"""Offline fixture and explicitly configured local Hermes executors.

Hermes stdout is parsed before its exit code. A valid structured terminal
result is authoritative; otherwise a nonzero agent-process exit is
``agent_failure``. Failure to launch the configured process is
``infrastructure_failure``, and parseable-process output with no valid result
is ``invalid``.
"""

from __future__ import annotations

import ast
import hashlib
import re
import shutil
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, BinaryIO, Protocol, Sequence

from verify_runtime.capsule.resolution import ResolvedRuntimeIdentity
from verify_runtime.model import MAX_RECORD_INTEGER, TERMINAL_STATUSES, TerminalStatus, canonical_json_bytes, sha256_bytes, strict_json_loads

INTROSPECTION_TIMEOUT_SECONDS = 10
MAX_CAPTURE_BYTES = 4 * 1024 * 1024
MAX_DETAIL_CHARACTERS = 65_536
MAX_FACTS = 64
MAX_FACT_CHARACTERS = 1_024
MAX_RESULT_INTEGER = MAX_RECORD_INTEGER
_READ_CHUNK_BYTES = 64 * 1024
_ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
_VERSION_LINE = re.compile(
    r"^Hermes Agent v(?P<version>\d+\.\d+\.\d+)"
    r"(?: \((?P<release>\d+(?:\.\d+)*)\))?"
    r"(?: · upstream (?P<upstream>[0-9a-f]{7,64}))?$"
)


class RuntimeResolutionError(RuntimeError):
    """The selected executor could not truthfully report its runtime identity."""


@dataclass(frozen=True)
class ExecutionResult:
    status: TerminalStatus
    score_millis: int | None
    detail: str
    artifact_bytes: bytes
    cost_usd_cents: int
    wall_time_ms: int
    process_exit_code: int | None
    provider_facts: tuple[tuple[str, str], ...] = ()
    runtime_facts: tuple[tuple[str, str], ...] = ()
    tool_facts: tuple[tuple[str, str], ...] = ()
    retry_count: int = 0
    spend_violation: bool = False
    structured_completion: bool = True


@dataclass(frozen=True)
class _ProcessCapture:
    returncode: int
    stdout: bytes
    stderr: bytes
    stdout_overflow: bool
    stderr_overflow: bool


class Executor(Protocol):
    name: str
    supplies_observed_identity: bool

    def resolve_identity(self) -> ResolvedRuntimeIdentity: ...

    def execute(self, *, side: str, task_id: str, workspace: Path, timeout_seconds: int, max_spend_usd_cents: int) -> ExecutionResult: ...


class FixtureExecutor:
    """Deterministic, no-key, no-network executor used by every required check."""

    name = "fixture"
    supplies_observed_identity = True
    _identity_digest = sha256_bytes(b"contract-drift-fixture-executor-v1\n")

    def __init__(self, case: TerminalStatus = "completed") -> None:
        if case not in TERMINAL_STATUSES:
            raise ValueError("unknown fixture case")
        self.case = case

    def resolve_identity(self) -> ResolvedRuntimeIdentity:
        return ResolvedRuntimeIdentity(
            executor=self.name,
            provider="fixture",
            model_identifier="contract-drift-fixture-v1",
            model_version="1",
            behavioral_fingerprint=self._identity_digest,
            model_mutability="content-pinned",
            hermes_version="fixture-runtime-v1",
            hermes_digest=self._identity_digest,
            hermes_mutability="content-pinned",
            tool_components=(("fixture-filesystem", sha256_bytes(b"fixture-filesystem-tool-v1\n"), "content-pinned"),),
            config_components=(("fixture-executor", self._identity_digest, "content-pinned"),),
        )

    def execute(self, *, side: str, task_id: str, workspace: Path, timeout_seconds: int, max_spend_usd_cents: int) -> ExecutionResult:
        del workspace, timeout_seconds
        if self.case == "completed":
            score = 1_000 if side == "candidate" else 0
            detail = "one-SKILL.md contract satisfied" if side == "candidate" else "contract drift reproduced"
        else:
            score = None
            detail = {
                "timeout": "fixture exceeded the task wall cap",
                "invalid": "fixture returned no valid task result",
                "agent_failure": "fixture agent failed while attempting the task",
                "infrastructure_failure": "fixture substrate failed before an agent outcome",
            }[self.case]
        artifact = canonical_json_bytes({"schema_version": 1, "side": side, "task_id": task_id, "status": self.case, "score_millis": score})
        return ExecutionResult(
            status=self.case,
            score_millis=score,
            detail=detail,
            artifact_bytes=artifact,
            cost_usd_cents=0,
            wall_time_ms=1,
            process_exit_code=0 if self.case in {"completed", "invalid"} else None,
            provider_facts=(("reported_provider", "fixture"), ("reported_model", "contract-drift-fixture-v1")),
            runtime_facts=(("reported_wall_time_ms", "1"), ("spend_ceiling_usd_cents", str(max_spend_usd_cents))),
            tool_facts=(("filesystem", "staged"), ("network", "disabled")),
        )


def _read_capped(stream: BinaryIO, chunks: list[bytes], overflow: list[bool]) -> None:
    captured = 0
    while chunk := stream.read(_READ_CHUNK_BYTES):
        remaining = MAX_CAPTURE_BYTES - captured
        if remaining > 0:
            kept = chunk[:remaining]
            chunks.append(kept)
            captured += len(kept)
        if len(chunk) > remaining:
            overflow[0] = True


def _run_capped(
    command: Sequence[str],
    *,
    input_bytes: bytes | None = None,
    cwd: Path | None = None,
    timeout_seconds: int,
) -> _ProcessCapture:
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=cwd,
    )
    if process.stdout is None or process.stderr is None:
        process.kill()
        raise OSError("executor pipes were not created")

    stdout_chunks: list[bytes] = []
    stderr_chunks: list[bytes] = []
    stdout_overflow = [False]
    stderr_overflow = [False]
    readers = (
        threading.Thread(target=_read_capped, args=(process.stdout, stdout_chunks, stdout_overflow), daemon=True),
        threading.Thread(target=_read_capped, args=(process.stderr, stderr_chunks, stderr_overflow), daemon=True),
    )
    for reader in readers:
        reader.start()

    if input_bytes is not None and process.stdin is not None:
        try:
            process.stdin.write(input_bytes)
        except BrokenPipeError:
            pass
        finally:
            process.stdin.close()
    try:
        returncode = process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        for reader in readers:
            reader.join()
        raise
    for reader in readers:
        reader.join()
    return _ProcessCapture(
        returncode=returncode,
        stdout=b"".join(stdout_chunks),
        stderr=b"".join(stderr_chunks),
        stdout_overflow=stdout_overflow[0],
        stderr_overflow=stderr_overflow[0],
    )


def _resolved_binary(command: tuple[str, ...]) -> Path:
    found = shutil.which(command[0])
    if found is None:
        raise RuntimeResolutionError("configured Hermes binary was not found on PATH")
    return Path(found).resolve()


def _run_introspection(command: tuple[str, ...], arguments: tuple[str, ...], purpose: str) -> bytes:
    try:
        completed = _run_capped(
            (*command, *arguments),
            timeout_seconds=INTROSPECTION_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeResolutionError(f"Hermes {purpose} introspection could not run: {error}") from error
    if completed.stdout_overflow or completed.stderr_overflow:
        raise RuntimeResolutionError(f"Hermes {purpose} introspection exceeded the {MAX_CAPTURE_BYTES}-byte output limit")
    if completed.returncode != 0 or not completed.stdout.strip():
        raise RuntimeResolutionError(f"Hermes {purpose} introspection did not return a usable result")
    return completed.stdout


def _hermes_version(stdout: bytes) -> str:
    try:
        version_text = stdout.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise RuntimeResolutionError("Hermes version introspection was malformed") from error
    match = _VERSION_LINE.fullmatch(version_text)
    if match is None:
        raise RuntimeResolutionError("Hermes version introspection was malformed")
    return f"Hermes Agent v{match.group('version')}"


def _effective_model(stdout: bytes) -> tuple[str, str]:
    try:
        text = _ANSI_ESCAPE.sub("", stdout.decode("utf-8"))
    except UnicodeDecodeError as error:
        raise RuntimeResolutionError("Hermes configuration introspection was not UTF-8") from error

    model_lines = [line.split("Model:", 1)[1].strip() for line in text.splitlines() if line.strip().startswith("Model:")]
    if len(model_lines) != 1 or len(model_lines[0]) > MAX_DETAIL_CHARACTERS:
        raise RuntimeResolutionError("Hermes configuration introspection did not report exactly one model record")
    try:
        expression = ast.parse(model_lines[0], mode="eval")
        if not isinstance(expression.body, ast.Dict):
            raise ValueError("model record is not a dictionary")
        keys = [ast.literal_eval(key) for key in expression.body.keys]
        if any(type(key) is not str for key in keys) or len(keys) != len(set(keys)):
            raise ValueError("model record has invalid or duplicate keys")
        model_value: Any = ast.literal_eval(expression)
    except (ValueError, SyntaxError, MemoryError, RecursionError) as error:
        raise RuntimeResolutionError("Hermes configuration introspection reported an unreadable model") from error
    allowed_keys = {"provider", "default", "base_url", "api_mode"}
    if type(model_value) is not dict or set(model_value) - allowed_keys or not {"provider", "default"} <= set(model_value):
        raise RuntimeResolutionError("Hermes configuration introspection reported an invalid model record")
    provider = model_value["provider"]
    model = model_value["default"]
    optional_values = (model_value.get("base_url"), model_value.get("api_mode"))
    if (
        type(provider) is not str
        or not provider
        or len(provider) > MAX_FACT_CHARACTERS
        or type(model) is not str
        or not model
        or len(model) > MAX_FACT_CHARACTERS
        or not _is_utf8(provider)
        or not _is_utf8(model)
        or any(value is not None and (type(value) is not str or len(value) > MAX_FACT_CHARACTERS) for value in optional_values)
    ):
        raise RuntimeResolutionError("Hermes configuration introspection reported invalid model fields")
    return provider, model


def _is_utf8(value: str) -> bool:
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return True


def _sanitize_text(value: str) -> str:
    return value.encode("utf-8", "replace").decode("utf-8")


def _fact_values(value: Any) -> tuple[tuple[str, str], ...] | None:
    if type(value) is not dict or len(value) > MAX_FACTS:
        return None
    facts: list[tuple[str, str]] = []
    for key, item in value.items():
        if type(key) is not str or not key or len(key) > MAX_FACT_CHARACTERS:
            return None
        if type(item) is str:
            fact_value = _sanitize_text(item)
        elif type(item) is int and not isinstance(item, bool) and abs(item) <= MAX_RESULT_INTEGER:
            fact_value = str(item)
        else:
            return None
        if len(fact_value) > MAX_FACT_CHARACTERS:
            return None
        facts.append((_sanitize_text(key), fact_value))
    return tuple(sorted(facts))


def _structured_result(stdout: bytes, process_exit_code: int) -> ExecutionResult | None:
    try:
        response = strict_json_loads(stdout)
    except (UnicodeDecodeError, ValueError, MemoryError, RecursionError):
        return None
    required = {"status", "score_millis", "cost_usd_cents", "detail"}
    if type(response) is not dict:
        return None
    response_keys = set(response)
    if response_keys != required and response_keys != required | {"observed"}:
        return None
    status = response["status"]
    score = response["score_millis"]
    cost = response["cost_usd_cents"]
    detail = response["detail"]
    if type(status) is not str or status not in TERMINAL_STATUSES:
        return None
    if score is not None and (type(score) is not int or isinstance(score, bool) or abs(score) > MAX_RESULT_INTEGER):
        return None
    if type(cost) is not int or isinstance(cost, bool) or not 0 <= cost <= MAX_RESULT_INTEGER:
        return None
    if type(detail) is not str or len(detail) > MAX_DETAIL_CHARACTERS:
        return None

    provider_facts: tuple[tuple[str, str], ...] = ()
    runtime_facts: tuple[tuple[str, str], ...] = ()
    tool_facts: tuple[tuple[str, str], ...] = ()
    retry_count = 0
    if "observed" in response:
        observed = response["observed"]
        if type(observed) is not dict or set(observed) != {"provider", "model", "timings", "retries", "tool_behavior"}:
            return None
        provider = observed["provider"]
        model = observed["model"]
        retries = observed["retries"]
        if (
            type(provider) is not str
            or len(provider) > MAX_FACT_CHARACTERS
            or type(model) is not str
            or len(model) > MAX_FACT_CHARACTERS
            or type(retries) is not int
            or isinstance(retries, bool)
            or not 0 <= retries <= MAX_RESULT_INTEGER
        ):
            return None
        runtime_values = _fact_values(observed["timings"])
        tool_values = _fact_values(observed["tool_behavior"])
        if runtime_values is None or tool_values is None:
            return None
        provider_facts = (("reported_provider", _sanitize_text(provider)), ("reported_model", _sanitize_text(model)))
        runtime_facts = runtime_values
        tool_facts = tool_values
        retry_count = retries
    return ExecutionResult(
        status=status,
        score_millis=score,
        detail=_sanitize_text(detail),
        artifact_bytes=stdout,
        cost_usd_cents=cost,
        wall_time_ms=0,
        process_exit_code=process_exit_code,
        provider_facts=provider_facts,
        runtime_facts=runtime_facts,
        tool_facts=tool_facts,
        retry_count=retry_count,
    )


class HermesExecutor:
    """Launch and interrogate one exact configured command without shell expansion."""

    name = "hermes"
    supplies_observed_identity = True

    def __init__(self, command: tuple[str, ...]) -> None:
        if not command or any(not part for part in command):
            raise ValueError("Hermes execution requires a non-empty command array")
        self.command = command

    def resolve_identity(self) -> ResolvedRuntimeIdentity:
        binary = _resolved_binary(self.command)
        try:
            version = _hermes_version(_run_introspection(self.command, ("--version",), "version"))
            with binary.open("rb") as stream:
                binary_digest = hashlib.file_digest(stream, "sha256").hexdigest()
        except OSError as error:
            raise RuntimeResolutionError(f"Hermes version identity could not be read: {error}") from error
        provider, model = _effective_model(_run_introspection(self.command, ("config", "show"), "configuration"))
        effective_config = canonical_json_bytes({"provider": provider, "model": model})
        configured_command = canonical_json_bytes(list(self.command))
        return ResolvedRuntimeIdentity(
            executor=self.name,
            provider=provider,
            model_identifier=model,
            model_version="not-reported",
            behavioral_fingerprint=None,
            model_mutability="mutable-hosted",
            hermes_version=version,
            hermes_digest=binary_digest,
            hermes_mutability="content-pinned",
            tool_components=(),
            config_components=(
                ("configured-command", sha256_bytes(configured_command), "content-pinned"),
                ("effective-model-configuration", sha256_bytes(effective_config), "mutable-local-configuration"),
            ),
        )

    def execute(self, *, side: str, task_id: str, workspace: Path, timeout_seconds: int, max_spend_usd_cents: int) -> ExecutionResult:
        request = canonical_json_bytes({"schema_version": 1, "side": side, "task_id": task_id, "workspace": str(workspace), "max_spend_usd_cents": max_spend_usd_cents})
        try:
            completed = _run_capped(
                self.command,
                input_bytes=request,
                cwd=workspace,
                timeout_seconds=timeout_seconds,
            )
        except subprocess.TimeoutExpired:
            return ExecutionResult(status="timeout", score_millis=None, detail="Hermes exceeded the locked task wall cap", artifact_bytes=b"", cost_usd_cents=0, wall_time_ms=timeout_seconds * 1_000, process_exit_code=None, structured_completion=False)
        except OSError as error:
            return ExecutionResult(status="infrastructure_failure", score_millis=None, detail=_sanitize_text(f"Hermes launcher or substrate could not start: {error}"), artifact_bytes=b"", cost_usd_cents=0, wall_time_ms=0, process_exit_code=None, structured_completion=False)

        if completed.stdout_overflow:
            return ExecutionResult(status="invalid", score_millis=None, detail=f"Hermes stdout exceeded the {MAX_CAPTURE_BYTES}-byte limit", artifact_bytes=completed.stdout, cost_usd_cents=0, wall_time_ms=0, process_exit_code=completed.returncode, structured_completion=False)
        if completed.stderr_overflow:
            return ExecutionResult(status="infrastructure_failure", score_millis=None, detail=f"Hermes stderr exceeded the {MAX_CAPTURE_BYTES}-byte limit", artifact_bytes=completed.stdout, cost_usd_cents=0, wall_time_ms=0, process_exit_code=completed.returncode, structured_completion=False)
        structured = _structured_result(completed.stdout, completed.returncode)
        if structured is not None:
            return structured
        if completed.returncode != 0:
            detail = completed.stderr.decode("utf-8", "replace").strip() or "Hermes agent process exited without a structured result"
            return ExecutionResult(status="agent_failure", score_millis=None, detail=detail, artifact_bytes=completed.stdout, cost_usd_cents=0, wall_time_ms=0, process_exit_code=completed.returncode, structured_completion=False)
        return ExecutionResult(status="invalid", score_millis=None, detail="Hermes returned no parseable structured result", artifact_bytes=completed.stdout, cost_usd_cents=0, wall_time_ms=0, process_exit_code=completed.returncode, structured_completion=False)


def artifact_record(result: ExecutionResult) -> tuple[tuple[str, str, int], ...]:
    if not result.artifact_bytes:
        return ()
    return (("executor-result.json", sha256_bytes(result.artifact_bytes), len(result.artifact_bytes)),)
