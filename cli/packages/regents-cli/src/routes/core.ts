import {
  runAgentHarnessList,
  runAgentInit,
  runAgentProfileList,
  runAgentProfileGet,
  runAgentStatus,
} from "../commands/agent.js";
import { runAgentContext } from "../commands/agent-context.js";
import { runBudgetGrant, runBudgetLedger, runBudgetRevoke, runBudgetStatus } from "../commands/budget.js";
import { runCommandsList } from "../commands/commands-list.js";
import { runConfigGet, runConfigWrite } from "../commands/config.js";
import { runDoctorCommand, runDoctorContractsCommand, runDoctorWorkspaceCommand } from "../commands/doctor.js";
import { runGossipsubStatus } from "../commands/gossipsub.js";
import {
  runMcpDoctor,
  runMcpExportCodex,
  runMcpServe,
  runMcpToolsList,
} from "../commands/mcp.js";
import {
  runOperatorInit,
  runOperatorStatus,
  runOperatorWhoami,
} from "../commands/operator.js";
import { runPluginDoctor, runPluginInstall, runPluginStatus } from "../commands/plugin.js";
import { runReceiptCreate, runReceiptGet, runReceiptList, runReceiptShareDraft } from "../commands/receipt.js";
import { runRuntime } from "../commands/run.js";
import { runSetup } from "../commands/setup.js";
import { runSetupSkills } from "../commands/setup-skills.js";
import { runUpdate } from "../commands/update.js";
import { runVersion } from "../commands/version.js";
import { runVoiceServe } from "../commands/voice.js";
import {
  runX402Details,
  runX402Fetch,
  runX402Pay,
  runX402Prepare,
  runX402Quote,
  runX402ReceiptsGet,
  runX402Refund,
  runX402Search,
} from "../commands/x402.js";
import type { CliHandlerRegistry } from "./shared.js";

export const coreHandlers: CliHandlerRegistry = {
  init: { run: ({ parsedArgs, configPath }) => runOperatorInit(parsedArgs, configPath) },
  settings: { run: ({ parsedArgs }) => runConfigGet(parsedArgs) },
  status: { run: ({ parsedArgs, configPath }) => runOperatorStatus(parsedArgs, configPath) },
  whoami: { run: ({ parsedArgs, configPath }) => runOperatorWhoami(parsedArgs, configPath) },
  "agent-context": { run: ({ parsedArgs, configPath }) => runAgentContext(parsedArgs, configPath) },
  setup: { run: ({ parsedArgs }) => runSetup(parsedArgs) },
  version: { run: ({ parsedArgs }) => runVersion(parsedArgs) },
  update: { run: ({ parsedArgs }) => runUpdate(parsedArgs) },
  "plugin status": { run: ({ parsedArgs }) => runPluginStatus(parsedArgs) },
  "plugin install": { run: ({ parsedArgs }) => runPluginInstall(parsedArgs) },
  "plugin doctor": { run: ({ parsedArgs }) => runPluginDoctor(parsedArgs) },
  "setup skills": { run: ({ parsedArgs }) => runSetupSkills(parsedArgs) },
  run: { run: ({ parsedArgs, configPath }) => runRuntime(parsedArgs, configPath) },
  "commands list": { run: ({ parsedArgs }) => runCommandsList(parsedArgs) },
  "config get": { run: ({ parsedArgs }) => runConfigGet(parsedArgs) },
  "config write": { run: ({ parsedArgs }) => runConfigWrite(parsedArgs) },
  "doctor runtime": { run: ({ parsedArgs, configPath }) => runDoctorCommand(parsedArgs, configPath) },
  "doctor auth": { run: ({ parsedArgs, configPath }) => runDoctorCommand(parsedArgs, configPath) },
  "doctor transports": { run: ({ parsedArgs, configPath }) => runDoctorCommand(parsedArgs, configPath) },
  "doctor contracts": { run: ({ parsedArgs, configPath }) => runDoctorContractsCommand(parsedArgs, configPath) },
  "doctor workspace": { run: ({ parsedArgs, configPath }) => runDoctorWorkspaceCommand(parsedArgs, configPath) },
  doctor: { run: ({ parsedArgs, configPath }) => runDoctorCommand(parsedArgs, configPath), variadicTail: true },
  "mcp export codex": { run: () => runMcpExportCodex() },
  "mcp tools list": { run: () => runMcpToolsList() },
  "mcp doctor": { run: ({ parsedArgs, configPath }) => runMcpDoctor(parsedArgs, configPath) },
  "mcp serve": { run: ({ parsedArgs, configPath }) => runMcpServe(parsedArgs, configPath) },
  "voice serve": { run: ({ parsedArgs, configPath }) => runVoiceServe(parsedArgs, configPath) },
  "x402 search": { run: ({ parsedArgs }) => runX402Search(parsedArgs), variadicTail: true },
  "x402 details": { run: ({ parsedArgs, configPath }) => runX402Details(parsedArgs, configPath) },
  "x402 quote": { run: ({ parsedArgs, configPath }) => runX402Quote(parsedArgs, configPath) },
  "x402 prepare": { run: ({ parsedArgs, configPath }) => runX402Prepare(parsedArgs, configPath) },
  "x402 fetch": { run: ({ parsedArgs, configPath }) => runX402Fetch(parsedArgs, configPath) },
  "x402 refund": { run: ({ parsedArgs, configPath }) => runX402Refund(parsedArgs, configPath) },
  "x402 pay": { run: ({ parsedArgs, configPath }) => runX402Pay(parsedArgs, configPath), pattern: "x402 pay <url>" },
  "x402 receipts get": { run: ({ parsedArgs, configPath }) => runX402ReceiptsGet(parsedArgs, configPath) },
  "budget grant": { run: ({ parsedArgs, configPath }) => runBudgetGrant(parsedArgs, configPath) },
  "budget status": { run: ({ parsedArgs, configPath }) => runBudgetStatus(parsedArgs, configPath) },
  "budget ledger": { run: ({ parsedArgs, configPath }) => runBudgetLedger(parsedArgs, configPath) },
  "budget revoke": { run: ({ parsedArgs, configPath }) => runBudgetRevoke(parsedArgs, configPath) },
  "receipt create": { run: ({ parsedArgs, configPath }) => runReceiptCreate(parsedArgs, configPath) },
  "receipt get": { run: ({ parsedArgs, configPath }) => runReceiptGet(parsedArgs, configPath) },
  "receipt list": { run: ({ parsedArgs, configPath }) => runReceiptList(parsedArgs, configPath) },
  "receipt share-draft": { run: ({ parsedArgs, configPath }) => runReceiptShareDraft(parsedArgs, configPath) },
  "agent init": { run: ({ configPath }) => runAgentInit(configPath) },
  "agent status": { run: ({ configPath }) => runAgentStatus(configPath) },
  "agent profile list": { run: ({ configPath }) => runAgentProfileList(configPath) },
  "agent profile get": { run: ({ parsedArgs, configPath }) => runAgentProfileGet(parsedArgs, configPath) },
  "agent harness list": { run: ({ configPath }) => runAgentHarnessList(configPath) },
  "gossipsub status": { run: ({ configPath }) => runGossipsubStatus(configPath) },
};
