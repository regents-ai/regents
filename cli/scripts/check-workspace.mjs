import fs from "node:fs";
import path from "node:path";
import { loadYaml } from "./dependency-preflight.mjs";
import { checkCliCommandMetadata } from "./generate-cli-command-metadata.mjs";

const root = path.resolve(import.meta.dirname, "..");
const YAML = await loadYaml(root);
const failures = [];

const fail = (message) => failures.push(message);
const fileExists = (filePath) => {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
};

const requiredFiles = [
  "package.json",
  "pnpm-workspace.yaml",
  "docs/shared-cli-contract.yaml",
  "docs/regent-services-contract.openapiv3.yaml",
  "docs/ash-techtree-contract.openapiv3.yaml",
  "docs/json-rpc-methods.yaml",
  "docs/json-rpc-methods.md",
  "docs/schemas/wallet-action.schema.yaml",
  "packages/regents-cli/package.json",
  "packages/regents-cli/src/generated/cli-command-metadata.ts",
  "packages/regents-cli/src/generated/platform-openapi.ts",
  "packages/regents-cli/src/generated/ash-techtree-openapi.ts",
  "packages/regents-cli/src/generated/autolaunch-openapi.ts",
  "packages/regents-cli/src/generated/regent-services-openapi.ts",
];

for (const relativePath of requiredFiles) {
  if (!fileExists(path.resolve(root, relativePath))) {
    fail(`missing repository-local input: ${relativePath}`);
  }
}

for (const relativePath of [
  "scripts/render-meta.mjs",
  "packages/regents-cli/src/commands/meta.ts",
  "packages/regents-cli/src/workspace/manifest.js",
]) {
  if (fs.existsSync(path.resolve(root, relativePath))) {
    fail(`retired workspace machinery still exists: ${relativePath}`);
  }
}

const packageJson = JSON.parse(fs.readFileSync(path.resolve(root, "package.json"), "utf8"));
for (const scriptName of Object.keys(packageJson.scripts ?? {})) {
  if (scriptName === ["check", "meta"].join(":" ) || scriptName.startsWith(["meta", "render"].join(":"))) {
    fail(`retired workspace script is still public: ${scriptName}`);
  }
}

const cliContract = YAML.parse(fs.readFileSync(path.resolve(root, "docs/shared-cli-contract.yaml"), "utf8"));
if (cliContract?.version !== 1 || !Array.isArray(cliContract.command_groups)) {
  fail("docs/shared-cli-contract.yaml must use the local v1 command_groups contract");
}

const contractCommands = (cliContract.command_groups ?? []).flatMap((group) => group.commands ?? []);
const retiredCommands = new Set([["meta", "check"].join(" "), ["meta", "render"].join(" ")]);
for (const command of contractCommands) {
  if (retiredCommands.has(command)) {
    fail(`retired public command remains in docs/shared-cli-contract.yaml: ${command}`);
  }
}

const metadataCheck = checkCliCommandMetadata();
if (!metadataCheck.metadataOk) {
  fail(`generated CLI command metadata is out of date: ${path.relative(root, metadataCheck.outputPath)}`);
}
if (!metadataCheck.commandListOk) {
  fail(`generated CLI command list is out of date: ${path.relative(root, metadataCheck.commandListPath)}`);
}

const scanRoots = [
  "scripts",
  "packages/regents-cli/src",
  "packages/regents-cli/test",
  "docs",
];
const scanFiles = ["AGENTS.md", "HANDOFF.md", "README.md", "packages/regents-cli/README.md"];
const ignoredNames = new Set(["check-workspace.mjs"]);
const visit = (relativePath) => {
  const absolutePath = path.resolve(root, relativePath);
  if (!fs.existsSync(absolutePath)) return;
  const stat = fs.statSync(absolutePath);
  if (stat.isDirectory()) {
    for (const name of fs.readdirSync(absolutePath)) {
      if (!["node_modules", "dist"].includes(name)) visit(path.join(relativePath, name));
    }
    return;
  }
  if (!ignoredNames.has(path.basename(relativePath)) && !/^docs\/release-audit-/u.test(relativePath)) {
    scanFiles.push(relativePath);
  }
};
for (const relativePath of scanRoots) visit(relativePath);

const forbiddenFragments = [
  ["meta", "stack.yaml"].join("/"),
  ["repo", "yaml"].join("."),
  ["regents", "meta", "check"].join(" "),
  ["regents", "meta", "render"].join(" "),
  ["..", "platform", "contracts"].join("/"),
  ["regent", "platform"].join("/"),
];

for (const relativePath of new Set(scanFiles)) {
  const absolutePath = path.resolve(root, relativePath);
  if (!fileExists(absolutePath)) continue;
  const source = fs.readFileSync(absolutePath, "utf8");
  for (const fragment of forbiddenFragments) {
    if (source.includes(fragment)) {
      fail(`${relativePath} still depends on retired workspace input: ${fragment}`);
    }
  }
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("repository-local workspace check passed");
