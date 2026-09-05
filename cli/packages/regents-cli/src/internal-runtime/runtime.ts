import path from "node:path";

import type {
  RegentConfig,
  RegentRpcMethod,
  RegentRpcResult,
  RuntimeStatus,
} from "../internal-types/index.js";

import { LocalKeySignerBackend } from "./agent/local-signer-backend.js";
import type { SignerBackend } from "./agent/signer-backend.js";
import { loadConfig } from "./config.js";
import { JsonRpcError } from "./errors.js";
import {
  handleAgentHarnessList,
  handleAgentInit,
  handleAgentProfileList,
  handleAgentProfileShow,
  handleAgentStatus,
} from "./handlers/agent.js";
import {
  handleAuthSiwaLogin,
  handleAuthSiwaLogout,
  handleAuthSiwaStatus,
} from "./handlers/auth.js";
import { handleGossipsubStatus } from "./handlers/gossipsub.js";
import {
  handleRuntimePing,
  handleRuntimeShutdown,
  handleRuntimeStatus,
} from "./handlers/runtime.js";
import {
  handleTechtreeForgeFamilyShow,
  handleTechtreeForgeFamilyValidate,
} from "./handlers/techtree/forge.js";
import {
  handleTechtreeNotebooksInit,
  handleTechtreeNotebooksPair,
} from "./handlers/techtree/notebooks.js";
import {
  handleTechtreeVerifyReceiptShow,
  handleTechtreeVerifyRun,
  handleTechtreeVerifyStatus,
} from "./handlers/techtree/verify.js";
import { handleTechtreeUpliftReport } from "./handlers/techtree/uplift.js";
import {
  handleX402Details,
  handleX402Fetch,
  handleX402Prepare,
  handleX402Quote,
  handleX402ReceiptGet,
  handleX402Refund,
} from "./handlers/x402.js";
import { JsonRpcServer } from "./jsonrpc/server.js";
import { SessionStore } from "./store/session-store.js";
import { StateStore } from "./store/state-store.js";
import {
  StubGossipsubAdapter,
  type GossipsubAdapter,
  type TransportAdapter,
} from "./transports/index.js";

export interface RuntimeContext {
  config: RegentConfig;
  stateStore: StateStore;
  sessionStore: SessionStore;
  signer: SignerBackend;
  gossipsub: GossipsubAdapter;
  runtime: RegentKernel;
  requestShutdown: () => void;
}

const createSigner = (config: RegentConfig): SignerBackend =>
  new LocalKeySignerBackend({
    privateKeyEnv: config.wallet.privateKeyEnv,
    keystorePath: config.wallet.keystorePath,
  });

const stopIgnoringErrors = async (
  stopper: { stop: () => Promise<void> },
): Promise<void> => {
  await stopper.stop().catch(() => undefined);
};

const loadDoctorHandlers = async () => import("./handlers/doctor.js");

export class RegentKernel {
  readonly configPath?: string;
  readonly config: RegentConfig;
  readonly stateStore: StateStore;
  readonly sessionStore: SessionStore;
  readonly signer: SignerBackend;
  readonly gossipsub: GossipsubAdapter;
  readonly jsonRpcServer: JsonRpcServer;

  private started = false;
  private shutdownRequested = false;

  constructor(configPath?: string) {
    this.configPath = configPath;
    this.config = loadConfig(configPath);
    this.stateStore = new StateStore(
      path.join(this.config.runtime.stateDir, "runtime-state.json"),
    );
    this.sessionStore = new SessionStore(this.stateStore);
    this.signer = createSigner(this.config);
    this.gossipsub = new StubGossipsubAdapter();
    this.jsonRpcServer = new JsonRpcServer(
      this.config.runtime.socketPath,
      async (method, params) => this.dispatch(method, params),
    );
  }

  async start(): Promise<void> {
    if (this.started) {
      return;
    }

    try {
      for (const transport of this.transportAdapters()) {
        await transport.start();
      }
      await this.jsonRpcServer.start();
      this.started = true;
      this.shutdownRequested = false;
    } catch (error) {
      await this.safeStopSubsystems();
      throw error;
    }
  }

  async stop(): Promise<void> {
    await this.safeStopSubsystems();
    this.started = false;
    this.shutdownRequested = false;
  }

  isStarted(): boolean {
    return this.started;
  }

  async status(): Promise<RuntimeStatus> {
    const session = this.sessionStore.getSiwaSession();
    const [agent, gossipsub] = await Promise.all([
      handleAgentStatus(this.context()),
      this.gossipsub.status(),
    ]);

    return {
      running: this.started,
      socketPath: this.config.runtime.socketPath,
      stateDir: this.config.runtime.stateDir,
      logLevel: this.config.runtime.logLevel,
      authenticated: !!session && !this.sessionStore.isReceiptExpired(),
      session: session
        ? {
            walletAddress: session.walletAddress,
            chainId: session.chainId,
            receiptExpiresAt: session.receiptExpiresAt,
          }
        : null,
      agentIdentity: agent.identity,
      agent,
      gossipsub,
    };
  }

  requestShutdown(): void {
    if (this.shutdownRequested) {
      return;
    }

    this.shutdownRequested = true;
    queueMicrotask(() => {
      void this.stop().finally(() => {
        this.shutdownRequested = false;
      });
    });
  }

