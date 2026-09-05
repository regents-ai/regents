import { CLI_COMMANDS } from "../command-registry.js";
import { agentbookHandlers } from "./agentbook.js";
import { autolaunchHandlers } from "./autolaunch.js";
import { chatHandlers } from "./chat.js";
import { coreHandlers } from "./core.js";
import { feynmanHandlers } from "./feynman.js";
import { platformAgentHandlers } from "./platform-agent.js";
import { platformHandlers } from "./platform.js";
import { regentStakingHandlers } from "./regent-staking.js";
import { reportingHandlers } from "./reporting.js";
import { runtimeHandlers } from "./runtime.js";
import {
  assertRouteRegistryMatches,
  buildRoutesFromRegistry,
  type CliHandlerRegistry,
  type CliRoute,
} from "./shared.js";
import { techtreeHandlers } from "./techtree.js";
import { walletIdentityAuthHandlers } from "./wallet-identity-auth.js";
import { workHandlers } from "./work.js";

export { dispatchRoute, type CliRouteContext } from "./shared.js";

// Single declarative handler registry: command name -> handler entry. The route
// table is generated from the generated CLI command metadata (CLI_COMMANDS), so
// every routable command is proven to have exactly one registered handler.
export const cliHandlerRegistry: CliHandlerRegistry = {
  ...coreHandlers,
  ...feynmanHandlers,
  ...workHandlers,
  ...runtimeHandlers,
  ...platformAgentHandlers,
  ...reportingHandlers,
  ...walletIdentityAuthHandlers,
  ...platformHandlers,
  ...techtreeHandlers,
  ...regentStakingHandlers,
  ...agentbookHandlers,
  ...chatHandlers,
  ...autolaunchHandlers,
};

export const cliRoutes: readonly CliRoute[] = buildRoutesFromRegistry(CLI_COMMANDS, cliHandlerRegistry);

assertRouteRegistryMatches(cliRoutes);
