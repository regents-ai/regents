import fs from "node:fs";
import path from "node:path";

import { daemonCall } from "../daemon-client.js";
import {
  callJsonRpc,
  coinbaseStatus,
  defaultConfigPath,
  expandHome,
  loadConfig,
  runScopedDoctor,
  SessionStore,
  StateStore,
  writeInitialConfigIfMissing,
} from "../internal-runtime/index.js";
import { readIdentityReceipt, receiptMatchesRequest } from "../internal-runtime/identity/cache.js";
import { identityNetworkForChainId } from "../internal-runtime/identity/shared.js";
import { pluginStatus } from "../internal-runtime/plugin-bridge.js";
import type { RegentConfig } from "../internal-types/index.js";
import { getBooleanFlag, getFlag, type ParsedCliArgs } from "../parse.js";
import {
  CLI_PALETTE,
  isHumanTerminal,
  printJson,
  printText,
  renderBanner,
  renderKeyValuePanel,
  renderPanel,
  renderTablePanel,
} from "../printer.js";
import { loadResolvedPlatformSession, requestPlatformSessionJson } from "./platform.js";

const ensureDirectories = (paths: readonly string[]): void => {
  for (const targetPath of paths) {
    fs.mkdirSync(targetPath, { recursive: true });
  }
};

const configPathFor = (args: ParsedCliArgs, configPath?: string): string =>
  expandHome(configPath ?? getFlag(args, "config") ?? defaultConfigPath());

const component = (
  name: string,
  status: "ready" | "waiting" | "blocked",
  detail?: string,
): { name: string; status: "ready" | "waiting" | "blocked"; detail?: string } => ({
  name,
  status,
  ...(detail ? { detail } : {}),
});

const statusColor = (status: string): string =>
  status === "ready" ? CLI_PALETTE.emphasis : status === "blocked" ? CLI_PALETTE.error : CLI_PALETTE.accent;

const printOperatorPayload = (
  payload: Record<string, unknown>,
  renderHuman: () => string,
): void => {
  if (isHumanTerminal()) {
    printText(renderHuman());
    return;
  }

  printJson(payload);
};

const readCurrentIdentityReceipt = (
  config: RegentConfig,
  input: { walletAddress?: string },
) => {
  const receipt = readIdentityReceipt();
  if (!receipt || !input.walletAddress) {
    return null;
  }

  try {
    const network = identityNetworkForChainId(config.auth.defaultChainId);
    return receipt.provider === "coinbase-cdp" &&
      receiptMatchesRequest({
        receipt,
        network,
        regentBaseUrl: config.services.siwa.baseUrl,
        walletHint: input.walletAddress,
      })
      ? receipt
      : null;
  } catch {
    return null;
  }
};

export interface OperatorInitDeps {
  callJsonRpc: typeof callJsonRpc;
  runScopedDoctor: typeof runScopedDoctor;
  pluginStatus: typeof pluginStatus;
}

export const operatorInitDeps: OperatorInitDeps = {
  callJsonRpc,
  runScopedDoctor,
  pluginStatus,
};

const runtimePingReady = async (socketPath: string): Promise<boolean> => {
  try {
    await operatorInitDeps.callJsonRpc(socketPath, "runtime.ping");
    return true;
  } catch {
    return false;
  }
};

const runtimeReadiness = async (
  socketPath: string,
): Promise<{ ready: boolean; socketExists: boolean }> => {
  const socketExists = fs.existsSync(socketPath);
  return {
    ready: await runtimePingReady(socketPath),
    socketExists,
  };
};

