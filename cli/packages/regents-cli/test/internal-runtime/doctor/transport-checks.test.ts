import { describe, expect, it } from "vitest";

import { defaultConfig } from "../../../src/internal-runtime/config.js";
import { transportChecks } from "../../../src/internal-runtime/doctor/checks/transportChecks.js";
import type { DoctorCheckContext } from "../../../src/internal-runtime/doctor/types.js";

describe("transport doctor checks", () => {
  it("reports the local gossipsub configuration", async () => {
    const check = transportChecks().find(
      (candidate) => candidate.id === "transports.gossipsub.config",
    );
    expect(check).toBeDefined();
    const result = await check!.run({
      config: defaultConfig(),
    } as DoctorCheckContext);
    expect(result).toMatchObject({
      status: "ok",
      details: { enabled: false },
    });
  });
});
