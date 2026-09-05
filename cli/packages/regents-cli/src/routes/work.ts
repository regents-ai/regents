import {
  runWorkCancel,
  runWorkCreate,
  runWorkList,
  runWorkLocalLoop,
  runWorkRetry,
  runWorkRun,
  runWorkGet,
  runWorkWatch,
} from "../commands/work.js";
import type { CliHandlerRegistry } from "./shared.js";

export const workHandlers: CliHandlerRegistry = {
  "work create": { run: ({ parsedArgs }) => runWorkCreate(parsedArgs) },
  "work list": { run: ({ parsedArgs }) => runWorkList(parsedArgs) },
  "work local-loop": { run: ({ parsedArgs }) => runWorkLocalLoop(parsedArgs) },
  "work get": { run: ({ parsedArgs }) => runWorkGet(parsedArgs), variadicTail: true },
  "work run": { run: ({ parsedArgs }) => runWorkRun(parsedArgs), variadicTail: true },
  "work cancel": { run: ({ parsedArgs }) => runWorkCancel(parsedArgs), variadicTail: true },
  "work retry": { run: ({ parsedArgs }) => runWorkRetry(parsedArgs), variadicTail: true },
  "work watch": { run: ({ parsedArgs }) => runWorkWatch(parsedArgs), variadicTail: true },
};