export async function runOperatorInit(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const resolvedConfigPath = configPathFor(args, configPath);
  const configCreated = writeInitialConfigIfMissing(resolvedConfigPath);
  const config = loadConfig(resolvedConfigPath);
  const directories = {
    state: config.runtime.stateDir,
    socket: path.dirname(config.runtime.socketPath),
    wallet: path.dirname(config.wallet.keystorePath),
    gossipsub: path.dirname(config.gossipsub.peerIdPath),
  };

  ensureDirectories(Object.values(directories));

  const plugin = operatorInitDeps.pluginStatus("auto");
  const missingRuntimes = plugin.runtimes
    .filter((runtime) => !runtime.installed)
    .map((runtime) => runtime.runtime);

  const runtime = await runtimeReadiness(config.runtime.socketPath);
  const daemonRunning = runtime.ready;

  const doctorReport = await operatorInitDeps.runScopedDoctor(
    { scope: "runtime" },
    { configPath: resolvedConfigPath },
  );
  const doctorFailures = doctorReport.checks.filter((check) => check.status === "fail");

  const wallet = await coinbaseStatus(config, {
    walletHint: getFlag(args, "wallet"),
  }).catch((error: unknown) => ({
    ok: false as const,
    account: null,
    identity_ready: false,
    error: error instanceof Error ? error.message : "Wallet check failed.",
  }));
  const receipt = readCurrentIdentityReceipt(config, {
    walletAddress: wallet.account?.address,
  });

  const nextActions = [
    ...(missingRuntimes.length === 0
      ? []
      : [`regents plugin install --runtime ${missingRuntimes.length === 1 ? missingRuntimes[0] : "auto"}`]),
    ...(daemonRunning ? [] : ["regents run"]),
    ...doctorFailures.map((check) => check.remediation ?? `Fix doctor check ${check.id}`),
    ...(wallet.account ? [] : ["regents wallet setup"]),
    ...(receipt ? [] : ["regents identity ensure"]),
  ];
  const ready = nextActions.length === 0;

  const components = [
    component("config", "ready", configCreated ? `created ${resolvedConfigPath}` : resolvedConfigPath),
    component(
      "plugins",
      plugin.runtimes.every((runtime) => runtime.installed) ? "ready" : "waiting",
      missingRuntimes.length > 0
        ? `Run regents plugin install --runtime ${missingRuntimes.length === 1 ? missingRuntimes[0] : "auto"}`
        : "Hermes and OpenClaw tools already installed",
    ),
    component(
      "runtime",
      daemonRunning ? "ready" : "blocked",
      daemonRunning ? "already running" : runtime.socketExists ? "Run regents doctor --fix" : "Run regents run",
    ),
    component(
      "doctor",
      doctorFailures.length === 0 ? "ready" : "blocked",
      doctorFailures.length === 0 ? "runtime checks passed" : doctorFailures[0]?.message,
    ),
    component(
      "wallet",
      wallet.account ? "ready" : "waiting",
      wallet.account?.address ?? "Run regents wallet setup",
    ),
    component(
      "identity",
      receipt ? "ready" : "waiting",
      receipt ? receipt.agent_id : "Run regents identity ensure",
    ),
  ];

  const payload = {
    ok: true,
    command: "init",
    status: ready ? "ready" : "waiting",
    config_path: resolvedConfigPath,
    config_created: configCreated,
    directories,
    plugin: {
      selected_runtime: "auto",
      installed_now: [],
      runtimes: plugin.runtimes.map(({ runtime, installed }) => ({ runtime, installed })),
    },
    daemon: {
      running: daemonRunning,
      started_now: false,
      socket_path: config.runtime.socketPath,
    },
    doctor: {
      ok: doctorReport.ok,
      fail: doctorReport.summary.fail,
      next_steps: doctorReport.nextSteps,
    },
    wallet: wallet.account ? { name: wallet.account.name, address: wallet.account.address } : null,
    identity: receipt ? { network: receipt.network, agent_id: receipt.agent_id } : null,
    next_actions: ready ? ["regents status"] : nextActions,
  };

  printOperatorPayload(payload, () =>
    [
      renderBanner(),
      renderKeyValuePanel(ready ? "◆ REGENT READY" : "◆ REGENT INIT", [
        { label: "status", value: payload.status, valueColor: statusColor(payload.status) },
        { label: "config", value: resolvedConfigPath },
        { label: "created", value: configCreated ? "yes" : "no" },
      ]),
      renderTablePanel(
        "◆ SETUP",
        [
          { header: "area" },
          { header: "status" },
          { header: "detail" },
        ],
        components.map((item) => ({
          cells: [item.name, item.status, item.detail ?? ""],
          colors: [undefined, statusColor(item.status), undefined],
        })),
      ),
      renderPanel("◆ NEXT", [...payload.next_actions]),
    ].join("\n\n"),
  );
  return 0;
}

