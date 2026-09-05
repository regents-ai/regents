import { describe, expect, it } from "vitest";

import { runChecksSequentially } from "../../../src/internal-runtime/doctor/checkRunner.js";
import type { DoctorCheckContext, DoctorCheckDefinition } from "../../../src/internal-runtime/doctor/types.js";

describe("doctor check runner", () => {
  it("normalizes thrown check errors into internal doctor failures", async () => {
    const check: DoctorCheckDefinition = {
      id: "runtime.crash.example",
      scope: "runtime",
      title: "crashing check",
      run: async () => {
        throw new Error("doctor check exploded");
      },
    };

    const ctx: DoctorCheckContext = {
      mode: "default",
      configPath: "/tmp/regent-doctor-config.json",
      runtimeContext: null,
      config: null,
      configLoadError: null,
      stateStore: null,
      sessionStore: null,
      signer: null,
      fix: false,
      verbose: false,
      refreshConfig: () => undefined,
    };

    const [result] = await runChecksSequentially([check], ctx);

    expect(result).toEqual(
      expect.objectContaining({
        id: "runtime.crash.example",
        scope: "runtime",
        status: "fail",
        message: "Doctor check crashed before it could return a result",
        details: expect.objectContaining({
          internal: true,
          code: "doctor_check_crashed",
          error: "doctor check exploded",
        }),
      }),
    );
  });

});
