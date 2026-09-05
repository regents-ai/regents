import fs from "node:fs";
import YAML from "yaml";

import { describe, expect, it } from "vitest";

import { renderJsonRpcMethodsDoc } from "../src/internal-runtime/jsonrpc/docs.js";
import { REGENT_RPC_METHODS } from "../src/internal-runtime/jsonrpc/methods.js";
import { TECHTREE_VERIFY_EXECUTORS } from "../src/internal-types/jsonrpc.js";

describe("JSON-RPC methods doc", () => {
  it("keeps the committed generated Markdown equal to renderer output", () => {
    const docsPath = new URL("../../../docs/json-rpc-methods.md", import.meta.url);
    const currentDoc = fs.readFileSync(docsPath, "utf8");

    expect(currentDoc).toBe(renderJsonRpcMethodsDoc());
  });

  it("keeps the YAML runtime contract aligned with the registry", () => {
    const contractPath = new URL("../../../docs/json-rpc-methods.yaml", import.meta.url);
    const contract = YAML.parse(fs.readFileSync(contractPath, "utf8"));
    const contractMethods = contract.methods.map((method: { name: string }) => method.name);

    expect(contractMethods).toEqual(Object.values(REGENT_RPC_METHODS));
    const verifyRun = contract.methods.find((method: { name: string }) => method.name === "techtree.verify.run");
    expect(verifyRun.params.executor.enum).toEqual(TECHTREE_VERIFY_EXECUTORS);
  });
});
