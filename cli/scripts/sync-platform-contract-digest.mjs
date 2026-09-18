#!/usr/bin/env node
// Regenerates the CLI's expected Platform contract identity from the contract
// itself. Platform serves the same two values as response headers on
// GET /api-contract.openapiv3.yaml, so both sides move together.
//
//   node cli/scripts/sync-platform-contract-digest.mjs          # write
//   node cli/scripts/sync-platform-contract-digest.mjs --check  # verify
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const arguments_ = process.argv.slice(2);
const check = arguments_.length === 1 && arguments_[0] === "--check";
if (arguments_.length > 0 && !check) {
  console.error(`unknown arguments: ${arguments_.join(" ")}`);
  process.exit(2);
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const contractPath = resolve(root, "platform/contracts/api-contract.openapiv3.yaml");
const outputPath = resolve(
  root,
  "cli/packages/regents-cli/src/generated/platform-contract-digest.ts",
);

const contract = readFileSync(contractPath);
const major = /^  version:\s*(\d+)\./m.exec(contract.toString("utf8"))?.[1];
if (!major) {
  throw new Error(`no info.version in ${contractPath}`);
}
const digest = `sha256:${createHash("sha256").update(contract).digest("hex")}`;

const output = [
  "// Generated from platform/contracts/api-contract.openapiv3.yaml by",
  "// cli/scripts/sync-platform-contract-digest.mjs. Platform serves the same",
  "// two values as response headers on GET /api-contract.openapiv3.yaml.",
  "",
  `export const SUPPORTED_PLATFORM_CONTRACT_MAJOR = "${major}";`,
  "export const EXPECTED_PLATFORM_CONTRACT_DIGEST =",
  `  "${digest}";`,
  "",
].join("\n");

if (check) {
  if (readFileSync(outputPath, "utf8") !== output) {
    console.error("platform contract digest is out of sync");
    process.exit(1);
  }
  console.log("platform contract digest is synchronized");
} else {
  writeFileSync(outputPath, output);
  console.log(`wrote ${outputPath}`);
}
