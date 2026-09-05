import {
  runAgentChat,
  runAgentConnectHostedHermes,
  runAgentConnectOpenClaw,
  runAgentExecutionPool,
  runAgentLink,
} from "../commands/platform/agent-link.js";
import type { CliHandlerRegistry } from "./shared.js";

export const platformAgentHandlers: CliHandlerRegistry = {
  "agent chat": {
    run: ({ parsedArgs }) => runAgentChat(parsedArgs),
    variadicTail: true,
  },
  "agent connect hosted-hermes": {
    run: ({ parsedArgs }) => runAgentConnectHostedHermes(parsedArgs),
  },
  "agent connect openclaw": {
    run: ({ parsedArgs, configPath }) => runAgentConnectOpenClaw(parsedArgs, configPath),
  },
  "agent link": { run: ({ parsedArgs }) => runAgentLink(parsedArgs) },
  "agent execution-pool": { run: ({ parsedArgs }) => runAgentExecutionPool(parsedArgs) },
};
