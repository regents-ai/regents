import type { GossipsubStatus } from "../../internal-types/index.js";

import type { RuntimeContext } from "../runtime.js";

export async function handleGossipsubStatus(ctx: RuntimeContext): Promise<GossipsubStatus> {
  return ctx.gossipsub.status();
}