export async function runOperatorStatus(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const resolvedConfigPath = configPathFor(args, configPath);
  const configExists = fs.existsSync(resolvedConfigPath);
  const config = loadConfig(resolvedConfigPath);
  const wallet = await coinbaseStatus(config, {
    walletHint: getFlag(args, "wallet"),
  }).catch((error: unknown) => ({
    ok: false as const,
    account: null,
    identity_ready: false,
    error: error instanceof Error ? error.message : "Wallet check failed.",
  }));
  const receipt = readCurrentIdentityReceipt(config, {
    walletAddress: wallet.account?.address,
  });
  const runtime = await runtimeReadiness(config.runtime.socketPath);
  const runtimeNextAction = runtime.socketExists ? "Run regents doctor --fix" : "Run regents run";

  const components = [
    component("config", configExists ? "ready" : "waiting", resolvedConfigPath),
    component(
      "wallet",
      wallet.ok ? "ready" : "waiting",
      wallet.account?.address ?? ("error" in wallet ? wallet.error : undefined),
    ),
    component("identity", receipt ? "ready" : "waiting", receipt ? receipt.agent_id : "Run regents identity ensure"),
    component("runtime", runtime.ready ? "ready" : "waiting", runtime.ready ? config.runtime.socketPath : runtimeNextAction),
  ];
  const blocked = components.filter((item) => item.status === "blocked").length;
  const waiting = components.filter((item) => item.status === "waiting").length;

  const payload = {
    ok: blocked === 0,
    command: "status",
    status: blocked > 0 ? "blocked" : waiting > 0 ? "waiting" : "ready",
    config_path: resolvedConfigPath,
    components,
    next_actions: waiting > 0 ? ["regents init", "regents identity ensure", "regents run"] : [],
  };

  printOperatorPayload(payload, () =>
    [
      renderKeyValuePanel("◆ REGENT STATUS", [
        { label: "status", value: payload.status, valueColor: statusColor(payload.status) },
        { label: "config", value: resolvedConfigPath },
      ]),
      renderTablePanel(
        "◆ READINESS",
        [
          { header: "area" },
          { header: "status" },
          { header: "detail" },
        ],
        components.map((item) => ({
          cells: [item.name, item.status, item.detail ?? ""],
          colors: [undefined, statusColor(item.status), undefined],
        })),
      ),
      ...(waiting > 0 ? [renderPanel("◆ NEXT", payload.next_actions)] : []),
    ].join("\n\n"),
  );
  return blocked > 0 ? 1 : 0;
}

