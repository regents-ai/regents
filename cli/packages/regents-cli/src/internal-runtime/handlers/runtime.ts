import type { RuntimeStatus } from "../../internal-types/index.js";

import type { RuntimeContext } from "../runtime.js";

export async function handleRuntimePing(): Promise<{ ok: true }> {
  return { ok: true };
}

export async function handleRuntimeStatus(ctx: RuntimeContext): Promise<RuntimeStatus> {
  return ctx.runtime.status();
}

export async function handleRuntimeShutdown(ctx: RuntimeContext): Promise<{ ok: true }> {
  ctx.requestShutdown();
  return { ok: true };
}
