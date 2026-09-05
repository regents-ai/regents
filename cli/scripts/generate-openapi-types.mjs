import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(import.meta.dirname, "..");
const contracts = [
  {
    input: "docs/regent-services-contract.openapiv3.yaml",
    output: "packages/regents-cli/src/generated/regent-services-openapi.ts",
  },
  {
    input: "docs/ash-techtree-contract.openapiv3.yaml",
    output: "packages/regents-cli/src/generated/ash-techtree-openapi.ts",
  },
];

for (const contract of contracts) {
  const input = resolve(root, contract.input);
  const output = resolve(root, contract.output);
  mkdirSync(dirname(output), { recursive: true });

  const result = spawnSync("pnpm", ["exec", "openapi-typescript", input, "-o", output], {
    cwd: root,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}
