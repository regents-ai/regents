import type { DoctorCheckDefinition } from "../types.js";
import { skipDueToMissingConfig } from "./shared.js";

export function transportChecks(): DoctorCheckDefinition[] {
  return [
    {
      id: "transports.gossipsub.config",
      scope: "transports",
      title: "Gossipsub config",
      run: async (ctx) => {
        if (!ctx.config) {
          return skipDueToMissingConfig();
        }

        return {
          status: "ok",
          message: ctx.config.gossipsub.enabled
            ? "Gossipsub configuration is present; this runtime exposes status only"
            : "Gossipsub is disabled in config",
          details: {
            enabled: ctx.config.gossipsub.enabled,
            listenAddrs: ctx.config.gossipsub.listenAddrs,
            bootstrap: ctx.config.gossipsub.bootstrap,
            peerIdPath: ctx.config.gossipsub.peerIdPath,
          },
        };
      },
    },
  ];
}
