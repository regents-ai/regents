import fs from "node:fs";
import { resolve } from "node:path";
import { loadYaml } from "./dependency-preflight.mjs";

const root = resolve(import.meta.dirname, "..");
const YAML = await loadYaml(root);
const contractPath = resolve(root, "docs/regent-services-contract.openapiv3.yaml");
const generatedPath = resolve(root, "packages/regents-cli/src/generated/regent-services-openapi.ts");
const contract = YAML.parse(fs.readFileSync(contractPath, "utf8"));
const failures = [];

if (contract?.openapi !== "3.1.0") failures.push("Shared services contract must use OpenAPI 3.1.0");
if (!contract?.paths || Object.keys(contract.paths).length === 0) failures.push("Shared services contract must define paths");
for (const routePath of [
  "/api/shared/identity/status",
  "/api/shared/identity/registration-intents",
  "/api/shared/identity/registration-completions",
  "/api/shared/identity/siwa/nonce",
  "/api/shared/identity/siwa/verify",
]) {
  if (!contract?.paths?.[routePath]) failures.push(`Shared services contract is missing ${routePath}`);
}
if (!fs.existsSync(generatedPath)) failures.push(`Shared services generated binding is missing: ${generatedPath}`);

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("repository-local shared services contract check passed");
