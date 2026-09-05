import type { RegentRpcMethod } from "../../internal-types/index.js";

export const REGENT_RPC_METHODS = {
  runtimePing: "runtime.ping",
  runtimeStatus: "runtime.status",
  runtimeShutdown: "runtime.shutdown",
  agentInit: "agent.init",
  agentStatus: "agent.status",
  agentProfileList: "agent.profile.list",
  agentProfileShow: "agent.profile.show",
  agentHarnessList: "agent.harness.list",
  doctorRun: "doctor.run",
  doctorRunScoped: "doctor.runScoped",
  doctorRunFull: "doctor.runFull",
  authSiwaLogin: "auth.siwa.login",
  authSiwaLogout: "auth.siwa.logout",
  authSiwaStatus: "auth.siwa.status",
  techtreeForgeFamilyShow: "techtree.forge.family.show",
  techtreeForgeFamilyValidate: "techtree.forge.family.validate",
  techtreeVerifyRun: "techtree.verify.run",
  techtreeVerifyStatus: "techtree.verify.status",
  techtreeVerifyReceiptShow: "techtree.verify.receipt.show",
  techtreeUpliftReport: "techtree.uplift.report",
  techtreeNotebooksInit: "techtree.notebooks.init",
  techtreeNotebooksPair: "techtree.notebooks.pair",
  x402Details: "x402.details",
  x402Quote: "x402.quote",
  x402Prepare: "x402.prepare",
  x402Fetch: "x402.fetch",
  x402Refund: "x402.refund",
  x402ReceiptsGet: "x402.receipts.get",
  gossipsubStatus: "gossipsub.status",
} as const satisfies Record<string, RegentRpcMethod>;

export const REGENT_RPC_METHOD_SET = new Set<RegentRpcMethod>(
  Object.values(REGENT_RPC_METHODS),
);
