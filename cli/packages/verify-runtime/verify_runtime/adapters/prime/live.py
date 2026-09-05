"""Config-gated live Prime Verifiers boundary.

This module is the only adapter module allowed to import the optional SDK. The
configured rollout factory and verifier boundary run in the same process and are not
an isolation boundary from each other. Sealed packets stay in this process's memory
behind random handles and are destroyed when finalization ends. The rollout factory
call receives only ``(agent_taskset, opaque_handle, rollout_config)``; the call does
not include sealed bytes, ``state_dir``, or another filesystem root.
This module does not spill verifier material to disk; an SDK integration that truly
needs a transient file must use anonymous/unlinked storage and destroy it before
finalization returns.
"""

from __future__ import annotations

import asyncio
import threading
import uuid
from concurrent.futures import CancelledError, Future, TimeoutError as FutureTimeoutError
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Callable

try:
    import verifiers
    from verifiers.v1 import Rollout, Trace, VersionInfo, WireTaskData
    from verifiers.v1.trace import TraceTask
except ModuleNotFoundError as error:
    raise ModuleNotFoundError(
        "Prime live access requires the optional adapters-prime dependency group; "
        "run `uv sync --frozen --group adapters-prime` in packages/verify-runtime"
    ) from error

from verify_runtime.model import canonical_json_bytes, sha256_bytes, strict_json_loads
from verify_runtime.runner import MAX_CAPTURE_BYTES

from .harness import RolloutConfig, require_rollout_config
from .packaging import PRIME_SDK_VERSION, new_verifier_handle

if verifiers.__version__ != PRIME_SDK_VERSION:
    raise RuntimeError(f"Prime live access requires verifiers=={PRIME_SDK_VERSION}, found {verifiers.__version__}")

SDK_ERROR_STATE_MAP = {
    "HarnessError": "harness_error",
    "ProviderError": "provider_error",
    "OverlongPromptError": "task_invalid",
    "SandboxError": "sandbox_error",
    "ToolsetError": "toolset_error",
    "UserError": "user_error",
    "TaskError": "task_invalid",
    "InterceptionError": "interception_error",
    "TunnelError": "tunnel_error",
    "RolloutError": "rollout_error",
}
SDK_PHASE_STATES = {"pending", "boot", "setup", "running", "finalize", "scoring", "done"}


def derive_prime_terminal_state(stop_condition: str | None, error_type: str | None) -> str:
    """Classify only after finalization so scoring errors override an earlier timeout."""

    if error_type is not None:
        return SDK_ERROR_STATE_MAP.get(error_type, "rollout_error")
    if stop_condition == "harness_timeout":
        return "harness_timeout"
    return "completed"


@dataclass
class _LiveRun:
    rollout: Rollout
    future: Future
    taskset: dict[str, Any]
    rollout_config: RolloutConfig
    verifier_handle: str
    cancellation_reason: str | None = None


