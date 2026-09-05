import { getBooleanFlag, requirePositional, type ParsedCliArgs } from "../../parse.js";
import {
  CLI_PALETTE,
  isHumanTerminal,
  printJsonLine,
  printText,
  renderKeyValuePanel,
} from "../../printer.js";
import {
  parsePollingIntervalSeconds,
  requestJson,
} from "./shared.js";

const displayValue = (value: unknown): string | null => {
  if (typeof value === "string" && value !== "") {
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
};

const renderLaunchJobTimeline = (payload: Record<string, unknown>, jobId: string): string => {
  const job = typeof payload.job === "object" && payload.job !== null
    ? payload.job as Record<string, unknown>
    : {};
  const steps = Array.isArray(payload.events)
    ? payload.events.filter((event): event is Record<string, unknown> => (
        !!event && typeof event === "object" && !Array.isArray(event)
      ))
    : [];

  return [
    renderKeyValuePanel("◆ LAUNCH JOB", [
      { label: "job id", value: displayValue(job.id) ?? jobId, valueColor: CLI_PALETTE.emphasis },
      { label: "status", value: displayValue(job.status) ?? displayValue(payload.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
      ...(displayValue(job.chain_id) ? [{ label: "chain", value: String(job.chain_id) }] : []),
      ...(displayValue(job.updated_at) ? [{ label: "updated", value: String(job.updated_at) }] : []),
    ]),
    ...(steps.length > 0
      ? [
          renderKeyValuePanel("◆ LATEST STEP", [
            { label: "step", value: displayValue(steps.at(-1)?.kind) ?? displayValue(steps.at(-1)?.status) ?? "update" },
            ...(displayValue(steps.at(-1)?.occurred_at) ? [{ label: "time", value: String(steps.at(-1)?.occurred_at) }] : []),
          ]),
        ]
      : []),
  ].join("\n\n");
};

const printLaunchJobWatchPayload = (
  args: ParsedCliArgs,
  payload: Record<string, unknown>,
  jobId: string,
): void => {
  if (isHumanTerminal() && !getBooleanFlag(args, "json")) {
    printText(renderLaunchJobTimeline(payload, jobId));
    return;
  }

  printJsonLine(payload);
};

export async function runAutolaunchJobsWatch(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const jobId = requirePositional(args, 3, "job-id");
  const intervalSeconds = parsePollingIntervalSeconds(args);
  const shouldWatch = getBooleanFlag(args, "watch");

  for (;;) {
    const payload = await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/launch/jobs/${encodeURIComponent(jobId)}`,
      { requireAgentAuth: true, configPath },
    );
    printLaunchJobWatchPayload(args, payload, jobId);

    const status =
      typeof payload.job === "object" && payload.job
        ? (payload.job as Record<string, unknown>).status
        : undefined;
    if (
      !shouldWatch ||
      status === "ready" ||
      status === "failed" ||
      status === "blocked"
    ) {
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, intervalSeconds * 1000));
  }
}
