import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";
import YAML from "yaml";

import {
  collectCliHttpRouteIssues,
  formatCliHttpRouteIssue,
} from "../../../scripts/cli-http-route-check.mjs";

describe("CLI HTTP route contract check", () => {
  let tempDir = "";

  afterEach(() => {
    if (tempDir) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
    tempDir = "";
  });

  it("reports the command when a handler calls a route missing from the owning OpenAPI contract", () => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-cli-http-route-check-"));
    const autolaunchContract = path.join(tempDir, "autolaunch-api.openapiv3.yaml");
    fs.writeFileSync(
      autolaunchContract,
      YAML.stringify({
        openapi: "3.1.0",
        info: { title: "Autolaunch fixture", version: "0.0.0" },
        paths: {
          "/api/autolaunch/v1/agent/contracts/subjects/{id}/{resource}/{action}/prepare": {
            post: { operationId: "agentPrepareSubjectContractAction" },
          },
        },
      }),
      "utf8",
    );

    const routeSources = [
      `
        export const autolaunchHandlers = {
          "autolaunch subjects stake": { run: ({ parsedArgs, configPath }) => runAutolaunchSubjectStake(parsedArgs, configPath) },
          "autolaunch subjects sweep-ingress": { run: ({ parsedArgs, configPath }) => runAutolaunchSubjectSweepIngress(parsedArgs, configPath) },
        };
      `,
    ];
    const commandSources = [
      {
        path: "subjects.ts",
        source: `
          export async function runAutolaunchSubjectStake(args, configPath) {
            await requestJson("POST", \`/api/autolaunch/v1/agent/subjects/\${encodeURIComponent("subject_123")}/stake\`, {
              configPath,
            });
          }

          export async function runAutolaunchSubjectSweepIngress(args, configPath) {
            await prepareOrSubmitWalletAction(
              \`/api/autolaunch/v1/agent/contracts/subjects/\${encodeURIComponent("subject_123")}/ingress_account/sweep/prepare\`,
              {},
              args,
              configPath,
            );
          }
        `,
      },
    ];

    const issues = collectCliHttpRouteIssues({
      routeSources,
      commandSources,
      openApiFiles: { autolaunch: autolaunchContract },
      shippedCommands: new Set([
        "autolaunch subjects stake",
        "autolaunch subjects sweep-ingress",
      ]),
      YAML,
    });

    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({
      command: "autolaunch subjects stake",
      method: "POST",
      routeShape: "/api/autolaunch/v1/agent/subjects/{}/stake",
      likelyOwner: "autolaunch",
    });
    expect(formatCliHttpRouteIssue(issues[0], { autolaunch: autolaunchContract })).toContain(
      'CLI command "autolaunch subjects stake" calls missing API operation: POST /api/autolaunch/v1/agent/subjects/{}/stake',
    );
  });

  it("reports routes ending in a dynamic segment when they are missing from the contract", () => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-cli-http-route-check-"));
    const techtreeContract = path.join(tempDir, "techtree-api.openapiv3.yaml");
    fs.writeFileSync(
      techtreeContract,
      YAML.stringify({
        openapi: "3.1.0",
        info: { title: "Techtree fixture", version: "0.0.0" },
        paths: {
          "/api/techtree/v1/nodes/{node_id}": {
            get: { operationId: "getNode" },
          },
        },
      }),
      "utf8",
    );

    const routeSources = [
      `
        export const techtreeHandlers = {
          "fixture node get": { run: ({ parsedArgs, configPath }) => runFixtureNodeGet(parsedArgs, configPath) },
          "fixture node delete": { run: ({ parsedArgs, configPath }) => runFixtureNodeDelete(parsedArgs, configPath) },
        };
      `,
    ];
    const commandSources = [
      {
        path: "nodes.ts",
        source: `
          export async function runFixtureNodeGet(args, configPath) {
            await requestJson("GET", \`/api/techtree/v1/nodes/\${encodeURIComponent("node_123")}\`, { configPath });
          }

          export async function runFixtureNodeDelete(args, configPath) {
            await requestJson("DELETE", \`/api/techtree/v1/nodes/\${encodeURIComponent("node_123")}\`, { configPath });
          }
        `,
      },
    ];

    const issues = collectCliHttpRouteIssues({
      routeSources,
      commandSources,
      openApiFiles: { techtree: techtreeContract },
      shippedCommands: new Set(["fixture node get", "fixture node delete"]),
      YAML,
    });

    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({
      command: "fixture node delete",
      method: "DELETE",
      routeShape: "/api/techtree/v1/nodes/{}",
      likelyOwner: "techtree",
    });
  });
});
