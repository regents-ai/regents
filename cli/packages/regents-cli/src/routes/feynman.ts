import { feynmanArgsFromRawArgs, runFeynman } from "../commands/feynman.js";
import type { CliHandlerRegistry } from "./shared.js";

export const feynmanHandlers: CliHandlerRegistry = {
  feynman: { run: ({ rawArgs }) => runFeynman(feynmanArgsFromRawArgs(rawArgs)), variadicTail: true },
};
