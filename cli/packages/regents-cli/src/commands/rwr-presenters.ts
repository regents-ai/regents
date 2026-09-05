import {
  CLI_PALETTE,
  isHumanTerminal,
  printJson,
  printJsonLine,
  printText,
  renderKeyValuePanel,
  renderPanel,
  renderTablePanel,
  tone,
  type KeyValueRow,
  type TableRow,
} from "../printer.js";
import { getBooleanFlag, getFlag, type ParsedCliArgs } from "../parse.js";

type JsonObject = Record<string, unknown>;

type RwrPayload = {
  readonly ok: true;
  readonly command: string;
  readonly origin: string;
  readonly result: JsonObject;
};

type RwrOpenClawPayload = RwrPayload & {
  readonly openclaw: {
    readonly skillFile: string | null;
  };
};

const asRecord = (value: unknown, label: string): JsonObject => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Regent returned ${label} that this command cannot show.`);
  }

  return value as JsonObject;
};

const optionalString = (value: unknown): string | null =>
  typeof value === "string" && value !== "" ? value : null;

const displayValue = (value: unknown): string | null => {
  if (typeof value === "string" && value !== "") {
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
};

const displayLabel = (value: unknown): string | null => {
  const raw = displayValue(value);
  return raw ? raw.replace(/_/gu, " ") : null;
};

const eventKey = (event: JsonObject): string =>
  [displayValue(event.id), displayValue(event.sequence), displayValue(event.occurred_at), displayValue(event.kind)]
    .filter(Boolean)
    .join(":");

const idValue = (record: JsonObject): string => {
  const id = displayValue(record.id);
  if (!id) {
    throw new Error("Regent returned a response without a required id.");
  }
  return id;
};

const commandValue = (command: string): string => tone(command, CLI_PALETTE.emphasis, true);

const nextPanel = (lines: readonly string[]): string =>
  renderPanel("◆ NEXT STEP", [...lines], {
    borderColor: CLI_PALETTE.chrome,
    titleColor: CLI_PALETTE.title,
  });

const printRwrPayload = (
  args: ParsedCliArgs,
  payload: RwrPayload,
  renderHuman: () => string,
): void => {
  if (isHumanTerminal() && !getBooleanFlag(args, "json")) {
    printText(renderHuman());
    return;
  }

  printJson(payload);
};

const workItemFromPayload = (payload: RwrPayload): JsonObject =>
  asRecord(payload.result.work_item, "a work item");

const runFromPayload = (payload: RwrPayload): JsonObject => asRecord(payload.result.run, "a work run");

const workerFromPayload = (payload: RwrPayload): JsonObject =>
  asRecord(payload.result.worker, "a worker");

const relationshipFromPayload = (payload: RwrPayload): JsonObject =>
  asRecord(payload.result.relationship, "a work link");

const runtimeFromPayload = (payload: RwrPayload): JsonObject =>
  asRecord(payload.result.runtime, "a runtime");

const checkpointFromPayload = (payload: RwrPayload): JsonObject =>
  asRecord(payload.result.checkpoint, "a checkpoint");

const runtimeRows = (runtime: JsonObject): KeyValueRow[] => [
  { label: "runtime id", value: idValue(runtime), valueColor: CLI_PALETTE.emphasis },
  { label: "name", value: displayValue(runtime.name) ?? "unnamed runtime" },
  { label: "status", value: displayLabel(runtime.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
  { label: "runner", value: displayLabel(runtime.runner_kind) ?? "unknown" },
  { label: "runs on", value: displayLabel(runtime.execution_surface) ?? "unknown" },
  { label: "billing", value: displayLabel(runtime.billing_mode) ?? "unknown" },
  ...(displayValue(runtime.platform_agent_id)
    ? [{ label: "agent id", value: String(runtime.platform_agent_id), valueColor: CLI_PALETTE.emphasis }]
    : []),
];

const checkpointRows = (checkpoint: JsonObject): KeyValueRow[] => [
  { label: "checkpoint id", value: idValue(checkpoint), valueColor: CLI_PALETTE.emphasis },
  { label: "reference", value: displayValue(checkpoint.checkpoint_ref) ?? "unnamed checkpoint" },
  { label: "status", value: displayLabel(checkpoint.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
  { label: "saved at", value: displayValue(checkpoint.captured_at) ?? displayValue(checkpoint.created_at) ?? "not saved yet" },
  { label: "protected", value: displayValue(checkpoint.protected) ?? "false" },
];

const workRows = (workItem: JsonObject): KeyValueRow[] => [
  { label: "work id", value: idValue(workItem), valueColor: CLI_PALETTE.emphasis },
  { label: "title", value: displayValue(workItem.title) ?? "untitled" },
  { label: "status", value: displayValue(workItem.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
  { label: "priority", value: displayValue(workItem.priority) ?? "normal" },
  ...(displayValue(workItem.desired_runner_kind)
    ? [{ label: "runs with", value: String(workItem.desired_runner_kind) }]
    : []),
  ...(displayValue(workItem.assigned_worker_id)
    ? [{ label: "assigned worker", value: String(workItem.assigned_worker_id), valueColor: CLI_PALETTE.emphasis }]
    : []),
];

const runRows = (run: JsonObject): KeyValueRow[] => [
  { label: "run id", value: idValue(run), valueColor: CLI_PALETTE.emphasis },
  { label: "work id", value: displayValue(run.work_item_id) ?? "unknown" },
  { label: "status", value: displayValue(run.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
  { label: "worker", value: displayValue(run.worker_id) ?? "not assigned" },
  { label: "runs with", value: displayValue(run.runner_kind) ?? "unknown" },
];

const workerRows = (worker: JsonObject): KeyValueRow[] => [
  { label: "worker id", value: idValue(worker), valueColor: CLI_PALETTE.emphasis },
  { label: "name", value: displayValue(worker.name) ?? "unnamed worker" },
  { label: "role", value: displayValue(worker.worker_role) ?? "unknown" },
  { label: "status", value: displayValue(worker.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
  { label: "worker type", value: displayValue(worker.agent_kind) ?? "unknown" },
  ...(displayValue(worker.agent_profile_id)
    ? [{ label: "agent id", value: String(worker.agent_profile_id) }]
    : []),
];

const workerTableRows = (workers: readonly JsonObject[]): TableRow[] =>
  workers.map((worker) => ({
    cells: [
      idValue(worker),
      displayValue(worker.name) ?? "unnamed worker",
      displayValue(worker.worker_role) ?? "unknown",
      displayValue(worker.agent_kind) ?? "unknown",
      displayValue(worker.status) ?? "unknown",
      displayValue(worker.last_heartbeat_at) ?? "not seen",
    ],
    colors: [
      CLI_PALETTE.emphasis,
      CLI_PALETTE.primary,
      CLI_PALETTE.primary,
      CLI_PALETTE.primary,
      CLI_PALETTE.emphasis,
      CLI_PALETTE.secondary,
    ],
  }));

export const printWorkCreateResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const workItem = workItemFromPayload(payload);
    const workId = idValue(workItem);
    const regentId = displayValue(workItem.regent_id) ?? "<id>";
    const runner = displayValue(workItem.desired_runner_kind) ?? "<runner>";

    return [
      renderKeyValuePanel("◆ WORK CREATED", workRows(workItem), {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([
        `Start it with ${commandValue(`regents work run ${workId} --regent-id ${regentId} --runner ${runner}`)}.`,
      ]),
    ].join("\n\n");
  });

export const printWorkListResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const regentId = displayValue(payload.result.regent_id) ?? "<id>";
    const workItems = Array.isArray(payload.result.work_items)
      ? payload.result.work_items.map((item) => asRecord(item, "a work item"))
      : [];

    if (workItems.length === 0) {
      return [
        renderKeyValuePanel("◆ REGENT WORK", [
          { label: "regent", value: regentId, valueColor: CLI_PALETTE.emphasis },
          { label: "open work", value: "0" },
        ]),
        nextPanel([`Create work with ${commandValue(`regents work create --regent-id ${regentId} --title "<title>"`)}.`]),
      ].join("\n\n");
    }

    return [
      renderTablePanel("◆ REGENT WORK", [
        { header: "id", color: CLI_PALETTE.secondary },
        { header: "status", color: CLI_PALETTE.secondary },
        { header: "title", color: CLI_PALETTE.secondary },
        { header: "worker", color: CLI_PALETTE.secondary },
        { header: "updated", color: CLI_PALETTE.secondary },
      ], workItems.map((item) => ({
        cells: [
          idValue(item),
          displayValue(item.status) ?? "unknown",
          displayValue(item.title) ?? "untitled",
          displayValue(item.assigned_worker_id) ?? "not assigned",
          displayValue(item.updated_at) ?? "",
        ],
        colors: [
          CLI_PALETTE.emphasis,
          CLI_PALETTE.emphasis,
          CLI_PALETTE.primary,
          CLI_PALETTE.primary,
          CLI_PALETTE.secondary,
        ],
      }))),
      nextPanel([`Start one with ${commandValue(`regents work run <work-id> --regent-id ${regentId} --runner <runner>`)}.`]),
    ].join("\n\n");
  });

export const printWorkShowResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const workItem = workItemFromPayload(payload);
    const workId = idValue(workItem);
    const regentId = displayValue(workItem.regent_id) ?? "<id>";

    return [
      renderKeyValuePanel("◆ WORK ITEM", workRows(workItem), {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([`Start it with ${commandValue(`regents work run ${workId} --regent-id ${regentId} --runner <runner>`)}.`]),
    ].join("\n\n");
  });

export const printWorkRunResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const run = runFromPayload(payload);
    const runId = idValue(run);
    const regentId = displayValue(run.regent_id) ?? "<id>";

    return [
      renderKeyValuePanel("◆ WORK STARTED", runRows(run), {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([`Check progress with ${commandValue(`regents work watch ${runId} --regent-id ${regentId}`)}.`]),
    ].join("\n\n");
  });

export const printWorkWatchResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printWorkWatchTimelineResult(args, payload);

export const printWorkWatchTimelineResult = (
  args: ParsedCliArgs,
  payload: RwrPayload,
  options: { readonly seenEventKeys?: Set<string> } = {},
): void => {
  if (!isHumanTerminal() || getBooleanFlag(args, "json")) {
    printJsonLine(payload);
    return;
  }

  printText(
    (() => {
    const runId = displayValue(payload.result.run_id) ?? "<run-id>";
    const regentId = getFlag(args, "regent-id") ?? "<id>";
    const allEvents = Array.isArray(payload.result.events)
      ? payload.result.events.map((event) => asRecord(event, "a run update"))
      : [];
    const seenEventKeys = options.seenEventKeys;
    const events = seenEventKeys
      ? allEvents.filter((event) => {
          const key = eventKey(event);
          if (key && seenEventKeys.has(key)) {
            return false;
          }
          if (key) {
            seenEventKeys.add(key);
          }
          return true;
        })
      : allEvents;

    if (events.length === 0) {
      return [
        renderKeyValuePanel("◆ RUN UPDATES", [
          { label: "run id", value: runId, valueColor: CLI_PALETTE.emphasis },
          { label: "new updates", value: "0" },
        ]),
        nextPanel([`Check again with ${commandValue(`regents work watch ${runId} --regent-id ${regentId}`)}.`]),
      ].join("\n\n");
    }

    return [
      renderKeyValuePanel("◆ RUN UPDATES", [
        { label: "run id", value: runId, valueColor: CLI_PALETTE.emphasis },
        { label: "new updates", value: String(events.length), valueColor: CLI_PALETTE.emphasis },
        { label: "latest", value: displayValue(events.at(-1)?.occurred_at) ?? "unknown" },
      ]),
      renderTablePanel("◆ UPDATE TIMELINE", [
        { header: "#", align: "right", color: CLI_PALETTE.secondary },
        { header: "update", color: CLI_PALETTE.secondary },
        { header: "actor", color: CLI_PALETTE.secondary },
        { header: "time", color: CLI_PALETTE.secondary },
      ], events.map((event) => ({
        cells: [
          displayValue(event.sequence) ?? idValue(event),
          displayValue(event.kind) ?? "update",
          [optionalString(event.actor_kind), optionalString(event.actor_id)].filter(Boolean).join(":") || "Regent",
          displayValue(event.occurred_at) ?? "",
        ],
        colors: [
          CLI_PALETTE.emphasis,
          CLI_PALETTE.primary,
          CLI_PALETTE.primary,
          CLI_PALETTE.secondary,
        ],
      }))),
    ].join("\n\n");
    })(),
  );
};

export const printAgentConnectHostedHermesResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const runtime = runtimeFromPayload(payload);
    const health = asRecord(payload.result.health, "runtime health");
    const services = Array.isArray(payload.result.services) ? (payload.result.services as JsonObject[]) : [];
    const regentId = displayValue(payload.result.regent_id) ?? getFlag(args, "regent-id") ?? "<id>";
    const runtimeId = idValue(runtime);

    return [
      renderKeyValuePanel("◆ HOSTED HERMES", [
        ...runtimeRows(runtime),
        { label: "available", value: health.available === true ? "yes" : "no" },
        { label: "health", value: displayLabel(health.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
        { label: "metering", value: displayLabel(health.metering_status) ?? "unknown" },
      ], {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      renderTablePanel("◆ HOSTED SERVICES", [
        { header: "id", color: CLI_PALETTE.secondary },
        { header: "name", color: CLI_PALETTE.secondary },
        { header: "kind", color: CLI_PALETTE.secondary },
        { header: "status", color: CLI_PALETTE.secondary },
        { header: "endpoint", color: CLI_PALETTE.secondary },
      ], services.map((service) => ({
        cells: [
          idValue(service),
          displayValue(service.name) ?? "unnamed service",
          displayLabel(service.service_kind) ?? "service",
          displayLabel(service.status) ?? "unknown",
          displayValue(service.endpoint_url) ?? "not published",
        ],
        colors: [
          CLI_PALETTE.emphasis,
          CLI_PALETTE.primary,
          CLI_PALETTE.primary,
          CLI_PALETTE.emphasis,
          CLI_PALETTE.secondary,
        ],
      }))),
      nextPanel([
        `Refresh health with ${commandValue(`regents runtime health ${runtimeId} --regent-id ${regentId}`)}.`,
        "Interactive hosted Hermes chat is not available from this command.",
      ]),
    ].join("\n\n");
  });

export const printAgentChatResult = (args: ParsedCliArgs, payload: RwrPayload): void => {
  if (isHumanTerminal() && !getBooleanFlag(args, "json")) {
    printText(displayValue(payload.result.reply) ?? "");
    return;
  }

  printJson(payload);
};

export const printRuntimeResult = (
  args: ParsedCliArgs,
  payload: RwrPayload,
  title: "created" | "status" | "paused" | "resumed",
): void =>
  printRwrPayload(args, payload, () => {
    const runtime = runtimeFromPayload(payload);
    const runtimeId = idValue(runtime);
    const regentId = displayValue(runtime.regent_id) ?? getFlag(args, "regent-id") ?? "<id>";
    const titleByState = {
      created: "◆ RUNTIME CREATED",
      status: "◆ RUNTIME STATUS",
      paused: "◆ RUNTIME PAUSED",
      resumed: "◆ RUNTIME RESUMED",
    } satisfies Record<typeof title, string>;

    return [
      renderKeyValuePanel(titleByState[title], runtimeRows(runtime), {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([`Check health with ${commandValue(`regents runtime health ${runtimeId} --regent-id ${regentId}`)}.`]),
    ].join("\n\n");
  });

export const printRuntimeCheckpointResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const checkpoint = checkpointFromPayload(payload);
    const runtimeId = args.positionals[2] ?? displayValue(checkpoint.runtime_profile_id) ?? "<runtime-id>";
    const regentId = displayValue(checkpoint.regent_id) ?? getFlag(args, "regent-id") ?? "<id>";

    return [
      renderKeyValuePanel("◆ CHECKPOINT SAVED", checkpointRows(checkpoint), {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([
        `Restore it with ${commandValue(`regents runtime restore ${runtimeId} --regent-id ${regentId} --checkpoint-id ${idValue(checkpoint)}`)}.`,
      ]),
    ].join("\n\n");
  });

export const printRuntimeRestoreResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const runtime = runtimeFromPayload(payload);
    const checkpoint = checkpointFromPayload(payload);
    const restore = asRecord(payload.result.restore, "a restore result");
    const runtimeId = idValue(runtime);
    const regentId = displayValue(runtime.regent_id) ?? getFlag(args, "regent-id") ?? "<id>";

    return [
      renderKeyValuePanel("◆ RESTORE ACCEPTED", [
        { label: "runtime id", value: runtimeId, valueColor: CLI_PALETTE.emphasis },
        { label: "runtime", value: displayValue(runtime.name) ?? "unnamed runtime" },
        { label: "checkpoint id", value: idValue(checkpoint), valueColor: CLI_PALETTE.emphasis },
        { label: "checkpoint", value: displayValue(checkpoint.checkpoint_ref) ?? "unnamed checkpoint" },
        { label: "status", value: displayLabel(restore.status) ?? "accepted", valueColor: CLI_PALETTE.emphasis },
      ], {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([`Check health with ${commandValue(`regents runtime health ${runtimeId} --regent-id ${regentId}`)}.`]),
    ].join("\n\n");
  });

export const printRuntimeServicesResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const regentId = displayValue(payload.result.regent_id) ?? getFlag(args, "regent-id") ?? "<id>";
    const runtimeId = displayValue(payload.result.runtime_id) ?? args.positionals[2] ?? "<runtime-id>";
    const services = Array.isArray(payload.result.services)
      ? payload.result.services.map((service) => asRecord(service, "a runtime service"))
      : [];

    if (services.length === 0) {
      return [
        renderKeyValuePanel("◆ RUNTIME SERVICES", [
          { label: "runtime id", value: runtimeId, valueColor: CLI_PALETTE.emphasis },
          { label: "services", value: "0" },
        ]),
        nextPanel([`Check health with ${commandValue(`regents runtime health ${runtimeId} --regent-id ${regentId}`)}.`]),
      ].join("\n\n");
    }

    return [
      renderTablePanel("◆ RUNTIME SERVICES", [
        { header: "id", color: CLI_PALETTE.secondary },
        { header: "name", color: CLI_PALETTE.secondary },
        { header: "kind", color: CLI_PALETTE.secondary },
        { header: "status", color: CLI_PALETTE.secondary },
        { header: "endpoint", color: CLI_PALETTE.secondary },
      ], services.map((service) => ({
        cells: [
          idValue(service),
          displayValue(service.name) ?? "unnamed service",
          displayLabel(service.service_kind) ?? "service",
          displayLabel(service.status) ?? "unknown",
          displayValue(service.endpoint_url) ?? "not published",
        ],
        colors: [
          CLI_PALETTE.emphasis,
          CLI_PALETTE.primary,
          CLI_PALETTE.primary,
          CLI_PALETTE.emphasis,
          CLI_PALETTE.secondary,
        ],
      }))),
      nextPanel([`Check health with ${commandValue(`regents runtime health ${runtimeId} --regent-id ${regentId}`)}.`]),
    ].join("\n\n");
  });

export const printRuntimeHealthResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const health = asRecord(payload.result.health, "runtime health");
    const controlRoom = asRecord(health.control_room, "control room");
    const gbrain = asRecord(controlRoom.gbrain, "gbrain");
    const regentId = displayValue(payload.result.regent_id) ?? getFlag(args, "regent-id") ?? "<id>";
    const runtimeId = displayValue(payload.result.runtime_id) ?? args.positionals[2] ?? "<runtime-id>";

    return [
      renderKeyValuePanel("◆ RUNTIME HEALTH", [
        { label: "runtime id", value: runtimeId, valueColor: CLI_PALETTE.emphasis },
        { label: "status", value: displayLabel(health.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
        { label: "available", value: health.available === true ? "yes" : "no" },
        { label: "metering", value: displayLabel(health.metering_status) ?? "unknown" },
      ], {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      renderKeyValuePanel("◆ HERMES CONTROL ROOM", [
        { label: "status", value: displayLabel(controlRoom.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
        { label: "one Sprite", value: controlRoom.one_sprite === true ? "yes" : "no" },
        { label: "Sprite runtime", value: displayValue(controlRoom.sprite_runtime_id) ?? "none" },
        { label: "Workspace service", value: displayValue(controlRoom.workspace_service_name) ?? "none" },
        { label: "bridge service", value: displayValue(controlRoom.bridge_service_name) ?? "none" },
        { label: "control room", value: displayValue(controlRoom.path) ?? "none" },
        { label: "GBrain", value: displayLabel(gbrain.status) ?? "unknown" },
        { label: "GBrain brain", value: displayValue(gbrain.brain_repo_path) ?? "none" },
      ], {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([`List services with ${commandValue(`regents runtime services ${runtimeId} --regent-id ${regentId}`)}.`]),
    ].join("\n\n");
  });

export const printAgentConnectOpenClawResult = (args: ParsedCliArgs, payload: RwrOpenClawPayload): void =>
  printRwrPayload(args, payload, () => {
    const worker = workerFromPayload(payload);
    const workerId = idValue(worker);
    const regentId = displayValue(worker.regent_id) ?? "<id>";

    return [
      renderKeyValuePanel("◆ OPENCLAW CONNECTED", [
        ...workerRows(worker),
        ...(payload.openclaw.skillFile
          ? [{ label: "skill file", value: payload.openclaw.skillFile, valueColor: CLI_PALETTE.emphasis }]
          : []),
      ], {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([
        payload.openclaw.skillFile
          ? `OpenClaw can now use ${tone("regents-work", CLI_PALETTE.emphasis, true)} from ${payload.openclaw.skillFile}.`
          : "OpenClaw was connected. No local skill file was written.",
        `Start work with ${commandValue(`regents work run <work-id> --regent-id ${regentId} --runner openclaw_local_executor --worker-id ${workerId}`)}.`,
      ]),
    ].join("\n\n");
  });

export const printAgentLinkResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const relationship = relationshipFromPayload(payload);
    const regentId = displayValue(relationship.regent_id) ?? "<id>";
    const manager =
      displayValue(relationship.source_agent_profile_id) ?? displayValue(relationship.source_worker_id) ?? "<manager>";
    const executor =
      displayValue(relationship.target_agent_profile_id) ?? displayValue(relationship.target_worker_id) ?? "<worker>";

    return [
      renderKeyValuePanel("◆ WORK LINK READY", [
        { label: "link id", value: idValue(relationship), valueColor: CLI_PALETTE.emphasis },
        { label: "manager", value: manager },
        { label: "worker", value: executor },
        { label: "link type", value: displayValue(relationship.relationship_kind) ?? "unknown" },
        { label: "status", value: displayValue(relationship.status) ?? "unknown", valueColor: CLI_PALETTE.emphasis },
      ], {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      }),
      nextPanel([`List assignable workers with ${commandValue(`regents agent execution-pool --regent-id ${regentId} --manager ${manager}`)}.`]),
    ].join("\n\n");
  });

export const printAgentExecutionPoolResult = (args: ParsedCliArgs, payload: RwrPayload): void =>
  printRwrPayload(args, payload, () => {
    const regentId = displayValue(payload.result.regent_id) ?? "<id>";
    const workers = Array.isArray(payload.result.workers)
      ? payload.result.workers.map((worker) => asRecord(worker, "a worker"))
      : [];

    if (workers.length === 0) {
      return [
        renderKeyValuePanel("◆ ASSIGNABLE WORKERS", [
          { label: "regent", value: regentId, valueColor: CLI_PALETTE.emphasis },
          { label: "workers", value: "0" },
        ]),
        nextPanel([`Connect a worker with ${commandValue(`regents agent connect openclaw --regent-id ${regentId} --role executor`)}.`]),
      ].join("\n\n");
    }

    return [
      renderKeyValuePanel("◆ ASSIGNABLE WORKERS", [
        { label: "regent", value: regentId, valueColor: CLI_PALETTE.emphasis },
        { label: "workers", value: String(workers.length), valueColor: CLI_PALETTE.emphasis },
      ]),
      renderTablePanel("◆ WORKER LIST", [
        { header: "id", color: CLI_PALETTE.secondary },
        { header: "name", color: CLI_PALETTE.secondary },
        { header: "role", color: CLI_PALETTE.secondary },
        { header: "worker type", color: CLI_PALETTE.secondary },
        { header: "status", color: CLI_PALETTE.secondary },
        { header: "last seen", color: CLI_PALETTE.secondary },
      ], workerTableRows(workers)),
      nextPanel([`Start work with ${commandValue(`regents work run <work-id> --regent-id ${regentId} --runner <runner> --worker-id <worker-id>`)}.`]),
    ].join("\n\n");
  });
