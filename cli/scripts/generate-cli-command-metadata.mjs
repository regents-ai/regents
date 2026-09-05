import fs from "node:fs";
import { resolve } from "node:path";
import process from "node:process";
import { loadYaml } from "./dependency-preflight.mjs";

const root = resolve(import.meta.dirname, "..");
const YAML = await loadYaml(root);
const outputPath = resolve(root, "packages/regents-cli/src/generated/cli-command-metadata.ts");
const commandListPath = resolve(root, "docs/regents-cli-command-list.md");
const sharedCliContractPath = resolve(root, "docs/shared-cli-contract.yaml");
const routesDirectory = resolve(root, "packages/regents-cli/src/routes");

const parseYaml = (file) => YAML.parse(fs.readFileSync(file, "utf8"));
const normalizeCommandName = (command) => command.replace(/^regents?\s+/u, "");
const topLevelGroup = (command) => command.split(" ")[0];
const commandKey = (command) => command.replace(/^regents?\s+/u, "").replace(/[<>\s-]+/gu, "_");
const humanize = (value) =>
  value
    .replace(/[<>]/gu, "")
    .replace(/[-_]+/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();

const isPlaceholder = (part) => /^<[^>]+>$/u.test(part);
const sentenceCase = (value) => (value.length === 0 ? value : `${value.charAt(0).toUpperCase()}${value.slice(1)}`);
const articleFor = (value) => (/^[aeiou]/iu.test(value) ? "an" : "a");
const terminalLabel = (value) =>
  value
    .replace(/\bmcp\b/giu, "MCP")
    .replace(/\bens\b/giu, "ENS")
    .replace(/\btechtree\b/giu, "Techtree")
    .replace(/\bautolaunch\b/giu, "Autolaunch")
    .replace(/\bsiwa\b/giu, "SIWA")
    .replace(/\bbbh\b/giu, "BBH")
    .replace(/\btech\b/giu, "TECH")
    .replace(/\borcid\b/giu, "ORCID")
    .replace(/\busdc\b/giu, "USDC")
    .replace(/\bregent\b/giu, "REGENT")
    .replace(/\bx402\b/giu, "x402");

const summaryOverrides = new Map([
  ["auth login", "Sign in for protected Regent commands."],
  ["auth logout", "Sign out on this machine."],
  ["auth status", "Show the current saved sign-in."],
  ["budget grant", "Give an agent a spending budget."],
  ["budget ledger", "Show budget activity."],
  ["budget revoke", "Revoke an agent budget."],
  ["budget status", "Show the current budget state."],
  ["config get", "Show local Regent configuration."],
  ["config write", "Save local Regent configuration."],
  ["doctor", "Check local Regent readiness."],
  ["ens set-primary", "Set the primary ENS name."],
  ["feynman", "Open the Feynman research shell."],
  ["identity ensure", "Set up or confirm the local Agent identity."],
  ["identity graph", "Show linked identity records."],
  ["identity status", "Show local identity readiness."],
  ["mcp doctor", "Check MCP setup."],
  ["mcp export codex", "Print MCP setup for Codex."],
  ["mcp serve", "Start the Regents MCP server."],
  ["plugin doctor", "Check plugin setup."],
  ["plugin install", "Install a Regent plugin for the selected runtime."],
  ["plugin status", "Show installed Regent plugins."],
  ["receipt create", "Create a payment receipt record."],
  ["receipt share-draft", "Draft shareable receipt details."],
  ["run", "Start local Regent access for agents and terminal commands."],
  ["runtime policy", "Show runtime policy settings."],
  ["runtime tools", "List runtime tools."],
  ["setup", "Show setup guidance."],
  ["setup skills", "Install recommended Regent skills."],
  ["wallet setup", "Set up the local wallet path."],
  ["wallet status", "Show wallet readiness."],
  ["wallet agentic balance", "Show the Agent wallet balance."],
  ["wallet agentic fund", "Show how to fund the Agent wallet."],
  ["wallet agentic login", "Sign in with the Agent wallet."],
  ["wallet agentic status", "Show Agent wallet readiness."],
  ["wallet agentic verify", "Verify the Agent wallet sign-in."],
  ["x402 details", "Show paid endpoint details."],
  ["x402 fetch", "Fetch a paid x402 result."],
  ["x402 pay", "Pay an x402 endpoint."],
  ["x402 prepare", "Prepare an x402 paid request."],
  ["x402 quote", "Quote an x402 paid request."],
  ["x402 refund", "Request an x402 refund."],
  ["x402 search", "Search for x402 services."],
  ["techtree activity", "Show recent Techtree activity."],
  ["techtree chat list", "List Techtree chat channels."],
  ["techtree chat read <scope>", "Show chat messages for a scope."],
  ["techtree chat tail [scope...]", "Watch live chat messages for one or more scopes."],
  ["techtree chat send <scope>", "Send a chat message to a scope."],
  ["techtree chat unread [scope...]", "Show new chat messages since the saved cursors."],
  ["techtree chat subscribe add <scope>", "Add a scope to the saved Techtree chat subscriptions."],
  ["techtree chat subscribe remove <scope>", "Remove a scope from the saved Techtree chat subscriptions."],
  ["techtree chat subscribe list", "List the saved Techtree chat subscriptions."],
  ["autolaunch chat unread [scope...]", "Show new chat messages since the saved cursors."],
  ["autolaunch chat subscribe add <scope>", "Add a scope to the saved Autolaunch chat subscriptions."],
  ["autolaunch chat subscribe remove <scope>", "Remove a scope from the saved Autolaunch chat subscriptions."],
  ["autolaunch chat subscribe list", "List the saved Autolaunch chat subscriptions."],
  ["chat follows add <wallet|label>", "Add a wallet or label to the saved chat follow list."],
  ["chat follows remove <wallet|label>", "Remove a wallet or label from the saved chat follow list."],
  ["chat follows list", "List the saved chat follow list."],
  ["techtree dm <node-id|address>", "Send a direct message to a node author or wallet address."],
  ["techtree dm list", "List server-stored direct message scopes."],
  ["techtree autoskill review", "Review an autoskill package."],
  ["techtree inbox", "Show your Techtree inbox."],
  ["techtree opportunities", "Show available Techtree opportunities."],
  ["techtree runbook invite-request <question_id>", "Invite help on a Runbook question."],
  ["techtree runbook mark-solved <question_id>", "Mark a Runbook question solved."],
  ["techtree runbook questions get <id>", "Show a Runbook question."],
  ["techtree runbook unlock <answer_id>", "Unlock a paid Runbook answer."],
  ["techtree science-tasks review-loop", "Run the science-task review loop."],
  ["techtree science-tasks review-update", "Update a science-task review."],
  ["techtree search", "Search Techtree."],
  ["techtree star <id>", "Star a Techtree node."],
  ["techtree start", "Open the Techtree start flow."],
  ["techtree unstar <id>", "Remove a Techtree node star."],
  ["techtree unwatch <id>", "Stop watching a Techtree node."],
  ["techtree watch <id>", "Watch a Techtree node."],
  ["techtree watch tail", "Watch updates from followed Techtree nodes."],
]);

const resourceLabel = (group, resourceParts) => {
  const words = resourceParts.filter((part) => !isPlaceholder(part));
  if (words.length === 0) {
    return terminalLabel(humanize(group));
  }

  return terminalLabel(humanize(words.join(" ")));
};

const splitAction = (action) => {
  const [verb, ...rest] = action.split("-");
  return { verb, qualifier: terminalLabel(humanize(rest.join(" "))) };
};

const knownActionVerbs = new Set([
  "accept",
  "activate",
  "add",
  "admins",
  "apply",
  "attach",
  "buy",
  "cancel",
  "checklist",
  "claim",
  "clear",
  "confirm",
  "create",
  "current",
  "details",
  "doctor",
  "edit",
  "evidence",
  "execute",
  "exit",
  "export",
  "fetch",
  "finalize",
  "get",
  "health",
  "history",
  "improve",
  "init",
  "invite",
  "leaderboard",
  "link",
  "list",
  "lookup",
  "mark",
  "materialize",
  "members",
  "migrate",
  "mint",
  "monitor",
  "next",
  "open",
  "pack",
  "pair",
  "pay",
  "permissions",
  "place",
  "post",
  "prepare",
  "preview",
  "proof",
  "proposals",
  "propose",
  "publish",
  "pull",
  "quote",
  "readiness",
  "ready",
  "refund",
  "register",
  "release",
  "remove",
  "repeat",
  "report",
  "rescue",
  "restore",
  "resume",
  "revoke",
  "review",
  "rotate",
  "run",
  "score",
  "search",
  "set",
  "solve",
  "stake",
  "star",
  "start",
  "status",
  "submit",
  "super",
  "sweep",
  "sync",
  "tail",
  "unstar",
  "unstake",
  "unwatch",
  "unlock",
  "update",
  "validate",
  "verify",
  "vote",
  "watch",
  "withdraw",
  "wizard",
  "write",
]);

const findActionIndex = (parts) => {
  for (let index = parts.length - 1; index >= 0; index -= 1) {
    if (knownActionVerbs.has(splitAction(parts[index]).verb)) {
      return index;
    }
  }
  return -1;
};

const actionSummary = (group, tail) => {
  const nonPlaceholderTail = tail.filter((part) => !isPlaceholder(part));
  const actionIndex = findActionIndex(nonPlaceholderTail);

  if (actionIndex === -1) {
    return `Show ${resourceLabel(group, [group, ...nonPlaceholderTail])}.`;
  }

  const action = nonPlaceholderTail[actionIndex] ?? group;
  const { verb, qualifier } = splitAction(action);
  const resource = resourceLabel(group, [
    ...nonPlaceholderTail.slice(0, actionIndex),
    ...nonPlaceholderTail.slice(actionIndex + 1),
  ]);
  const qualifiedResource = qualifier ? `${qualifier} for ${resource}` : resource;

  switch (verb) {
    case "account":
    case "details":
    case "get":
    case "lookup":
    case "projection":
      return `Show ${resource}.`;
    case "list":
      return `List ${resource}.`;
    case "admins":
    case "members":
    case "permissions":
    case "proposals":
    case "super":
      return `List ${resourceLabel(group, nonPlaceholderTail)}.`;
    case "status":
    case "health":
      return `Show ${resource} status.`;
    case "init":
      return `Set up ${resource}.`;
    case "create":
    case "mint":
    case "register":
      return `Create ${qualifiedResource}.`;
    case "add":
      return `Add ${qualifier ? `${qualifier} to ` : ""}${resource}.`;
    case "remove":
    case "clear":
    case "revoke":
      return `Remove ${qualifier ? `${qualifier} from ` : ""}${resource}.`;
    case "set":
    case "write":
      return `Set ${qualifiedResource}.`;
    case "link":
      return `Link ${qualifiedResource}.`;
    case "pair":
      return `Pair ${resource}.`;
    case "post":
      return `Post ${qualifiedResource}.`;
    case "publish":
      return `Publish ${qualifiedResource}.`;
    case "submit":
      return `Submit ${qualifiedResource}.`;
    case "watch":
    case "tail":
    case "monitor":
      return `Watch ${qualifiedResource}.`;
    case "claim":
      return `Claim ${qualifiedResource}.`;
    case "stake":
      return `Stake ${resource}.`;
    case "unstake":
      return `Unstake ${resource}.`;
    case "prepare":
      return `Prepare ${qualifiedResource}.`;
    case "preview":
      return `Preview ${resource}.`;
    case "validate":
    case "verify":
    case "doctor":
      return `Check ${resource}.`;
    case "quote":
      return `Quote ${resource}.`;
    case "run":
      return `Run ${resource}.`;
    case "buy":
      return `Buy ${resource}.`;
    case "pay":
      return `Pay ${resource}.`;
    case "fetch":
    case "pull":
      return `Fetch ${resource}.`;
    case "unlock":
      return `Unlock ${resource}.`;
    case "refund":
      return `Refund ${resource}.`;
    case "search":
      return `Search ${resource}.`;
    case "start":
      return `Start ${resource}.`;
    case "apply":
      return `Apply ${qualifiedResource}.`;
    case "accept":
      return `Accept ${qualifiedResource}.`;
    case "activate":
      return `Activate ${qualifiedResource}.`;
    case "attach":
      return `Attach ${qualifiedResource}.`;
    case "cancel":
      return `Cancel ${qualifiedResource}.`;
    case "confirm":
      return `Confirm ${qualifiedResource}.`;
    case "execute":
      return `Execute ${qualifiedResource}.`;
    case "finalize":
      return `Finalize ${resource}.`;
    case "release":
      return `Release ${resource}.`;
    case "restore":
      return `Restore ${resource}.`;
    case "pause":
      return `Pause ${resource}.`;
    case "resume":
      return `Resume ${resource}.`;
    case "open":
      return `Open ${resource}.`;
    case "edit":
      return `Edit ${resource}.`;
    case "sweep":
      return `Sweep ${qualifiedResource}.`;
    case "update":
      return `Update ${qualifiedResource}.`;
    case "migrate":
      return `Migrate ${resource}.`;
    case "rotate":
      return `Rotate ${qualifiedResource}.`;
    case "rescue":
      return `Rescue ${resource}.`;
    case "ready":
      return `Mark ${resource} ready.`;
    case "mark":
      return `Mark ${resource}${qualifier ? ` ${qualifier}` : ""}.`;
    case "vote":
      return `Vote on ${resource}.`;
    case "invite":
      return `Invite help for ${resource}.`;
    case "score":
      return `Score ${resource}.`;
    case "improve":
      return `Improve ${resource}.`;
    case "solve":
      return `Solve ${resource}.`;
    case "materialize":
      return `Materialize ${resource}.`;
    case "repeat":
      return `Repeat ${resource}.`;
    case "pack":
      return `Pack ${resource}.`;
    case "sync":
      return `Sync ${resource}.`;
    case "review":
      return `Review ${resource}.`;
    case "exit":
      return `Exit ${resource}.`;
    case "place":
      return `Place ${resource}.`;
    case "withdraw":
      return `Withdraw ${resource}.`;
    case "current":
      return `Show current ${resource}.`;
    case "history":
      return `Show ${resource} history.`;
    case "leaderboard":
      return `Show ${resource} leaderboard.`;
    case "proof":
      return `Show ${resource} proof.`;
    case "report":
      return `Create ${resource} report.`;
    case "wizard":
      return `Open ${resource} wizard.`;
    case "checklist":
      return `Show ${resource} checklist.`;
    case "evidence":
      return `Show ${resource} evidence.`;
    case "export":
      return `Export ${resource}.`;
    case "next":
      return `Show the next ${resource}.`;
    case "readiness":
      return `Show ${resource} readiness.`;
    case "plan":
      return `Plan ${resource}.`;
    case "by":
      return `Find ${qualifiedResource}.`;
    default:
      return `${sentenceCase(terminalLabel(humanize(action)))} ${resource}.`;
  }
};

const verbSummary = (command) => {
  const override = summaryOverrides.get(command);
  if (override) {
    return override;
  }

  const parts = command.split(" ");
  const tail = parts.slice(1);
  const group = parts[0] ?? command;

  if (command === "init") return "Set up the local Regents config and working folders.";
  if (command === "status") return "Show whether this machine is ready to use Regent.";
  if (command === "whoami") return "Show the local Agent account and saved sign-in context.";
  if (command === "run") return "Start local Regent access for agents and terminal commands.";
  if (command === "agent-context") return "Print the safe command and setup context for another agent.";
  if (command === "bug") return "Send a signed bug report to Regents.";
  if (command === "security-report") return "Send a signed security report to Regents.";

  return actionSummary(group, tail);
};

const commandSummary = (command, existing) => {
  if (typeof existing === "string" && existing.trim().length > 0) {
    return existing;
  }
  return verbSummary(command);
};

const compactObject = (value) => {
  if (!value || typeof value !== "object") {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(compactObject);
  }

  return Object.fromEntries(
    Object.entries(value)
      .filter(([, entryValue]) => entryValue !== undefined)
      .map(([key, entryValue]) => [key, compactObject(entryValue)]),
  );
};

const metadataWithoutExamples = (metadata) => {
  if (!metadata || typeof metadata !== "object") {
    return undefined;
  }

  const { examples: _examples, commands: _commands, ...rest } = metadata;
  return compactObject(rest);
};

const literalCommandTokens = (command) =>
  command
    .split(" ")
    .filter((part) => !part.startsWith("<") && !part.startsWith("["));

const commandSpecificMapValue = (map, normalizedCommand) => {
  if (!map || typeof map !== "object") {
    return undefined;
  }

  const literalTokens = literalCommandTokens(normalizedCommand);

  return (
    map[normalizedCommand] ??
    map[`regents ${normalizedCommand}`] ??
    map[commandKey(normalizedCommand)] ??
    map[literalTokens.join(" ")] ??
    map[literalTokens.slice(1).join(" ")] ??
    map[normalizedCommand.split(" ").at(-1)]
  );
};

const readGroupArgs = (group, normalizedCommand) =>
  commandSpecificMapValue(group.command_args, normalizedCommand) ??
  commandSpecificMapValue(group.args, normalizedCommand);

const readGroupFlags = (group, normalizedCommand) =>
  commandSpecificMapValue(group.command_flags, normalizedCommand) ??
  commandSpecificMapValue(group.flags, normalizedCommand);

const readAgentMetadata = (agentMetadata, normalizedCommand) => {
  if (!agentMetadata || typeof agentMetadata !== "object") {
    return undefined;
  }

  const commandOverrides = commandSpecificMapValue(agentMetadata.commands, normalizedCommand);
  const { commands: _commands, ...defaults } = agentMetadata;
  if (!commandOverrides) {
    return compactObject(defaults);
  }

  return compactObject({ ...defaults, ...commandOverrides });
};

const readContractGroups = (owner, contract) => {
  if (contract?.openapi || Array.isArray(contract?.commands) || contract?.version !== 1) {
    throw new Error("CLI contracts must use the v1 command_groups schema.");
  }

  return (contract.command_groups ?? []).map((group) => ({
    owner,
    name: typeof group.name === "string" ? group.name : owner,
    commands: (group.commands ?? []).map(normalizeCommandName),
    commandDetails: (group.commands ?? []).map((command) => {
      const normalizedCommand = normalizeCommandName(command);
      const agentMetadata = readAgentMetadata(group.agent_metadata, normalizedCommand);
      const help = group.help ?? {};
      // Group-level usage only describes the command itself when the group
      // ships exactly one command; otherwise leave usage unset so the CLI
      // derives it from the command name and its required flags.
      const singleCommandGroup = (group.commands ?? []).length === 1;

      return compactObject({
        command: normalizedCommand,
        owner,
        group: typeof group.name === "string" ? group.name : owner,
        interface: group.interface,
        auth_mode: agentMetadata?.auth_mode ?? group.auth_mode,
        auth_audience: agentMetadata?.auth_audience ?? group.auth_audience,
        output_envelope: group.output_envelope,
        args: readGroupArgs(group, normalizedCommand),
        flags: readGroupFlags(group, normalizedCommand),
        examples: agentMetadata?.examples ?? group.examples,
        agent_metadata: metadataWithoutExamples(agentMetadata),
        summary: commandSummary(normalizedCommand, agentMetadata?.summary),
        usage: singleCommandGroup ? help.usage ?? group.usage : undefined,
        next_step: agentMetadata?.next_step ?? help.next_step ?? group.next_step,
      });
    }),
  }));
};

const routeCommands = () => {
  const commands = fs.readdirSync(routesDirectory)
    .filter((filename) => filename.endsWith(".ts") && !["index.ts", "shared.ts"].includes(filename))
    .flatMap((filename) => {
      const source = fs.readFileSync(resolve(routesDirectory, filename), "utf8");
      return Array.from(
        source.matchAll(/^  (?:(?:"([^"]+)")|([A-Za-z][A-Za-z0-9_-]*)):\s*\{/gmu),
        (match) => match[1] ?? match[2],
      );
    });

  if (new Set(commands).size !== commands.length) {
    throw new Error("CLI route handler registries contain duplicate commands.");
  }
  return commands.sort();
};

const existingCommandDetails = () => {
  if (!fs.existsSync(outputPath)) return {};
  const source = fs.readFileSync(outputPath, "utf8");
  const marker = "export const CLI_COMMAND_DETAILS_BY_COMMAND = ";
  const start = source.indexOf(marker);
  const end = source.indexOf(" as const;", start);
  if (start < 0 || end < 0) return {};
  return JSON.parse(source.slice(start + marker.length, end));
};

export const buildCliCommandMetadata = () => {
  const groups = readContractGroups("shared-services", parseYaml(sharedCliContractPath));
  const commands = routeCommands();
  const commandSet = new Set(commands);
  for (const command of groups.flatMap((group) => group.commands)) {
    if (!commandSet.has(command)) {
      throw new Error(`Local CLI contract command has no route handler: ${command}`);
    }
  }
  const topLevelGroups = Array.from(new Set(commands.map(topLevelGroup))).sort();
  const commandsByTopLevelGroup = Object.fromEntries(
    topLevelGroups.map((groupName) => [
      groupName,
      commands.filter((command) => command === groupName || command.startsWith(`${groupName} `)),
    ]),
  );
  const contractDetails = new Map(
    groups.flatMap((group) => group.commandDetails ?? []).map((detail) => [detail.command, detail]),
  );
  const previousDetails = existingCommandDetails();
  const commandDetails = commands.map((command) => contractDetails.get(command) ?? previousDetails[command] ?? {
    command,
    owner: "regents-cli",
    group: topLevelGroup(command),
    summary: commandSummary(command),
  });
  const commandDetailsByCommand = Object.fromEntries(
    commandDetails.map((detail) => [detail.command, detail]),
  );

  return { commands, commandsByTopLevelGroup, commandDetails, commandDetailsByCommand };
};

const generatedHeader = [
  "// Generated by scripts/generate-cli-command-metadata.mjs.",
  "// Sources: local route registries, docs/shared-cli-contract.yaml, and checked-in product command details.",
  "",
];

export const renderCliCommandMetadata = () => {
  const metadata = buildCliCommandMetadata();
  return [
    ...generatedHeader,
    `export const CLI_COMMANDS = ${JSON.stringify(metadata.commands, null, 2)} as const;`,
    "",
    `export const CLI_COMMANDS_BY_TOP_LEVEL_GROUP = ${JSON.stringify(
      metadata.commandsByTopLevelGroup,
      null,
      2,
    )} as const;`,
    "",
    `export const CLI_COMMAND_DETAILS_BY_COMMAND = ${JSON.stringify(
      metadata.commandDetailsByCommand,
      null,
      2,
    )} as const;`,
    "",
  ].join("\n");
};

const titleCaseGroup = (groupName) =>
  groupName
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");

export const renderCliCommandList = () => {
  const metadata = buildCliCommandMetadata();
  return [
    "# Regents CLI Command List",
    "",
    "This file lists the full command surface shipped by the standalone Regents CLI in this repo.",
    "",
    "Sources used: repository-local route registries and `docs/shared-cli-contract.yaml` via `scripts/generate-cli-command-metadata.mjs`.",
    "",
    `Total commands: ${metadata.commands.length}.`,
    "",
    "## Full Command List",
    "",
    ...Object.entries(metadata.commandsByTopLevelGroup).flatMap(([groupName, commands]) => [
      `### ${titleCaseGroup(groupName)}`,
      "",
      ...commands.map((command) => {
        const detail = metadata.commandDetailsByCommand[command];
        return detail?.summary
          ? `- \`regents ${command}\` - ${detail.summary}`
          : `- \`regents ${command}\``;
      }),
      "",
    ]),
  ].join("\n");
};

export const checkCliCommandMetadata = () => {
  const expected = renderCliCommandMetadata();
  const actual = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, "utf8") : "";
  const expectedCommandList = renderCliCommandList();
  const actualCommandList = fs.existsSync(commandListPath)
    ? fs.readFileSync(commandListPath, "utf8")
    : "";
  return {
    ok: actual === expected && actualCommandList === expectedCommandList,
    metadataOk: actual === expected,
    commandListOk: actualCommandList === expectedCommandList,
    expected,
    actual,
    expectedCommandList,
    actualCommandList,
    outputPath,
    commandListPath,
  };
};

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const checkOnly = process.argv.includes("--check");
  const result = checkCliCommandMetadata();

  if (checkOnly) {
    if (!result.ok) {
      if (!result.metadataOk) {
        console.error(`Generated CLI command metadata is out of date: ${outputPath}`);
      }
      if (!result.commandListOk) {
        console.error(`Generated CLI command list is out of date: ${commandListPath}`);
      }
      console.error("Run pnpm generate:cli-command-metadata.");
      process.exitCode = 1;
    }
  } else {
    fs.writeFileSync(outputPath, result.expected);
    fs.writeFileSync(commandListPath, result.expectedCommandList);
  }
}