class LivePrimeClient:
    """Drive adapter-side Rollouts through the configured opaque-handle interface."""

    def __init__(
        self,
        rollout_factory: Callable[[dict[str, Any], str, RolloutConfig], Rollout],
        verifier_boundary: Callable[[bytes, str], str],
    ) -> None:
        self.rollout_factory = rollout_factory
        self.verifier_boundary = verifier_boundary
        self.loop = asyncio.new_event_loop()
        self.thread = threading.Thread(target=self.loop.run_forever, name="regent-prime-verifiers", daemon=True)
        self.thread.start()
        self.runs: dict[str, _LiveRun] = {}
        self.verifier_packets: dict[str, bytearray] = {}

    def prepare_verifier(self, sealed_packet: bytes) -> str:
        if len(sealed_packet) > MAX_CAPTURE_BYTES:
            raise ValueError("Prime sealed verifier packet exceeds the 4MiB boundary")
        packet = strict_json_loads(sealed_packet)
        if type(packet) is not dict or type(packet.get("task")) is not dict:
            raise ValueError("Prime sealed verifier packet is invalid")
        for _ in range(16):
            verifier_handle = new_verifier_handle()
            if verifier_handle not in self.verifier_packets:
                break
        else:
            raise RuntimeError("Prime could not allocate a unique verifier handle")
        self.verifier_packets[verifier_handle] = bytearray(sealed_packet)
        try:
            accepted = self.verifier_boundary(sealed_packet, verifier_handle)
            if accepted != verifier_handle:
                raise ValueError("Prime verifier boundary returned a different opaque handle")
        except Exception:
            self.destroy_verifier(verifier_handle)
            raise
        return verifier_handle

    def destroy_verifier(self, verifier_handle: str) -> None:
        packet = self.verifier_packets.pop(verifier_handle, None)
        if packet is not None:
            packet[:] = b"\x00" * len(packet)

    def start(self, taskset: dict[str, Any], rollout_config: RolloutConfig, verifier_handle: str) -> str:
        if verifier_handle not in self.verifier_packets:
            raise ValueError("Prime rollout referenced an unprepared verifier handle")
        future: Future | None = None
        try:
            validated_config = require_rollout_config(rollout_config)
            rollout = self.rollout_factory(taskset, verifier_handle, validated_config)
            if not isinstance(rollout, Rollout):
                raise TypeError("Prime rollout factory must return verifiers.v1.Rollout")
            run_id = f"prime-{uuid.uuid4().hex}"
            future = asyncio.run_coroutine_threadsafe(rollout.run(), self.loop)
            self.runs[run_id] = _LiveRun(rollout, future, taskset, validated_config, verifier_handle)
        except BaseException:
            try:
                if future is not None:
                    future.cancel()
            finally:
                self.destroy_verifier(verifier_handle)
            raise
        return run_id

    def monitor(self, run_id: str) -> dict[str, Any]:
        run = self._run(run_id)
        if run.future.cancelled():
            state = "deadline_timeout" if run.cancellation_reason == "deadline" else "operator_cancelled"
        elif not run.future.done():
            state = run.rollout.phase.value
        else:
            state = self._state(run.future.result())
        return {"run_id": run_id, "state": state}

    def cancel(self, run_id: str, *, reason: str) -> dict[str, Any]:
        if reason not in {"deadline", "operator"}:
            raise ValueError("Prime cancellation reason must be deadline or operator")
        run = self._run(run_id)
        run.cancellation_reason = reason
        run.future.cancel()
        return {"run_id": run_id, "state": "cancelling"}

    def finalize(self, run_id: str) -> bytes:
        run = self._run(run_id)
        try:
            try:
                trace = run.future.result()
            except CancelledError:
                trace = run.rollout.trace or self._cancelled_trace(run.taskset)
                cancellation_state = "deadline_timeout" if run.cancellation_reason == "deadline" else "operator_cancelled"
                state = cancellation_state if trace.error is None else self._state(trace)
            else:
                state = self._state(trace)
            self._enforce_trace_bound(trace)
            taskset_bytes = canonical_json_bytes(run.taskset)
            identity = run.rollout_config.to_dict()
            usage = trace.usage
            cost = Decimal(str(usage.cost if usage is not None and usage.cost is not None else 0)) * 100
            if cost != cost.to_integral_value():
                raise ValueError("Prime reported cost cannot be represented losslessly in cents")
            artifacts = trace.info.get("artifacts", [])
            record = {
                "schema_version": 1,
                "run_id": run_id,
                "state": state,
                "identity": {
                    "provider": identity["provider"],
                    "model": identity["model"],
                    "hermes_version": identity["hermes_version"],
                    "hermes_digest": identity["hermes_digest"],
                },
                "task": strict_json_loads(bytes(self.verifier_packets[run.verifier_handle]))["task"],
                "taskset": {"format": run.taskset["format"], "digest": sha256_bytes(taskset_bytes)},
                "trace": trace.to_record(),
                "artifacts": artifacts,
                "cost": {"usd_cents": int(cost)},
                "retry_count": max(0, len(trace.errors) - 1),
            }
            payload = canonical_json_bytes(record)
            if len(payload) > MAX_CAPTURE_BYTES:
                raise ValueError("Prime SDK record exceeds the 4MiB ingestion boundary")
            return payload
        finally:
            self.runs.pop(run_id, None)
            self.destroy_verifier(run.verifier_handle)

    def close(self) -> None:
        futures = [run.future for run in self.runs.values()]
        for future in futures:
            future.cancel()
        for future in futures:
            try:
                future.result(timeout=5)
            except (CancelledError, FutureTimeoutError):
                pass
            except Exception:
                pass
        self.loop.call_soon_threadsafe(self.loop.stop)
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            raise RuntimeError("Prime event loop did not stop cleanly")
        self.runs.clear()
        for verifier_handle in tuple(self.verifier_packets):
            self.destroy_verifier(verifier_handle)
        self.loop.close()

    def _run(self, run_id: str) -> _LiveRun:
        try:
            return self.runs[run_id]
        except KeyError as error:
            raise KeyError(f"Prime run not found: {run_id}") from error

    @staticmethod
    def _state(trace: Trace) -> str:
        return derive_prime_terminal_state(
            trace.stop_condition,
            None if trace.error is None else trace.error.type,
        )

    @staticmethod
    def _cancelled_trace(taskset: dict[str, Any]) -> Trace:
        data = WireTaskData(idx=0, prompt=None, task_id=taskset["task"]["identity"]["task_id"])
        trace = Trace(task=TraceTask(type="CancelledTask", data=data), verifiers=VersionInfo(version=PRIME_SDK_VERSION, commit=None), is_completed=True, stop_condition="cancelled")
        return trace

    @staticmethod
    def _enforce_trace_bound(trace: Trace) -> None:
        """Reject an oversized SDK object before calling its record converter."""

        remaining = MAX_CAPTURE_BYTES
        pending: list[Any] = [trace]
        seen: set[int] = set()
        while pending:
            value = pending.pop()
            if isinstance(value, dict | list | tuple) or hasattr(value, "__dict__"):
                identity = id(value)
                if identity in seen:
                    continue
                seen.add(identity)
            remaining -= 8
            if value is None or isinstance(value, bool | int | float):
                remaining -= 16
            elif isinstance(value, str):
                remaining -= 2 + 6 * len(value)
            elif isinstance(value, bytes):
                remaining -= 2 + 4 * ((len(value) + 2) // 3)
            elif isinstance(value, dict):
                pending.extend(value.keys())
                pending.extend(value.values())
            elif isinstance(value, list | tuple):
                pending.extend(value)
            elif hasattr(value, "__dict__"):
                pending.append(vars(value))
            else:
                remaining -= len(str(value).encode("utf-8"))
            if remaining < 0:
                raise ValueError("Prime SDK trace exceeds the 4MiB ingestion boundary")
