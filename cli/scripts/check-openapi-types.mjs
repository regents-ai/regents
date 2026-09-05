import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(import.meta.dirname, "..");
const contracts = [
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
