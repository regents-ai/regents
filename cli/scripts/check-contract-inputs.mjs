import { existsSync, statSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const requiredInputs = [
  ["shared CLI contract", "docs/shared-cli-contract.yaml"],
  ["shared services OpenAPI contract", "docs/regent-services-contract.openapiv3.yaml"],
  ["Ash Techtree OpenAPI contract", "docs/ash-techtree-contract.openapiv3.yaml"],
  ["runtime JSON-RPC contract", "docs/json-rpc-methods.yaml"],
  ["WalletAction schema", "docs/schemas/wallet-action.schema.yaml"],
  ["Platform copied API binding", "packages/regents-cli/src/generated/platform-openapi.ts"],
  ["Ash Techtree generated API binding", "packages/regents-cli/src/generated/ash-techtree-openapi.ts"],
  ["Autolaunch copied API binding", "packages/regents-cli/src/generated/autolaunch-openapi.ts"],
  ["shared services generated binding", "packages/regents-cli/src/generated/regent-services-openapi.ts"],
];

const missing = requiredInputs.filter(([, relativePath]) => {
  const inputPath = resolve(root, relativePath);
  return !existsSync(inputPath) || !statSync(inputPath).isFile();
});

if (missing.length > 0) {
  console.error("Repository checks need these local inputs:");
  for (const [label, relativePath] of missing) console.error(`- ${label}: ${relativePath}`);
  process.exit(1);
}

console.log("repository-local contract input check passed");
