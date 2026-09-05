import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(import.meta.dirname, "..");
const contracts = [
  {
    label: "Autolaunch public",
    expectedSha256: "8f8100c9583972f4ff663f3d8dcfb1800b89b3f26e01741e37fd689b3606519c",
    input: "docs/autolaunch-public-contract.openapiv3.yaml",
    output: "packages/regents-cli/src/generated/autolaunch-public-openapi.ts",
  },
  {
    label: "Shared services",
    input: "docs/regent-services-contract.openapiv3.yaml",
    output: "packages/regents-cli/src/generated/regent-services-openapi.ts",
  },
  {
    label: "Ash Techtree",
    input: "docs/ash-techtree-contract.openapiv3.yaml",
    output: "packages/regents-cli/src/generated/ash-techtree-openapi.ts",
  },
];
const tempDir = mkdtempSync(join(tmpdir(), "regents-openapi-"));

try {
  for (const contract of contracts) {
    const input = resolve(root, contract.input);
    const output = resolve(root, contract.output);
    if (contract.expectedSha256 && createHash("sha256").update(readFileSync(input)).digest("hex") !== contract.expectedSha256) {
      throw new Error(`${contract.label} copied contract differs from its reviewed product source. Synchronize the product contract and provenance together.`);
    }
    const generated = join(tempDir, basename(contract.output));
    const result = spawnSync("pnpm", ["exec", "openapi-typescript", input, "-o", generated], {
      cwd: root,
      encoding: "utf8",
    });
    if (result.status !== 0) {
      process.stderr.write(result.stderr || result.stdout || "OpenAPI generation failed\n");
      process.exit(result.status ?? 1);
    }
    if (!readFileSync(generated).equals(readFileSync(output))) {
      console.error(`${contract.label} generated OpenAPI types drifted from ${contract.input}`);
      process.exit(1);
    }
  }
} finally {
  rmSync(tempDir, { recursive: true, force: true });
}

console.log("repository-local OpenAPI generated types check passed");