export async function runOperatorOverview(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const resolvedConfigPath = configPathFor(args, configPath);
  const config = loadConfig(resolvedConfigPath);
  const wallet = await coinbaseStatus(config, {
    walletHint: getFlag(args, "wallet"),
  }).catch((error: unknown) => ({
    ok: false as const,
    account: null,
    identity_ready: false,
    error: error instanceof Error ? error.message : "Wallet check failed.",
  }));
  const receipt = readCurrentIdentityReceipt(config, {
    walletAddress: wallet.account?.address,
  });
  const runtime = await runtimeReadiness(config.runtime.socketPath);

  const sessionStore = new SessionStore(
    new StateStore(path.join(config.runtime.stateDir, "runtime-state.json")),
  );
  const siwaSession = sessionStore.getSiwaSession();
  const signIns = [
    ...(siwaSession && !sessionStore.isReceiptExpired() ? [siwaSession.audience] : []),
    ...sessionStore
      .getAppSiwaSessions()
      .filter((session) => !sessionStore.isAppSessionExpired(session.audience))
      .map((session) => session.audience),
  ];

  const components = [
    component(
      "runtime",
      runtime.ready ? "ready" : "waiting",
      runtime.ready ? "running" : runtime.socketExists ? "Run regents doctor --fix" : "Run regents run",
    ),
    component(
      "wallet",
      wallet.account ? "ready" : "waiting",
      wallet.account?.address ?? "Run regents wallet setup",
    ),
    component(
      "identity",
      receipt ? "ready" : "waiting",
      receipt ? receipt.agent_id : "Run regents identity ensure",
    ),
    component(
      "sign-ins",
      signIns.length > 0 ? "ready" : "waiting",
      signIns.length > 0 ? signIns.join(", ") : "Run regents auth login --audience <product>",
    ),
  ];
  const waiting = components.filter((item) => item.status === "waiting").length;

  const payload = {
    ok: true,
    command: "overview",
    status: waiting > 0 ? "waiting" : "ready",
    config_path: resolvedConfigPath,
    components,
    help: "Run regents --help for all commands.",
  };

  printOperatorPayload(payload, () =>
    [
      renderBanner(),
      renderTablePanel(
        "◆ REGENT",
        [
          { header: "area" },
          { header: "status" },
          { header: "detail" },
        ],
        components.map((item) => ({
          cells: [item.name, item.status, item.detail ?? ""],
          colors: [undefined, statusColor(item.status), undefined],
        })),
      ),
      "Run regents --help for all commands.",
    ].join("\n\n"),
  );
  return 0;
}

export async function runOperatorWhoami(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPathFor(args, configPath));
  const full = getBooleanFlag(args, "full");
  const wallet = await coinbaseStatus(config, {
    walletHint: getFlag(args, "wallet"),
  });
  const receipt = readCurrentIdentityReceipt(config, {
    walletAddress: wallet.account?.address,
  });
  const platformProjection = full
    ? await (async () => {
        const { origin, session } = await loadResolvedPlatformSession(args);
        const { data } = await requestPlatformSessionJson({
          origin,
          session,
          method: "GET",
          path: "/api/platform/projection",
          commandName: "regents whoami --full",
          configPath: configPathFor(args, configPath),
          chainId: config.auth.defaultChainId,
        });

        return data;
      })()
    : null;

  const payload = {
    ok: Boolean(wallet.account),
    command: "whoami",
    status: wallet.account ? "ready" : "waiting",
    wallet: wallet.account
      ? {
          name: wallet.account.name,
          address: wallet.account.address,
        }
      : null,
    identity: receipt
      ? {
          network: receipt.network,
          address: receipt.address,
          agent_id: receipt.agent_id,
          verified_until: receipt.receipt_expires_at,
        }
      : null,
    chain_id: config.auth.defaultChainId,
    ...(full
      ? {
          identity_graph: {
            agent_id: receipt?.agent_id ?? null,
            local_identity: receipt
              ? {
                  network: receipt.network,
                  address: receipt.address,
                  agent_id: receipt.agent_id,
                }
              : null,
            platform_projection: platformProjection,
          },
        }
      : {}),
  };

  printOperatorPayload(payload, () =>
    [
      renderKeyValuePanel("◆ CURRENT AGENT", [
        { label: "status", value: payload.status, valueColor: statusColor(payload.status) },
        { label: "wallet", value: wallet.account?.name ?? "not ready" },
        { label: "address", value: wallet.account?.address ?? "not ready" },
        { label: "identity", value: receipt ? receipt.agent_id : "not ready" },
        { label: "chain", value: String(config.auth.defaultChainId) },
        ...(full ? [{ label: "platform", value: platformProjection ? "loaded" : "not loaded" }] : []),
      ]),
    ].join("\n\n"),
  );
  return wallet.account ? 0 : 1;
}
