import path from "node:path";

import { describe, expect, it } from "vitest";

import { buildContractDoctorReport, buildWorkspaceDoctorReport } from "../src/commands/doctor.js";
import { route, routeMatches } from "../src/routes/shared.js";

const repoRoot = path.resolve(import.meta.dirname, "../../..");

describe("repository-local observability", () => {
  it("reports local contracts, generated files, and command coverage", () => {
    const report = buildContractDoctorReport();
    expect(report).toMatchObject({
      ok: true,
      command: "regents doctor contracts",
      root: repoRoot,
      summary: { loaded: 3, missingFiles: 0, missingGeneratedBindings: 0, missingCommands: 0 },
    });
    expect(report.files).toEqual(expect.arrayContaining([
      expect.objectContaining({ owner: "regents-cli", kind: "cli", loaded: true, commandStatus: "covered" }),
      expect.objectContaining({ owner: "shared-services", kind: "api", loaded: true, generatedStatus: "present" }),
      expect.objectContaining({ owner: "regents-cli", kind: "runtime", loaded: true, generatedStatus: "present" }),
    ]));
    for (const file of report.files) expect(file.contractPath.startsWith(repoRoot)).toBe(true);
  });

  it("reports standalone workspace readiness from repository-local files", () => {
    const previousCwd = process.cwd();
    process.chdir(path.join(repoRoot, "packages/regents-cli"));
    try {
      const report = buildWorkspaceDoctorReport();
      expect(report).toMatchObject({
        ok: true,
        command: "regents doctor workspace",
        root: repoRoot,
        summary: { missingFiles: 0 },
      });
      expect(report.summary.requiredFiles).toBeGreaterThan(0);
      expect(report.files.every((file) => file.loaded && file.path.startsWith(repoRoot))).toBe(true);
    } finally {
      process.chdir(previousCwd);
    }
  });

  it("does not match extra words unless the route declares them", () => {
    const exact = route("techtree notebooks pair", async () => 0);
    const variadic = route("doctor", async () => 0, { variadicTail: true });
    expect(routeMatches(exact, ["techtree", "notebooks", "pair"])).toBe(true);
    expect(routeMatches(exact, ["techtree", "notebooks", "pair", "extra"])).toBe(false);
    expect(routeMatches(variadic, ["doctor", "auth"])).toBe(true);
  });
});