  async call<TMethod extends RegentRpcMethod>(
    method: TMethod,
    params?: unknown,
  ): Promise<RegentRpcResult<TMethod>> {
    return (await this.dispatch(method, params)) as RegentRpcResult<TMethod>;
  }

  private context(): RuntimeContext {
    return {
      config: this.config,
      stateStore: this.stateStore,
      sessionStore: this.sessionStore,
      signer: this.signer,
      gossipsub: this.gossipsub,
      runtime: this,
      requestShutdown: () => this.requestShutdown(),
    };
  }

  private async safeStopSubsystems(): Promise<void> {
    await stopIgnoringErrors(this.jsonRpcServer);
    for (const transport of [...this.transportAdapters()].reverse()) {
      await stopIgnoringErrors(transport);
    }
  }

  private transportAdapters(): TransportAdapter[] {
    return [this.gossipsub];
  }

  private async dispatch(
    method: RegentRpcMethod,
    params: unknown,
  ): Promise<unknown> {
    const ctx = this.context();

    switch (method) {
      case "runtime.ping":
        return handleRuntimePing();
      case "runtime.status":
        return handleRuntimeStatus(ctx);
      case "runtime.shutdown":
        return handleRuntimeShutdown(ctx);
      case "agent.init":
        return handleAgentInit(ctx);
      case "agent.status":
        return handleAgentStatus(ctx);
      case "agent.profile.list":
        return handleAgentProfileList(ctx);
      case "agent.profile.show":
        return handleAgentProfileShow(
          ctx,
          params as Parameters<typeof handleAgentProfileShow>[1],
        );
      case "agent.harness.list":
        return handleAgentHarnessList(ctx);
      case "doctor.run":
        return (await loadDoctorHandlers()).handleDoctorRun(
          ctx,
          params as Parameters<
            (typeof import("./handlers/doctor.js"))["handleDoctorRun"]
          >[1],
        );
      case "doctor.runScoped":
        return (await loadDoctorHandlers()).handleDoctorRunScoped(
          ctx,
          params as Parameters<
            (typeof import("./handlers/doctor.js"))["handleDoctorRunScoped"]
          >[1],
        );
      case "doctor.runFull":
        return (await loadDoctorHandlers()).handleDoctorRunFull(
          ctx,
          params as Parameters<
            (typeof import("./handlers/doctor.js"))["handleDoctorRunFull"]
          >[1],
        );
      case "auth.siwa.login":
        return handleAuthSiwaLogin(
          ctx,
          (params ?? {}) as Parameters<typeof handleAuthSiwaLogin>[1],
        );
      case "auth.siwa.status":
        return handleAuthSiwaStatus(ctx);
      case "auth.siwa.logout":
        return handleAuthSiwaLogout(ctx);
      case "techtree.forge.family.show":
        return handleTechtreeForgeFamilyShow();
      case "techtree.forge.family.validate":
        return handleTechtreeForgeFamilyValidate(
          params as Parameters<typeof handleTechtreeForgeFamilyValidate>[0],
        );
      case "techtree.verify.run":
        return handleTechtreeVerifyRun(
          ctx.config.runtime.stateDir,
          params as Parameters<typeof handleTechtreeVerifyRun>[1],
        );
      case "techtree.verify.status":
        return handleTechtreeVerifyStatus(
          ctx.config.runtime.stateDir,
          params as Parameters<typeof handleTechtreeVerifyStatus>[1],
        );
      case "techtree.verify.receipt.show":
        return handleTechtreeVerifyReceiptShow(
          ctx.config.runtime.stateDir,
          params as Parameters<typeof handleTechtreeVerifyReceiptShow>[1],
        );
      case "techtree.uplift.report":
        return handleTechtreeUpliftReport(
          ctx.config.runtime.stateDir,
          params as Parameters<typeof handleTechtreeUpliftReport>[1],
        );
      case "techtree.notebooks.init":
        return handleTechtreeNotebooksInit(
          params as Parameters<typeof handleTechtreeNotebooksInit>[0],
        );
      case "techtree.notebooks.pair":
        return handleTechtreeNotebooksPair(
          params as Parameters<typeof handleTechtreeNotebooksPair>[0],
        );
      case "x402.details":
        return handleX402Details(
          ctx,
          params as Parameters<typeof handleX402Details>[1],
        );
      case "x402.quote":
        return handleX402Quote(
          ctx,
          params as Parameters<typeof handleX402Quote>[1],
        );
      case "x402.prepare":
        return handleX402Prepare(
          ctx,
          params as Parameters<typeof handleX402Prepare>[1],
        );
      case "x402.fetch":
        return handleX402Fetch(
          ctx,
          params as Parameters<typeof handleX402Fetch>[1],
        );
      case "x402.refund":
        return handleX402Refund(
          ctx,
          params as Parameters<typeof handleX402Refund>[1],
        );
      case "x402.receipts.get":
        return handleX402ReceiptGet(
          ctx,
          params as Parameters<typeof handleX402ReceiptGet>[1],
        );
      case "gossipsub.status":
        return handleGossipsubStatus(ctx);
      default:
        throw new JsonRpcError(`method not implemented: ${method}`, {
          code: "method_not_implemented",
          rpcCode: -32601,
        });
    }
  }
}

export class RegentRuntime extends RegentKernel {}
