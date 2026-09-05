import fs from "node:fs";
import { resolve } from "node:path";
import { loadYaml } from "./dependency-preflight.mjs";

const root = resolve(import.meta.dirname, "..");
const YAML = await loadYaml(root);
const contractPath = resolve(root, "docs/shared-cli-contract.yaml");
const registryPath = resolve(root, "packages/regents-cli/src/mcp/tool-registry.ts");
const contract = YAML.parse(fs.readFileSync(contractPath, "utf8"));
const registrySource = fs.readFileSync(registryPath, "utf8");
const failures = [];
const fail = (message) => failures.push(message);

const sliceExportedArray = (source, exportName) => {
  const start = source.indexOf(`export const ${exportName}`);
  const assignment = source.indexOf("=", start);
  const open = source.indexOf("[", assignment);
  const constEnd = source.indexOf("] as const", open);
  const end = constEnd >= 0 ? constEnd : source.indexOf("];", open);
  if (start < 0 || assignment < 0 || open < 0 || end < 0) {
    throw new Error(`Unable to parse ${exportName} in ${registryPath}`);
  }
  return source.slice(open + 1, end);
};

const definitionPattern =
  /\{\s*name:\s*"([^"]+)",\s*title:\s*"([^"]+)",\s*description:\s*"([^"]+)",\s*riskClass:\s*"([^"]+)",\s*owner:\s*"([^"]+)",\s*authMode:\s*"([^"]+)",\s*(?:rpcMethod:\s*"([^"]+)",\s*)?\}/gu;
const definitions = sliceExportedArray(registrySource, "REGENTS_MCP_TOOL_DEFINITIONS");
const registryTools = Array.from(definitions.matchAll(definitionPattern), (match) => ({
  name: match[1], title: match[2], description: match[3], risk_class: match[4],
  owner: match[5], auth_mode: match[6], rpc_method: match[7],
}));
const declaredCount = Array.from(definitions.matchAll(/name:\s*"/gu)).length;
if (registryTools.length !== declaredCount) fail(`MCP registry parser matched ${registryTools.length} of ${declaredCount} tools`);

if (sliceExportedArray(registrySource, "REGENTS_MCP_SUBMIT_TOOLS").trim() !== "") {
  fail("REGENTS_MCP_SUBMIT_TOOLS must stay empty until submit tools are contract-approved");
}

const mcp = contract?.["x-regent-mcp-tools"];
if (!mcp || typeof mcp !== "object" || !Array.isArray(mcp.tools)) {
  fail("Shared CLI contract must define x-regent-mcp-tools.tools");
}
if (mcp?.submit_tools_enabled !== false) fail("Shared CLI contract must keep MCP submit tools disabled");

const contractTools = mcp?.tools ?? [];
const registryByName = new Map(registryTools.map((tool) => [tool.name, tool]));
const contractByName = new Map(contractTools.map((tool) => [tool.name, tool]));
if (registryByName.size !== registryTools.length) fail("MCP registry contains duplicate tool names");
if (contractByName.size !== contractTools.length) fail("Shared CLI contract contains duplicate MCP tool names");

for (const [name, tool] of registryByName) {
  const declared = contractByName.get(name);
  if (!declared) {
    fail(`Shared CLI contract is missing local MCP tool: ${name}`);
    continue;
  }
  for (const field of ["title", "description", "risk_class", "owner", "auth_mode", "rpc_method"]) {
    if (declared[field] !== tool[field]) fail(`MCP tool ${name} ${field} drifted`);
  }
}
for (const name of contractByName.keys()) {
  if (!registryByName.has(name)) fail(`Local MCP registry is missing contract tool: ${name}`);
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("repository-local MCP tools check passed");
