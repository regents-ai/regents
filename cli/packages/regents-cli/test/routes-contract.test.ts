import { describe, expect, it } from "vitest";

import { CLI_COMMANDS } from "../src/command-registry.js";
import { parseCliArgs } from "../src/parse.js";
import { cliRoutes } from "../src/routes/index.js";
import { dispatchRoute, route, routeMatches, type CliRoute } from "../src/routes/shared.js";

const withoutPlaceholders = (command: string): string =>
  command
    .split(" ")
    .filter((part) => !(part.startsWith("<") && part.endsWith(">")))
    .join(" ");

const positionalsForRoute = (route: CliRoute): string[] =>
  route.pattern.map((part) => (part.startsWith("<") && part.endsWith(">") ? "sample-id" : part));

describe("contract command route matching", () => {
  it("has a route for every generated contract command", () => {
    for (const command of CLI_COMMANDS) {
      expect(
        cliRoutes.some(
          (route) => route.command === command || withoutPlaceholders(route.command) === command,
        ),
        command,
      ).toBe(true);
    }
  });

  it("keeps non-tail routes exact", () => {
    const nonTailRoutes = cliRoutes.filter((route) => !route.variadicTail);

    for (const route of nonTailRoutes) {
      expect(routeMatches(route, [...positionalsForRoute(route), "unexpected-tail"]), route.command).toBe(false);
    }
  });

  it("only variadic-tail routes accept extra positional words", () => {
    const variadicRoutes = cliRoutes.filter((route) => route.variadicTail);

    expect(variadicRoutes.map((route) => route.command).sort()).toEqual([
      "agent chat",
      "agentbook sessions watch",
      "autolaunch chat tail [scope...]",
      "autolaunch chat unread [scope...]",
      "autolaunch jobs watch",
      "autolaunch launch monitor",
      "doctor",
      "feynman",
      "regent-staking account",
      "regent-staking verify",
      "runtime checkpoint",
      "runtime get",
      "runtime health",
      "runtime pause",
      "runtime restore",
      "runtime resume",
      "runtime services",
      "work cancel",
      "work get",
      "work retry",
      "work run",
      "work watch",
      "x402 search",
    ]);

    for (const route of variadicRoutes) {
      expect(routeMatches(route, [...positionalsForRoute(route), "tail"]), route.command).toBe(true);
    }
  });

  it("does not let value slots consume known command words", () => {
    const autolaunchAgentRoute = cliRoutes.find((route) => route.command === "autolaunch agent <id>");

    expect(autolaunchAgentRoute).toBeDefined();
    expect(routeMatches(autolaunchAgentRoute!, ["autolaunch", "agent", "readiness"])).toBe(false);
  });

  it("dispatches to the most specific matching command", async () => {
    const parsedArgs = parseCliArgs(["doctor", "contracts"]);
    const routes = [
      route("doctor", async () => 1, { variadicTail: true }),
      route("doctor contracts", async () => 2),
    ];

    await expect(
      dispatchRoute(routes, {
        rawArgs: ["doctor", "contracts"],
        parsedArgs,
        configPath: undefined,
        positionals: parsedArgs.positionals,
      }),
    ).resolves.toBe(2);
  });
});
