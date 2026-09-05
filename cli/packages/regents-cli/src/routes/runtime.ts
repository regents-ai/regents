import {
  runRuntimeCheckpoint,
  runRuntimeCreate,
  runRuntimeHealth,
  runRuntimePause,
  runRuntimeRestore,
  runRuntimeResume,
  runRuntimeServices,
  runRuntimeGet,
} from "../commands/runtime.js";
import {
  runRuntimeLocalPolicy,
  runRuntimeLocalStatus,
  runRuntimeLocalTools,
} from "../commands/runtime-local.js";
import type { CliHandlerRegistry } from "./shared.js";

export const runtimeHandlers: CliHandlerRegistry = {
  "runtime status": { run: ({ configPath }) => runRuntimeLocalStatus(configPath) },
  "runtime tools": { run: () => runRuntimeLocalTools() },
  "runtime policy": { run: ({ configPath }) => runRuntimeLocalPolicy(configPath) },
  "runtime create": { run: ({ parsedArgs }) => runRuntimeCreate(parsedArgs) },
  "runtime get": { run: ({ parsedArgs }) => runRuntimeGet(parsedArgs), variadicTail: true },
  "runtime checkpoint": { run: ({ parsedArgs }) => runRuntimeCheckpoint(parsedArgs), variadicTail: true },
  "runtime restore": { run: ({ parsedArgs }) => runRuntimeRestore(parsedArgs), variadicTail: true },
  "runtime pause": { run: ({ parsedArgs }) => runRuntimePause(parsedArgs), variadicTail: true },
  "runtime resume": { run: ({ parsedArgs }) => runRuntimeResume(parsedArgs), variadicTail: true },
  "runtime services": { run: ({ parsedArgs }) => runRuntimeServices(parsedArgs), variadicTail: true },
  "runtime health": { run: ({ parsedArgs }) => runRuntimeHealth(parsedArgs), variadicTail: true },
};
