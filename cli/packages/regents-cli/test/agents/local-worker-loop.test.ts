import { describe, expect, it, vi } from "vitest";

import {
  runLocalWorkerLoop,
  type LocalWorkerAssignment,
  type LocalWorkerLoopHandlers,
} from "../../src/agents/bridge/local-worker-loop.js";

const assignment = (overrides: Partial<LocalWorkerAssignment> = {}): LocalWorkerAssignment => ({
  id: "assignment_1",
  work_run_id: "run_1",
  status: "available",
  ...overrides,
});

const onePass = (): (() => boolean) => {
  let remaining = 1;
  return () => remaining-- > 0;
};

describe("local worker loop", () => {
  it("claims assigned work, records updates, uploads proof packets, delegates, and completes", async () => {
    const available = assignment();
    const claimed = assignment({ status: "claimed" });
    const calls: string[] = [];
    const handlers = {
      sleepMs: 0,
      shouldContinue: onePass(),
      heartbeat: vi.fn(async () => {
        calls.push("heartbeat");
      }),
      listAssignments: vi.fn(async () => {
        calls.push("list");
        return [assignment({ id: "busy_assignment", status: "completed" }), available];
      }),
      claimAssignment: vi.fn(async (nextAssignment) => {
        calls.push(`claim:${nextAssignment.id}`);
        return claimed;
      }),
      appendRunEvent: vi.fn(async (_nextAssignment, event) => {
        calls.push(`event:${event.kind}`);
      }),
      uploadArtifact: vi.fn(async (_nextAssignment, artifact) => {
        calls.push(`artifact:${artifact.artifact_type}`);
      }),
      requestDelegation: vi.fn(async (_nextAssignment, request) => {
        calls.push(`delegate:${request.requested_runner_kind}`);
      }),
      releaseAssignment: vi.fn(async () => {
        calls.push("release");
      }),
      completeAssignment: vi.fn(async (nextAssignment) => {
        calls.push(`complete:${nextAssignment.id}`);
      }),
      handleAssignment: vi.fn(async () => ({
        events: [
          {
            kind: "worker_started",
            payload: { stage: "proof" },
            visibility: "operator",
            sensitivity: "normal",
          },
        ],
        artifacts: [
          {
            artifact_type: "proof_packet",
            title: "Review proof",
            body: "The worker finished the requested checks.",
            metadata: { checks: 3 },
            publish_action: "requires_review",
            visibility: "operator",
          },
        ],
        delegation: {
          requested_runner_kind: "codex_exec",
          target_worker_id: "worker_2",
          tasks: [{ title: "Review proof" }],
          required_capabilities: ["code_review"],
        },
        complete: true,
      })),
    } satisfies LocalWorkerLoopHandlers;

    await runLocalWorkerLoop(handlers);

    expect(calls).toEqual([
      "heartbeat",
      "list",
      "claim:assignment_1",
      "event:worker_started",
      "artifact:proof_packet",
      "delegate:codex_exec",
      "complete:assignment_1",
    ]);
    expect(handlers.releaseAssignment).not.toHaveBeenCalled();
    expect(handlers.handleAssignment).toHaveBeenCalledWith(claimed);
    expect(handlers.uploadArtifact).toHaveBeenCalledWith(
      claimed,
      expect.objectContaining({
        artifact_type: "proof_packet",
        metadata: { checks: 3 },
        publish_action: "requires_review",
      }),
    );
  });

  it("records the failure and releases claimed work when handling fails", async () => {
    const claimed = assignment({ status: "claimed" });
    const handlers = {
      sleepMs: 0,
      shouldContinue: onePass(),
      heartbeat: vi.fn(async () => {}),
      listAssignments: vi.fn(async () => [assignment()]),
      claimAssignment: vi.fn(async () => claimed),
      appendRunEvent: vi.fn(async () => {}),
      uploadArtifact: vi.fn(async () => {}),
      requestDelegation: vi.fn(async () => {}),
      releaseAssignment: vi.fn(async () => {}),
      completeAssignment: vi.fn(async () => {}),
      handleAssignment: vi.fn(async () => {
        throw new Error("workspace unavailable");
      }),
    } satisfies LocalWorkerLoopHandlers;

    await runLocalWorkerLoop(handlers);

    expect(handlers.appendRunEvent).toHaveBeenCalledWith(
      claimed,
      expect.objectContaining({
        kind: "local_worker_failed",
        payload: { message: "workspace unavailable" },
      }),
    );
    expect(handlers.releaseAssignment).toHaveBeenCalledWith(claimed);
    expect(handlers.completeAssignment).not.toHaveBeenCalled();
  });
});
