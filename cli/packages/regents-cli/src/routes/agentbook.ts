import { runAgentbookLookup, runAgentbookRegister, runAgentbookSessionsWatch } from "../commands/agentbook.js";
import type { CliHandlerRegistry } from "./shared.js";

export const agentbookHandlers: CliHandlerRegistry = {
  "agentbook register": { run: ({ parsedArgs, configPath }) => runAgentbookRegister(parsedArgs, configPath) },
  "agentbook sessions watch": { run: ({ parsedArgs, configPath }) => runAgentbookSessionsWatch(parsedArgs, configPath), variadicTail: true },
  "agentbook lookup": { run: ({ parsedArgs, configPath }) => runAgentbookLookup(parsedArgs, configPath) },
};
