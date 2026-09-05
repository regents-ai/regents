export interface LocalWorkerAssignment {
  readonly id: string | number;
  readonly work_run_id: string | number;
  readonly status: string;
}

export interface LocalWorkerRunEvent {
  readonly kind: string;
  readonly payload?: Record<string, unknown>;
  readonly visibility?: string;
  readonly sensitivity?: string;
}

export interface LocalWorkerArtifact {
  readonly artifact_type: string;
  readonly title: string;
  readonly body?: string;
  readonly url?: string;
  readonly visibility?: string;
  readonly metadata?: Record<string, unknown>;
  readonly publish_action?: string;
}

export interface LocalWorkerDelegationRequest {
  readonly requested_runner_kind: string;
  readonly execution_surface?: string;
  readonly target_worker_id?: string | number;
  readonly tasks?: readonly Record<string, unknown>[];
  readonly required_capabilities?: readonly string[];
}

export interface LocalWorkerAssignmentResult {
  readonly events?: readonly LocalWorkerRunEvent[];
  readonly artifacts?: readonly LocalWorkerArtifact[];
  readonly delegation?: LocalWorkerDelegationRequest;
  readonly complete?: boolean;
}

export interface LocalWorkerLoopHandlers<TAssignment extends LocalWorkerAssignment = LocalWorkerAssignment> {
  readonly heartbeat: () => Promise<void>;
  readonly listAssignments: () => Promise<readonly TAssignment[]>;
  readonly claimAssignment: (assignment: TAssignment) => Promise<TAssignment | null>;
  readonly appendRunEvent: (assignment: TAssignment, event: LocalWorkerRunEvent) => Promise<void>;
  readonly uploadArtifact: (assignment: TAssignment, artifact: LocalWorkerArtifact) => Promise<void>;
  readonly requestDelegation: (assignment: TAssignment, request: LocalWorkerDelegationRequest) => Promise<void>;
  readonly releaseAssignment: (assignment: TAssignment) => Promise<void>;
  readonly completeAssignment: (assignment: TAssignment) => Promise<void>;
  readonly handleAssignment: (assignment: TAssignment) => Promise<LocalWorkerAssignmentResult | void>;
  readonly sleepMs?: number;
  readonly shouldContinue?: () => boolean;
}

const sleep = async (ms: number): Promise<void> => {
  await new Promise((resolve) => setTimeout(resolve, ms));
};

const shouldTryAssignment = (assignment: LocalWorkerAssignment): boolean =>
  assignment.status === "available" || assignment.status === "leased";

export const runLocalWorkerLoop = async <TAssignment extends LocalWorkerAssignment>(
  handlers: LocalWorkerLoopHandlers<TAssignment>,
): Promise<void> => {
  const sleepMs = handlers.sleepMs ?? 5_000;

  while (handlers.shouldContinue?.() ?? true) {
    await handlers.heartbeat();
    const assignments = await handlers.listAssignments();

    for (const assignment of assignments) {
      if (!shouldTryAssignment(assignment)) {
        continue;
      }

      const claimed = await handlers.claimAssignment(assignment);
      if (!claimed) {
        continue;
      }

      try {
        const result = (await handlers.handleAssignment(claimed)) ?? {};

        for (const event of result.events ?? []) {
          await handlers.appendRunEvent(claimed, event);
        }

        for (const artifact of result.artifacts ?? []) {
          await handlers.uploadArtifact(claimed, artifact);
        }

        if (result.delegation) {
          await handlers.requestDelegation(claimed, result.delegation);
        }

        if (result.complete ?? true) {
          await handlers.completeAssignment(claimed);
        }
      } catch (error) {
        await handlers.appendRunEvent(claimed, {
          kind: "local_worker_failed",
          payload: { message: error instanceof Error ? error.message : "Local worker failed" },
          visibility: "operator",
          sensitivity: "internal",
        });
        await handlers.releaseAssignment(claimed);
      }
    }

    await sleep(sleepMs);
  }
};
