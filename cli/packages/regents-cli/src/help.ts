import { CliUsageError } from "./cli-usage-error.js";
import { CLI_COMMANDS, knownCliCommand } from "./command-registry.js";
import {
  CLI_COMMANDS_BY_TOP_LEVEL_GROUP,
  CLI_COMMAND_DETAILS_BY_COMMAND,
} from "./generated/cli-command-metadata.js";
import { CLI_PALETTE, printText, renderBanner, renderPanel, tone } from "./printer.js";
import { padRight } from "./terminal/palette.js";

interface HelpEntry {
  readonly summary: string;
  readonly usage: string;
  readonly flags?: readonly string[];
  readonly examples?: readonly string[];
  readonly prerequisites?: readonly string[];
  readonly auth: string;
  readonly output: string;
  readonly nextStep: string;
  readonly ifItFails?: readonly string[];
}

interface HelpGroup {
  readonly summary: string;
  readonly auth: string;
  readonly output: string;
  readonly commands: readonly string[];
  readonly nextStep: string;
}

interface CommandFieldMetadata {
  readonly name?: string;
  readonly type?: string;
  readonly enum?: readonly string[];
  readonly required?: boolean;
  readonly description?: string;
}

interface CommandAgentMetadata {
  readonly json_support?: string;
  readonly mutation_class?: string;
  readonly async_behavior?: string;
  readonly auth_mode?: string;
}

interface CommandDetailMetadata {
  readonly command: string;
  readonly group?: string;
  readonly auth_mode?: string;
  readonly auth_audience?: string;
  readonly output_envelope?: string;
  readonly args?: unknown;
  readonly flags?: unknown;
  readonly examples?: readonly string[];
  readonly agent_metadata?: CommandAgentMetadata;
  readonly summary?: string;
  readonly usage?: string;
  readonly next_step?: string;
}

const commandDetailsByCommand = CLI_COMMAND_DETAILS_BY_COMMAND as unknown as Readonly<
  Record<string, CommandDetailMetadata>
>;

const globalNextStep =
  "Install the Regents agent skills with `regents setup skills`, then run `regents status`.";

const localRuntimePrerequisites = [
  "Install the matching runtime tools with `regents plugin install --runtime hermes`, `regents plugin install --runtime openclaw`, or `regents plugin install --runtime auto`.",
  "Keep `regents run` open in another terminal for commands that need local Regent access.",
];

const agentIdentityPrerequisites = [
  "Run `regents run` in another terminal.",
  "Run `regents auth login --audience <audience>` for the product you are using.",
  "Run `regents identity ensure` so signed agent requests have wallet, chain, registry, and token details.",
];

const autolaunchPrerequisites = [
  "Run `regents run` in another terminal.",
  "Run `regents auth login --audience autolaunch`.",
  "Run `regents identity ensure`.",
];

const techtreePrerequisites = [
  "Run `regents run` in another terminal.",
  "Choose a local workspace path for the notebook.",
];

const platformPrerequisites = [
  "Run `regents platform auth login` with a Regent website access token.",
  "Use the correct regent id or slug from the Regent website.",
];

const serviceOwnerPrerequisites = [
  "Run `regents platform auth login` with a Regent website access token.",
  "Use these commands only for a service you own or administer.",
  "Buyers use `regents x402 details`, `quote`, `prepare`, `fetch`, or `pay` for paid service calls.",
];

const walletPrerequisites = [
  "Use `regents wallet status` to see whether a local wallet source is already configured.",
  "Do not paste private keys into shared logs or public prompts.",
];

const paymentPrerequisites = [
  "Run `regents wallet agentic status` before paid x402 work.",
  "Run `regents budget status` and make sure the named budget has enough remaining allowance.",
];

const autolaunchFailureChecks = [
  "If the command says auth is missing, run `regents auth login --audience autolaunch` and `regents identity ensure`.",
  "If a wallet or signer is missing, run `regents wallet status` and use the exact missing flag named in the error.",
  "If the result is not ready, run the read/status command shown in the output before trying the next write.",
];

const autolaunchWalletActionPrerequisites = [
  ...autolaunchPrerequisites,
  "Use a wallet that can review and sign the prepared action before any onchain submit step.",
  "Check that the wallet has enough token balance and network fees before a bid, claim, release, or finalize command.",
];

const techtreeFailureChecks = [
  "If the command cannot connect locally, start `regents run` in another terminal.",
  "If a workspace path is missing, create or pass the same folder path through the notebook flow.",
];

// Bespoke help overlay keyed by command. The full help SKELETON (summary,
// usage, examples, next step, auth, args, flags) is rendered from
// CLI_COMMAND_DETAILS_BY_COMMAND via summarizeCommand. This overlay holds ONLY
// the prose that is richer than, or absent from, that metadata skeleton:
// prerequisites, "if it fails" failure checks, extended output descriptions,
// and the handful of summary/usage/flags/examples/next-step strings whose
// hand-written wording carries more detail than the generated stub. No field
// that is identical to the skeleton is kept here; each command is rendered as
// mergeHelp(summarizeCommand(command), commandHelpOverlay[command]).
const commandHelpOverlay: Record<string, Partial<HelpEntry>> = {
  setup: {
    summary: "Set up Regents for the agent runtimes on this machine.",
    usage: "regents setup [--quick] [--runtime <auto|hermes|openclaw>]",
    flags: [
      "--quick installs missing plugins and MCP registrations without prompting.",
      "--runtime auto (default) covers every detected runtime.",
      "--runtime hermes or --runtime openclaw narrows the status report.",
      "--json prints the read-only status report.",
      "--config <path>",
    ],
    examples: ["regents setup", "regents setup --quick", "regents setup --json"],
    output:
      "On a terminal, runs the setup wizard: detects Hermes, OpenClaw, Claude Code, and Codex, and registers the regents MCP server. Use `regents plugin install --runtime ...` for Hermes and OpenClaw tools. With --runtime, --json, or no terminal, prints the readiness report instead.",
    nextStep: "Run `regents identity ensure`, then `regents doctor`.",
  },
  version: {
    summary: "Print the installed Regents CLI version.",
    usage: "regents version [--json]",
    flags: ["--json"],
    examples: ["regents version", "regents --version"],
    output: "The version string, or {name, version} with --json.",
    nextStep: "Update with `regents update`.",
  },
  update: {
    summary: "Update the Regents CLI in place via npm.",
    usage: "regents update [--version <x.y.z>] [--json]",
    flags: [
      "--version <x.y.z> installs a specific release instead of the latest.",
      "--json",
    ],
    examples: ["regents update", "regents update --version 0.6.0"],
    output: "Streams the npm install and reports the result.",
    nextStep: "Run `regents setup --quick` to refresh plugins after updating.",
  },
  "setup skills": {
    summary: "Install the Regents agent skills for supported agent clients.",
    usage: "regents setup skills [--project]",
    flags: ["--project", "--json", "--no-input"],
    examples: ["regents setup skills", "regents setup skills --project"],
    output: "Shows which Regents skills were installed and where they came from.",
    nextStep: "Open your agent client and use the installed Regents skills.",
  },
  "plugin install": {
    summary: "Install the Regent tools into Hermes, OpenClaw, or both.",
    usage: "regents plugin install [--runtime <auto|hermes|openclaw>]",
    flags: [
      "--runtime auto (default) installs both sets of tools. Use this when the machine may run either Hermes or OpenClaw.",
      "--runtime hermes installs the Hermes tools and selects xAI Grok OAuth with grok-4.3.",
      "--runtime openclaw installs only the OpenClaw tools. Use this for an OpenClaw agent.",
      "--json",
      "--config <path>",
    ],
    examples: [
      "regents plugin install",
      "regents plugin install --runtime hermes",
      "regents plugin install --runtime openclaw",
    ],
    output:
      "Shows which runtime was selected, which tool files were written, and the Hermes sign-in command when Hermes is selected.",
    nextStep:
      "For Hermes, run `hermes auth add xai-oauth`, then run `regents plugin status --runtime hermes` and start Regent with `regents run`.",
  },
  "plugin status": {
    summary: "Check whether Hermes, OpenClaw, or both can see the Regent tools.",
    usage: "regents plugin status [--runtime <auto|hermes|openclaw>]",
    flags: [
      "--runtime auto (default) checks both Hermes and OpenClaw.",
      "--runtime hermes checks only Hermes.",
      "--runtime openclaw checks only OpenClaw.",
      "--json",
      "--config <path>",
    ],
    examples: [
      "regents plugin status --runtime auto",
      "regents plugin status --runtime hermes",
      "regents plugin status --runtime openclaw",
    ],
    output:
      "Shows each selected runtime, whether its Regent tools are installed, and the local path that was checked.",
    nextStep:
      "If the intended runtime is missing, run `regents plugin install --runtime hermes` or `regents plugin install --runtime openclaw`.",
  },
  "plugin doctor": {
    summary: "Diagnose missing Regent tools for Hermes, OpenClaw, or both.",
    usage: "regents plugin doctor [--runtime <auto|hermes|openclaw>]",
    flags: [
      "--runtime auto (default) diagnoses both Hermes and OpenClaw.",
      "--runtime hermes diagnoses only Hermes.",
      "--runtime openclaw diagnoses only OpenClaw.",
      "--json",
      "--config <path>",
    ],
    examples: [
      "regents plugin doctor --runtime auto",
      "regents plugin doctor --runtime hermes",
      "regents plugin doctor --runtime openclaw",
    ],
    output:
      "Shows which runtimes are ready and which ones are missing Regent tools. This is the command to run when Hermes or OpenClaw says Regent tools are unavailable.",
    nextStep:
      "Install the missing runtime with `regents plugin install --runtime hermes`, `regents plugin install --runtime openclaw`, or `regents plugin install --runtime auto`.",
  },
  feynman: {
    summary: "Open the Feynman research shell from Regents CLI.",
    usage: "regents feynman [feynman command or prompt]",
    flags: ["Feynman flags are passed through after `regents feynman`."],
    examples: [
      "regents feynman setup",
      "regents feynman doctor",
      'regents feynman chat "explain this paper"',
    ],
    auth: "Feynman manages its own setup.",
    output: "Shows Feynman's terminal output directly.",
  },
  "regent-staking get": {
    summary: "Show Regent staking totals for the saved Agent account.",
    flags: ["--config <path>"],
    output: "Shows staking balances and claimable amounts.",
    nextStep: "Use the stake, unstake, or claim command that matches the account state.",
  },
  "regent-staking stake": {
    summary: "Prepare a $REGENT staking transaction.",
    usage: "regents regent-staking stake --amount <amount> [--receiver <0xaddress>]",
    flags: ["--amount <amount>", "--receiver <0xaddress>", "--submit", "--config <path>"],
    examples: [
      "regents regent-staking stake --amount 100",
      "regents regent-staking stake --amount 100 --receiver 0x1111111111111111111111111111111111111111",
    ],
    output: "Shows the wallet action to review and sign.",
    nextStep: "Sign the prepared transaction with the wallet that owns the $REGENT.",
  },
  "doctor contracts": {
    summary: "Show the contract files and generated artifacts the CLI can see.",
    usage: "regents doctor contracts [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents doctor contracts", "regents doctor contracts --json"],
    output: "Shows contract files, hashes, generated files, command coverage, and service URLs.",
    nextStep: "Run this before release checks or when an operator needs to confirm which contracts are loaded.",
  },
  "doctor workspace": {
    summary: "Show the release repos, contracts, and checks the CLI can see.",
    usage: "regents doctor workspace [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents doctor workspace", "regents doctor workspace --json"],
    output: "Shows repo presence, shared contract agreement, release checks, and workspace readiness.",
    nextStep: "Run this before public beta release checks or when moving the workspace to a new machine.",
  },
  "platform auth login": {
    summary: "Save a Regent website sign-in for platform account commands.",
    usage:
      "regents platform auth login [--access-token <token> | --access-token-env <name>]",
    flags: [
      "--access-token <token>",
      "--access-token-env <name>",
      "--display-name <name>",
      "--origin <url>",
      "--session-file <path>",
      "--config <path>",
    ],
    examples: [
      "regents platform auth login --access-token <token>",
      "regents platform auth login --access-token-env REGENT_PLATFORM_ACCESS_TOKEN",
    ],
    auth: "No saved platform sign-in is needed.",
    output: "Shows the saved website account profile and where the session was stored.",
    nextStep: "Run `regents platform formation status` or `regents platform auth status`.",
  },
  "platform regent runtime": {
    summary: "Show runtime status for one hosted Regent.",
    usage: "regents platform regent runtime --slug <regent-slug>",
    flags: ["--slug <slug>", "--origin <url>", "--session-file <path>", "--config <path>"],
    examples: ["regents platform regent runtime --slug acme-labs"],
    output: "Shows runtime status for the selected hosted Regent.",
    nextStep: "Use the Regent slug from the Regent website, then run the command again when you need a fresh status check.",
  },
  "platform formation doctor": {
    summary: "Explain what is ready or blocked for opening a regent.",
    flags: ["--origin <url>", "--session-file <path>", "--config <path>"],
    output: "Shows the current setup diagnosis from Regent Platform.",
    nextStep: "Follow the next action shown by the diagnosis, then run it again.",
  },
  "platform projection": {
    summary: "Show the Regent Platform account projection.",
    flags: ["--origin <url>", "--session-file <path>", "--config <path>"],
    output: "Shows the Platform account projection used by Regent clients.",
    nextStep: "Use this when you need to compare local state with the Regent website account.",
  },
  "work create": {
    usage: "regents work create --regent-id <id> --title <title> [--description <text>]",
    flags: ["--regent-id <id>", "--title <title>", "--description <text>", "--origin <url>", "--session-file <path>"],
    examples: ["regents work create --regent-id <id> --title \"Review launch notes\""],
    output: "Shows the new work id, status, title, and command to start it.",
    nextStep: "Run `regents work run <work-item-id> --regent-id <id> --runner <runner>`.",
  },
  "work run": {
    summary: "Start work for one regent.",
    usage: "regents work run <work-item-id> --regent-id <id> --runner <runner>",
    flags: [
      "--regent-id <id>",
      "--runner <runner>",
      "--worker-id <id>",
      "--instructions <text>",
      "--origin <url>",
      "--session-file <path>",
    ],
    examples: ["regents work run <work-item-id> --regent-id <id> --runner openclaw_local_executor"],
    output: "Shows the run id, selected worker, current status, and watch command.",
    nextStep: "Run `regents work watch <run-id> --regent-id <id>`.",
  },
  "work watch": {
    summary: "Show updates for one Regent work run.",
    usage: "regents work watch <run-id> --regent-id <id>",
    flags: ["--regent-id <id>", "--origin <url>", "--session-file <path>"],
    examples: ["regents work watch <run-id> --regent-id <id>"],
    output: "Shows recent run updates with sequence, update name, actor, and time.",
    nextStep: "Run the command again when you need the latest updates.",
  },
  "work local-loop": {
    usage: "regents work local-loop --regent-id <id> --worker-id <id>",
    flags: [
      "--regent-id <id>",
      "--worker-id <id>",
      "--once",
      "--sleep-ms <ms>",
      "--artifact-title <title>",
      "--artifact-body <text>",
      "--delegate-runner <runner>",
      "--delegate-title <title>",
      "--config <path>",
    ],
    examples: ["regents work local-loop --regent-id <id> --worker-id <id> --once"],
    auth: "Needs `regents auth login --audience platform` and `regents identity ensure`.",
    output: "Checks for assigned work and records the worker update.",
    nextStep: "Run it without `--once` when the worker should keep checking.",
  },
  "runtime create": {
    usage:
      "regents runtime create --regent-id <id> --name <name> --runner <runner> --execution-surface <surface> --billing-mode <mode>",
    flags: [
      "--regent-id <id>",
      "--name <name>",
      "--platform-agent-id <id>",
      "--runner <runner>",
      "--execution-surface <surface>",
      "--billing-mode <mode>",
      "--origin <url>",
      "--session-file <path>",
    ],
    examples: [
      "regents runtime create --regent-id <id> --platform-agent-id <id> --name \"Hosted Codex\" --runner codex_exec --execution-surface hosted_sprite --billing-mode platform_hosted",
    ],
    output: "Shows the runtime id, status, runner, surface, and billing mode.",
    nextStep: "Run `regents runtime health <runtime-id> --regent-id <id>`.",
  },
  "runtime get": {
    usage: "regents runtime get <runtime-id> --regent-id <id>",
    flags: ["--regent-id <id>", "--origin <url>", "--session-file <path>"],
    examples: ["regents runtime get <runtime-id> --regent-id <id>"],
    output: "Shows the runtime id, status, runner, surface, and billing mode.",
    nextStep: "Run `regents runtime health <runtime-id> --regent-id <id>`.",
  },
  "runtime checkpoint": {
    usage: "regents runtime checkpoint <runtime-id> --regent-id <id> --checkpoint-ref <name>",
    flags: ["--regent-id <id>", "--checkpoint-ref <name>", "--origin <url>", "--session-file <path>"],
    examples: ["regents runtime checkpoint <runtime-id> --regent-id <id> --checkpoint-ref before-release"],
    output: "Shows the checkpoint id, reference, status, and restore command.",
    nextStep: "Use the checkpoint id with `regents runtime restore` when you need to roll back.",
  },
  "runtime restore": {
    usage: "regents runtime restore <runtime-id> --regent-id <id> --checkpoint-id <id>",
    flags: ["--regent-id <id>", "--checkpoint-id <id>", "--origin <url>", "--session-file <path>"],
    examples: ["regents runtime restore <runtime-id> --regent-id <id> --checkpoint-id <id>"],
    output: "Shows the accepted restore request and the next health check.",
    nextStep: "Run `regents runtime health <runtime-id> --regent-id <id>`.",
  },
  "runtime pause": {
    usage: "regents runtime pause <runtime-id> --regent-id <id>",
    flags: ["--regent-id <id>", "--origin <url>", "--session-file <path>"],
    examples: ["regents runtime pause <runtime-id> --regent-id <id>"],
    output: "Shows the paused runtime status.",
    nextStep: "Run `regents runtime resume <runtime-id> --regent-id <id>` when it should run again.",
  },
  "runtime resume": {
    usage: "regents runtime resume <runtime-id> --regent-id <id>",
    flags: ["--regent-id <id>", "--origin <url>", "--session-file <path>"],
    examples: ["regents runtime resume <runtime-id> --regent-id <id>"],
    output: "Shows the resumed runtime status.",
    nextStep: "Run `regents runtime health <runtime-id> --regent-id <id>`.",
  },
  "runtime services": {
    usage: "regents runtime services <runtime-id> --regent-id <id>",
    flags: ["--regent-id <id>", "--origin <url>", "--session-file <path>"],
    examples: ["regents runtime services <runtime-id> --regent-id <id>"],
    output: "Shows service names, status, kind, and endpoint.",
    nextStep: "Run `regents runtime health <runtime-id> --regent-id <id>`.",
  },
  "runtime health": {
    usage: "regents runtime health <runtime-id> --regent-id <id>",
    flags: ["--regent-id <id>", "--origin <url>", "--session-file <path>"],
    examples: ["regents runtime health <runtime-id> --regent-id <id>"],
    output: "Shows availability, status, and metering status.",
    nextStep: "Run `regents runtime services <runtime-id> --regent-id <id>` to inspect published services.",
  },
  "agent connect hosted-hermes": {
    usage: "regents agent connect hosted-hermes --regent-id <id> --runtime-id <id>",
    flags: ["--regent-id <id>", "--runtime-id <id>", "--origin <url>", "--session-file <path>", "--config <path>"],
    examples: ["regents agent connect hosted-hermes --regent-id <id> --runtime-id <id>"],
    output: "Shows hosted runtime status, health, and service records.",
    nextStep: "Use `regents runtime health <runtime-id> --regent-id <id>` when you need a fresh health check.",
  },
  "agent chat": {
    summary: "Send one message to a hosted agent and print the reply.",
    usage: "regents agent chat <message> [--slug <regent-slug>] [--timeout-seconds <5-60>]",
    flags: ["--slug <regent-slug>", "--timeout-seconds <5-60>", "--origin <url>", "--session-file <path>", "--json"],
    examples: [
      "regents agent chat \"Summarize today's priorities\"",
      "regents agent chat \"Check the launch checklist\" --slug startline --timeout-seconds 45",
    ],
    auth: "Needs a saved Regent website session from `regents platform auth login`.",
    output: "Prints the reply. `--json` includes the reply and run metadata.",
    nextStep: "Run another `regents agent chat` message when you need a new reply.",
  },
  "agent connect openclaw": {
    usage: "regents agent connect openclaw --regent-id <id> --role <manager|executor|hybrid>",
    flags: ["--regent-id <id>", "--role <manager|executor|hybrid>", "--name <name>", "--write-skill <true|false>", "--config <path>"],
    examples: ["regents agent connect openclaw --regent-id <id> --role executor"],
    auth: "Needs `regents auth login --audience platform` and `regents identity ensure`.",
    output: "Shows the worker id and the local Regents Work skill path.",
    nextStep: "Use the generated OpenClaw skill, or start work with `regents work run`.",
  },
  "agent link": {
    usage: "regents agent link --regent-id <id> --manager-agent-id <id> --executor-agent-id <id> --relationship <kind>",
    flags: [
      "--regent-id <id>",
      "--manager-agent-id <id>",
      "--manager-worker-id <id>",
      "--executor-agent-id <id>",
      "--executor-worker-id <id>",
      "--relationship <kind>",
      "--origin <url>",
      "--session-file <path>",
    ],
    examples: [
      "regents agent link --regent-id <id> --manager-agent-id <id> --executor-agent-id <id> --relationship can_delegate_to",
      "regents agent link --regent-id <id> --manager-worker-id <id> --executor-worker-id <id> --relationship can_delegate_to",
    ],
    auth: "Use `regents platform auth login` with a Platform access token.",
    output: "Shows the manager, worker, link type, and listing command.",
    nextStep: "Run `regents agent execution-pool --regent-id <id> --manager <id>`.",
  },
  "agent execution-pool": {
    summary: "List workers one manager can assign.",
    usage: "regents agent execution-pool --regent-id <id> --manager <id>",
    flags: ["--regent-id <id>", "--manager <id>", "--origin <url>", "--session-file <path>"],
    examples: ["regents agent execution-pool --regent-id <id> --manager <id>"],
    auth: "Use `regents platform auth login` with a Platform access token.",
    output: "Shows assignable worker ids, roles, status, and last check-in.",
    nextStep: "Use `regents work run` or a connected manager to start regent work.",
  },
};

Object.assign(commandHelpOverlay, {
  status: {
    usage: "regents status [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents status", "regents status --json"],
    prerequisites: ["No setup is required, but the result is more useful after `regents run` has been started once."],
    output: "Shows local runtime, wallet, identity, and sign-in readiness.",
    nextStep: "Fix the first waiting item shown in the output, then run `regents status` again.",
    ifItFails: [
      "If config cannot load, run `regents init` or pass the right `--config <path>`.",
      "If local runtime is waiting, start `regents run` in another terminal.",
    ],
  },
  whoami: {
    summary: "Show the wallet, Agent account, chain, and saved sign-in used by Regent.",
    usage: "regents whoami [--full] [--json]",
    flags: ["--full - Include the saved Regent website account when present.", "--json", "--config <path>"],
    examples: ["regents whoami", "regents whoami --full --json"],
    prerequisites: ["Run `regents identity ensure` when the output says no Agent account is saved."],
    auth: "No saved sign-in is needed for the local read.",
    output: "Shows the active local identity state without moving funds or changing account data.",
    nextStep: "Use this before a signed command to confirm which Agent account will act.",
    ifItFails: [
      "If identity is missing, run `regents identity ensure`.",
      "If the wrong wallet appears, check `regents wallet status` and the config path being used.",
    ],
  },
  "agent-context": {
    summary: "Print the command map and local context that another agent can safely read.",
    usage: 'regents agent-context [--area <name>] [--command "<command>"] [--json]',
    flags: [
      "--area <name> - Only include commands for one area, such as techtree, autolaunch, platform, wallet, x402, chat, work, or mcp.",
      '--command "<command>" - Only include the one exact command named.',
      "--json",
      "--config <path>",
    ],
    examples: [
      "regents agent-context --area techtree",
      'regents agent-context --command "techtree notebooks init"',
    ],
    prerequisites: ["No sign-in is needed. Run this when an agent needs to discover the current command surface."],
    output: "Shows commands, command groups, output behavior, and safe local profile/config summaries.",
    nextStep: "Give the JSON output to the agent that needs to choose the next Regent command.",
    ifItFails: ["If the config cannot load, pass the intended `--config <path>`."],
  },
  run: {
    summary: "Start local Regent access for this machine.",
    usage: "regents run [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents run", "regents run --json"],
    prerequisites: localRuntimePrerequisites,
    auth: "No saved sign-in is needed to start local Regent access.",
    output: "Shows runtime readiness, local records, wallet, identity, sign-in, budget, and transport checks.",
    nextStep: "Keep this terminal open, then run other Regent commands from another terminal.",
    ifItFails: [
      "If a port or socket is already active, stop the older Regent process or run the status command in the terminal that owns it.",
      "If Hermes or OpenClaw tools are missing, run the matching `regents plugin install --runtime ...` command.",
    ],
  },
  doctor: {
    summary: "Run the broad local Regent diagnostic.",
    usage: "regents doctor [--fix] [--json]",
    flags: [
      "--fix applies safe local repairs only: create the default config, create missing runtime folders, and remove a validated stale runtime socket. Everything else keeps its printed next step.",
      "--json",
      "--config <path>",
    ],
    examples: ["regents doctor", "regents doctor --fix", "regents doctor --json"],
    prerequisites: ["Run this before deeper product-specific doctor commands when the failure source is unclear."],
    auth: "No saved sign-in is needed for local checks. Signed remote checks may report missing auth.",
    output: "Shows local setup, runtime, wallet, identity, and service readiness with next moves.",
    nextStep: "Follow the first failing remediation, then run the doctor again.",
    ifItFails: [
      "If the doctor itself cannot read config, run `regents init` or pass `--config <path>`.",
      "If a remote check is unauthorized, run the product-specific `regents auth login --audience ...` command.",
    ],
  },
  "doctor runtime": {
    summary: "Diagnose local Regent runtime access.",
    usage: "regents doctor runtime [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents doctor runtime", "regents doctor runtime --json"],
    prerequisites: ["Run this when a command says it cannot connect to local Regent."],
    output: "Shows local socket, runtime process, and local transport readiness.",
    nextStep: "Start `regents run` if the local runtime is not available.",
    ifItFails: ["If the socket path is stale, stop old Regent processes and start `regents run` again."],
  },
  "auth login": {
    summary: "Save an Agent account sign-in for one Regent product.",
    usage: "regents auth login --audience <platform|autolaunch|techtree|regent-services>",
    flags: ["--audience <name>", "--wallet-address <address>", "--chain-id <id>", "--json", "--config <path>"],
    examples: [
      "regents auth login --audience techtree",
      "regents auth login --audience autolaunch",
      "regents auth login --audience regent-services",
    ],
    prerequisites: ["Start `regents run` in another terminal when the command says local Regent is unavailable."],
    auth: "No saved sign-in is needed.",
    output: "Shows the saved product audience, wallet, chain, and expiry.",
    nextStep: "Run `regents identity ensure` after sign-in so signed agent commands can work.",
    ifItFails: [
      "If the audience is wrong, rerun with the audience named by the product command.",
      "If the local runtime is unavailable, start `regents run` and retry.",
    ],
  },
  "auth status": {
    summary: "Show saved product sign-ins and their expiry.",
    usage: "regents auth status [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents auth status --json"],
    prerequisites: ["No setup is required. Use this before a product write command."],
    output: "Shows which product sessions are saved and whether they are still current.",
    nextStep: "Run `regents auth login --audience <product>` for any missing or expired product session.",
    ifItFails: ["If the config path is wrong, pass the same `--config <path>` used by your other commands."],
  },
  "auth logout": {
    summary: "Remove a saved product sign-in from this machine.",
    usage: "regents auth logout --audience <platform|autolaunch|techtree|regent-services>",
    flags: ["--audience <name>", "--json", "--config <path>"],
    examples: ["regents auth logout --audience techtree"],
    prerequisites: ["Use `regents auth status` first when you are not sure which audience is saved."],
    output: "Shows which saved sign-in was removed.",
    nextStep: "Run `regents auth login --audience <product>` when you need that product again.",
    ifItFails: ["If the audience is missing, pass the exact audience named in `regents auth status`."],
  },
  "identity ensure": {
    summary: "Create or refresh the saved Agent account on this machine.",
    usage: "regents identity ensure [--network base-sepolia|base]",
    flags: ["--network <name>", "--wallet-address <address>", "--json", "--config <path>"],
    examples: ["regents identity ensure --network base-sepolia", "regents identity ensure --network base"],
    prerequisites: [
      "Run `regents auth login --audience <product>` for the product you plan to use.",
      "Make sure `regents wallet status` shows the wallet you expect.",
    ],
    auth: "Uses the local wallet configured for Regent.",
    output: "Shows the wallet, chain, registry, token, and saved status.",
    nextStep: "Run the product command that needs the Agent account.",
    ifItFails: [
      "If the wallet source is missing, run `regents wallet setup` or set the configured wallet environment variable.",
      "If the chain is wrong, rerun with the intended `--network` value.",
    ],
  },
  "identity status": {
    summary: "Read the saved Agent account without changing it.",
    usage: "regents identity status [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents identity status --json"],
    prerequisites: ["Run this before product writes when you need to confirm the saved Agent account."],
    auth: "No saved sign-in is needed for the local read.",
    output: "Shows the saved wallet, registry, token, and chain if present.",
    nextStep: "Run `regents identity ensure` if any required identity field is missing.",
    ifItFails: ["If identity is missing, run `regents identity ensure`."],
  },
  "wallet status": {
    summary: "Show the local wallet source Regent will use.",
    usage: "regents wallet status [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents wallet status", "regents wallet status --json"],
    prerequisites: walletPrerequisites,
    output: "Shows whether Regent sees an environment wallet, local wallet file, or missing wallet source.",
    nextStep: "Run `regents wallet setup` only when you need to create or configure a local wallet source.",
    ifItFails: ["If the wallet shown is not the one you expect, check the config path and shell environment."],
  },
  "wallet setup": {
    summary: "Set up the local wallet source used by Regent.",
    flags: ["--json", "--config <path>"],
    prerequisites: ["Run `regents wallet status` first so you know whether setup is actually needed."],
    output: "Shows where the local wallet source was created or configured.",
    nextStep: "Run `regents identity ensure` after the wallet source is ready.",
    ifItFails: [
      "If setup refuses to overwrite an existing wallet source, inspect `regents wallet status`.",
      "If the terminal is non-interactive, provide the required wallet source through config or environment.",
    ],
  },
  "wallet agentic status": {
    summary: "Show whether Agentic Wallet is connected for paid x402 flows.",
    usage: "regents wallet agentic status [--json]",
    flags: ["--json", "--config <path>"],
    prerequisites: ["Agentic Wallet is optional until paid x402 spend or earn flows are needed."],
    auth: "No saved sign-in is needed for the local status check.",
    output: "Shows login state and the Agentic Wallet address when connected.",
    nextStep: "Run `regents wallet agentic login --email <email>` when paid x402 access is needed.",
    ifItFails: ["If no wallet is connected, start the login and verify flow before trying paid x402 commands."],
  },
  "wallet agentic login": {
    summary: "Start Agentic Wallet email login for paid x402 flows.",
    usage: "regents wallet agentic login --email <email>",
    flags: ["--email <email>", "--json", "--config <path>"],
    examples: ["regents wallet agentic login --email agent@example.com"],
    prerequisites: ["Use this only when an agent needs paid x402 spend or earn flows."],
    auth: "No saved Regent sign-in is needed.",
    output: "Shows the verification flow id and the next verify command.",
    nextStep: "Run `regents wallet agentic verify --flow-id <id> --otp <code>`.",
    ifItFails: ["If the email is wrong, rerun login with the correct email."],
  },
  "wallet agentic verify": {
    summary: "Finish Agentic Wallet login with the one-time code.",
    usage: "regents wallet agentic verify --flow-id <id> --otp <code>",
    flags: ["--flow-id <id>", "--otp <code>", "--json", "--config <path>"],
    examples: ["regents wallet agentic verify --flow-id flow_123 --otp 123456"],
    prerequisites: ["Run `regents wallet agentic login --email <email>` first."],
    auth: "No saved Regent sign-in is needed.",
    output: "Shows the connected Agentic Wallet address and saves the local connection.",
    nextStep: "Run `regents wallet agentic balance --chain base` or create a Regent budget.",
    ifItFails: ["If the code expired, rerun `regents wallet agentic login --email <email>`."],
  },
  "wallet agentic fund": {
    summary: "Show the guided funding path for Agentic Wallet.",
    usage: "regents wallet agentic fund --amount-usdc <amount> --chain base",
    flags: ["--amount-usdc <amount>", "--chain base", "--json", "--config <path>"],
    prerequisites: ["Connect Agentic Wallet with login and verify first."],
    auth: "Uses the saved Agentic Wallet connection.",
    output: "Shows funding instructions for the connected Agentic Wallet.",
    nextStep: "After funding, run `regents wallet agentic balance --chain base`.",
    ifItFails: ["If no Agentic Wallet is connected, run login and verify first."],
  },
  "config get": {
    summary: "Show the current Regent config path and safe config values.",
    usage: "regents config get [--json]",
    flags: ["--json", "--config <path>"],
    examples: ["regents config get --json"],
    prerequisites: ["No setup is required."],
    output: "Shows safe config values and avoids printing secrets.",
    nextStep: "Pass `--config <path>` to other commands if this is not the config you meant to use.",
    ifItFails: ["If config is missing, run `regents init`."],
  },
  "budget grant": {
    summary: "Create a capped local budget for agent paid calls.",
    usage: "regents budget grant --agent <agent-id> --amount-usdc <amount> --max-payment-usdc <amount> --mode <mode>",
    flags: ["--agent <id>", "--amount-usdc <amount>", "--max-payment-usdc <amount>", "--mode <mode>", "--expires <duration>", "--json", "--config <path>"],
    examples: ["regents budget grant --agent <id> --amount-usdc 10 --max-payment-usdc 0.25 --mode techtree_research --expires 7d"],
    prerequisites: paymentPrerequisites,
    auth: "No saved product sign-in is needed; this writes local budget policy.",
    output: "Shows the saved budget id, limit, per-payment cap, mode, and expiry.",
    nextStep: "Use the budget id with `regents x402 pay ... --budget <budget-id>`.",
    ifItFails: ["If the agent id is unknown, run `regents whoami` or inspect the target agent record first."],
  },
  "budget status": {
    summary: "Show saved Regent budgets and remaining spend.",
    usage: "regents budget status [--budget <id>] [--agent <id>] [--json]",
    flags: ["--budget <id>", "--agent <id>", "--json", "--config <path>"],
    examples: ["regents budget status --json", "regents budget status --budget bud_123"],
    prerequisites: ["Run this before paid x402 commands."],
    auth: "No saved product sign-in is needed.",
    output: "Shows budget limits, spent amounts, per-payment cap, mode, status, and expiry.",
    nextStep: "Grant, revoke, or use the budget depending on the remaining allowance.",
    ifItFails: ["If the budget id is missing, run `regents budget status --json` to list saved budgets."],
  },
  "x402 search": {
    summary: "Find paid x402 services without making a payment.",
    usage: 'regents x402 search "<query>" [--json]',
    flags: ["<query> - Service search text.", "--json", "--config <path>"],
    prerequisites: ["No payment setup is needed for search."],
    auth: "No saved sign-in is needed.",
    output: "Shows candidate paid endpoints and metadata.",
    nextStep: "Inspect an endpoint with `regents x402 details --url <url> --json`.",
    ifItFails: ["If search has no results, broaden the query or inspect a known URL directly."],
  },
  "x402 pay": {
    summary: "Make a capped paid x402 request through Regent budget policy.",
    usage: "regents x402 pay <url> --budget <budget-id> --max-usdc <amount> --rail agentic-wallet [--receipt]",
    flags: ["<url> - Protected endpoint URL.", "--budget <id>", "--max-usdc <amount>", "--rail agentic-wallet", "--receipt", "--json", "--config <path>"],
    examples: ["regents x402 pay https://api.example.com/paid --budget bud_123 --max-usdc 0.25 --rail agentic-wallet --receipt --json"],
    prerequisites: paymentPrerequisites,
    auth: "Uses local budget policy and the selected payment rail.",
    output: "Shows payment result, receipt fields when requested, and safe next steps.",
    nextStep: "Create or share a receipt when the paid call produced useful work.",
    ifItFails: [
      "If the budget is missing or exhausted, run `regents budget status` or create a new budget.",
      "If Agentic Wallet is missing, run `regents wallet agentic status` and finish login.",
    ],
  },
  "receipt create": {
    summary: "Create a local receipt from an x402 payment or budget entry.",
    usage: "regents receipt create [--from-x402-payment <id> | --from-budget-entry <id>]",
    flags: ["--from-x402-payment <id>", "--from-budget-entry <id>", "--json", "--config <path>"],
    examples: ["regents receipt create --from-x402-payment payment_123 --json"],
    prerequisites: ["Use this after a paid x402 action or recorded budget entry."],
    auth: "No saved product sign-in is needed to create the local receipt.",
    output: "Shows the saved receipt id and source.",
    nextStep: "Use `regents receipt share-draft --receipt <id>` before sharing public copy.",
    ifItFails: ["If the source id is unknown, inspect the x402 result or budget ledger first."],
  },
  "receipt share-draft": {
    summary: "Draft safe public copy from a saved receipt.",
    usage: "regents receipt share-draft --receipt <id>",
    flags: ["--receipt <id>", "--json", "--config <path>"],
    examples: ["regents receipt share-draft --receipt receipt_123"],
    prerequisites: ["Create or list receipts first."],
    auth: "No saved product sign-in is needed.",
    output: "Shows draft public copy and notes that the receipt is not a revenue claim by itself.",
    nextStep: "Review the draft before posting it publicly.",
    ifItFails: ["If the receipt id is missing, run `regents receipt list --json`."],
  },
  "autolaunch agents list": {
    summary: "List Autolaunch agents and find the ones that can launch.",
    usage: "regents autolaunch agents list [--launchable] [--json]",
    flags: ["--launchable - Show only agents that are close to launch-ready.", "--json", "--config <path>"],
    examples: ["regents autolaunch agents list --launchable", "regents autolaunch agents list --json"],
    prerequisites: autolaunchPrerequisites,
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows agent ids, launch readiness fields, and the next readiness command to run.",
    nextStep: "Run `regents autolaunch agent readiness <id>` for the agent you plan to launch.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch agent readiness <id>": {
    summary: "Check one agent before spending time on launch setup.",
    usage: "regents autolaunch agent readiness <id> [--json]",
    flags: ["<id> - Agent id from `regents autolaunch agents list`.", "--json", "--config <path>"],
    examples: ["regents autolaunch agent readiness <id> --json"],
    prerequisites: autolaunchPrerequisites,
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows what is ready, what is missing, and whether the agent can move into prelaunch planning.",
    nextStep: "Fix waiting items, then run `regents autolaunch prelaunch wizard`.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch prelaunch wizard": {
    summary: "Create or update the saved prelaunch plan for one agent.",
    usage:
      "regents autolaunch prelaunch wizard --agent <id> --name <token-name> --symbol <symbol> --minimum-raise-quote <amount> --agent-safe-address <safe> [--connect-profile]",
    flags: [
      "--agent <id> - Agent being launched.",
      "--name <text> - Token name.",
      "--symbol <text> - Token symbol.",
      "--minimum-raise-quote <amount> - Minimum $REGENT raise target, up to 18 decimals.",
      "--agent-safe-address <address> - Agent Safe that will control launch ownership.",
      "--plan <id> - Update an existing plan.",
      "--connect-profile - Start a profile connection link during the wizard.",
      "--image-url <url>",
      "--json",
      "--config <path>",
    ],
    examples: [
      "regents autolaunch prelaunch wizard --agent <id> --name RegentBot --symbol RGBOT --minimum-raise-quote 1000 --agent-safe-address 0x0000000000000000000000000000000000000001",
    ],
    prerequisites: [
      ...autolaunchPrerequisites,
      "Run `regents autolaunch safe wizard` first if you do not already have an Agent Safe address.",
      "Know the token name, token symbol, minimum raise, and public launch copy before starting.",
    ],
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Saves a local plan, validates it remotely, and shows the plan id plus launchable status.",
    nextStep: "Run `regents autolaunch prelaunch validate --plan <plan-id>`.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch connect start": {
    summary: "Start a profile connection link from the terminal.",
    usage: "regents autolaunch connect start [--plan <plan-id>] [--label <text>] [--watch] [--json]",
    flags: [
      "--plan <id> - Attach the connection to a saved prelaunch plan.",
      "--label <text> - Human-friendly agent label to show on the connection page.",
      "--watch - Keep polling until the connection is completed or expired.",
      "--json",
      "--config <path>",
    ],
    examples: [
      "regents autolaunch connect start --plan plan_123",
      "regents autolaunch connect start --label Atlas --watch",
    ],
    prerequisites: autolaunchPrerequisites,
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows the URL, code, expiry, and agent details for the human profile owner.",
    nextStep: "Ask the human operator to open the URL and confirm the agent.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch prelaunch get": {
    summary: "Open the latest or named prelaunch plan.",
    usage: "regents autolaunch prelaunch get [--plan <plan-id>] [--json]",
    flags: ["--plan <id> - Plan id. If omitted, the latest local plan is used.", "--json", "--config <path>"],
    examples: ["regents autolaunch prelaunch get --plan plan_123"],
    prerequisites: [...autolaunchPrerequisites, "Run `regents autolaunch prelaunch wizard` first so a plan exists."],
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows the saved plan and refreshes the local copy.",
    nextStep: "Run `regents autolaunch prelaunch validate --plan <plan-id>`.",
    ifItFails: [
      ...autolaunchFailureChecks,
      "If no local plan exists, rerun with `--plan <id>` or create one with `regents autolaunch prelaunch wizard`.",
    ],
  },
  "autolaunch prelaunch validate": {
    summary: "Check whether a prelaunch plan is ready to publish or launch.",
    usage: "regents autolaunch prelaunch validate [--plan <plan-id>] [--json]",
    flags: ["--plan <id> - Plan id. If omitted, the latest local plan is used.", "--json", "--config <path>"],
    examples: ["regents autolaunch prelaunch validate --plan plan_123"],
    prerequisites: [...autolaunchPrerequisites, "Create or fetch the plan before validating it."],
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows launchable status and the exact missing fields or approvals.",
    nextStep: "Run `regents autolaunch prelaunch publish --plan <plan-id>` when validation is clean.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch prelaunch publish": {
    summary: "Publish the launch page draft for a validated plan.",
    usage: "regents autolaunch prelaunch publish [--plan <plan-id>] [--json]",
    flags: ["--plan <id> - Plan id. If omitted, the latest local plan is used.", "--json", "--config <path>"],
    examples: ["regents autolaunch prelaunch publish --plan plan_123"],
    prerequisites: [
      ...autolaunchPrerequisites,
      "Run `regents autolaunch prelaunch validate --plan <plan-id>` and confirm it is clean.",
      "Review public copy and images before publishing.",
    ],
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows the published page state and the next launch command.",
    nextStep: "Run `regents autolaunch launch run --plan <plan-id>` when the operator is ready.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch safe wizard": {
    summary: "Prepare the Agent Safe inputs needed for launch ownership.",
    usage: "regents autolaunch safe wizard --backup-signer-address <wallet> [--website-wallet-address <wallet>]",
    flags: [
      "--backup-signer-address <address> - Backup signer wallet for the Safe.",
      "--website-wallet-address <address> - Website wallet when available.",
      "--agent-safe-address <address> - Existing Safe to reuse.",
      "--wait-for-website-wallet",
      "--json",
      "--config <path>",
    ],
    examples: ["regents autolaunch safe wizard --backup-signer-address 0x0000000000000000000000000000000000000001"],
    prerequisites: [
      "Run `regents wallet status` and confirm the local wallet is the agent signer you intend to use.",
      "Have a backup signer wallet ready before creating a new Safe.",
    ],
    auth: "No Autolaunch sign-in is needed for the local Safe planning step.",
    output: "Explains the Safe setup and shows the values to use in the prelaunch plan.",
    nextStep: "Use the Safe address with `regents autolaunch prelaunch wizard --agent-safe-address <safe>`.",
    ifItFails: [
      "If a signer is missing, run `regents wallet status` and pass the missing wallet flag named in the error.",
      "If you already have a Safe, rerun with `--agent-safe-address <safe>`.",
    ],
  },
  "autolaunch safe create": {
    summary: "Create the Agent Safe used by an Autolaunch project.",
    usage: "regents autolaunch safe create --backup-signer-address <wallet> [--website-wallet-address <wallet>]",
    flags: [
      "--backup-signer-address <address> - Required backup signer wallet.",
      "--website-wallet-address <address> - Optional website wallet.",
      "--json",
      "--config <path>",
    ],
    examples: ["regents autolaunch safe create --backup-signer-address 0x0000000000000000000000000000000000000001"],
    prerequisites: [
      "Run `regents autolaunch safe wizard` first unless you already know the exact Safe signer layout.",
      "Confirm the local wallet is allowed to create the Safe and has enough network fees.",
    ],
    auth: "No Autolaunch sign-in is needed for the local Safe creation step.",
    output: "Shows the created Safe address and the launch command that needs it.",
    nextStep: "Run `regents autolaunch prelaunch wizard --agent-safe-address <safe>`.",
    ifItFails: [
      "If the backup signer is missing, rerun with `--backup-signer-address <wallet>`.",
      "If the local wallet cannot sign, run `regents wallet status` and correct the wallet source.",
    ],
  },
  "autolaunch launch run": {
    summary: "Run the launch flow for a validated prelaunch plan.",
    usage: "regents autolaunch launch run [--plan <plan-id>] [--watch] [--interval <seconds>] [--json]",
    flags: [
      "--plan <id> - Plan id. If omitted, the latest local plan is used.",
      "--wallet-address <address> - Wallet that signs the launch authorization when needed.",
      "--watch - Keep polling until the launch reaches a final state.",
      "--interval <seconds>",
      "--json",
      "--config <path>",
    ],
    examples: ["regents autolaunch launch run --plan plan_123 --watch"],
    prerequisites: [
      ...autolaunchWalletActionPrerequisites,
      "Run `regents autolaunch prelaunch validate --plan <plan-id>` and confirm it is launchable.",
      "Run `regents autolaunch prelaunch publish --plan <plan-id>` if the public page should be visible first.",
    ],
    auth: "Needs Autolaunch sign-in, saved Agent account, and a launch-authorizing wallet.",
    output: "Shows the launch job id, current job status, and the command to keep watching it.",
    nextStep: "Run `regents autolaunch jobs watch <job-id> --watch` until the job is ready, failed, or blocked.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch jobs watch": {
    summary: "Watch an Autolaunch job until it reaches a final state.",
    usage: "regents autolaunch jobs watch <job-id> [--watch] [--interval <seconds>] [--json]",
    flags: ["<job-id> - Job id from launch run.", "--watch", "--interval <seconds>", "--json", "--config <path>"],
    examples: ["regents autolaunch jobs watch job_123 --watch --interval 5"],
    prerequisites: [...autolaunchPrerequisites, "Start this after a command prints a launch job id."],
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows the latest job status and stops when the job is ready, failed, or blocked unless asked to keep watching.",
    nextStep: "Run the next command shown in the job output, usually launch monitor or finalize.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch launch monitor": {
    summary: "Watch the lifecycle job after the launch job starts.",
    usage: "regents autolaunch launch monitor --job <job-id> [--watch] [--interval <seconds>] [--json]",
    flags: ["--job <id>", "--watch", "--interval <seconds>", "--json", "--config <path>"],
    examples: ["regents autolaunch launch monitor --job job_123 --watch --interval 5"],
    prerequisites: [...autolaunchPrerequisites, "Run this only after launch output gives you a lifecycle job id."],
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows lifecycle status and the recommended next action.",
    nextStep: "Run `regents autolaunch launch finalize --job <job-id>` when the monitor recommends finalizing.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch launch finalize": {
    summary: "Prepare or submit the final launch action for a lifecycle job.",
    usage: "regents autolaunch launch finalize --job <job-id> [--submit] [--json]",
    flags: ["--job <id>", "--submit - Sign and submit the prepared action.", "--json", "--config <path>"],
    examples: ["regents autolaunch launch finalize --job job_123", "regents autolaunch launch finalize --job job_123 --submit"],
    prerequisites: [
      ...autolaunchWalletActionPrerequisites,
      "Run `regents autolaunch launch monitor --job <job-id>` and confirm finalize is the recommended action.",
      "Run without `--submit` first when you want to inspect the prepared action.",
    ],
    auth: "Needs Autolaunch sign-in, saved Agent account, and a wallet able to sign the final action.",
    output: "Without `--submit`, shows the prepared action. With `--submit`, shows the transaction result.",
    nextStep: "Run `regents autolaunch vesting status --job <job-id>` after finalization.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch auctions list": {
    summary: "List active and recent Autolaunch auctions.",
    usage: "regents autolaunch auctions list [--sort hottest|newest] [--status <status>] [--mine-only] [--json]",
    flags: ["--sort <value>", "--status <status>", "--chain <chain>", "--mine-only", "--json", "--config <path>"],
    examples: ["regents autolaunch auctions list --sort hottest --json"],
    prerequisites: autolaunchPrerequisites,
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows auction ids, subject ids, status, and pricing fields needed for quote commands.",
    nextStep: "Run `regents autolaunch auction <id>` or `regents autolaunch bids quote --auction <id> ...`.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch auction <id>": {
    summary: "Open one Autolaunch auction.",
    usage: "regents autolaunch auction <id> [--json]",
    flags: ["<id> - Auction id from `regents autolaunch auctions list`.", "--json", "--config <path>"],
    examples: ["regents autolaunch auction auction_123 --json"],
    prerequisites: autolaunchPrerequisites,
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows auction state, subject details, bid fields, and current pricing context.",
    nextStep: "Run `regents autolaunch bids quote --auction <id> --amount <regent> --max-price <price>` before placing a bid.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch bids quote": {
    summary: "Quote a bid before spending funds.",
    usage: "regents autolaunch bids quote --auction <auction-id> --amount <regent> --max-price <price> [--json]",
    flags: [
      "--auction <id>",
      "--amount <regent> - $REGENT bid budget.",
      "--max-price <price> - Maximum $REGENT price per agent token.",
      "--json",
      "--config <path>",
    ],
    examples: ["regents autolaunch bids quote --auction auction_123 --amount 100 --max-price 0.50 --json"],
    prerequisites: [
      ...autolaunchPrerequisites,
      "Open the auction first so the $REGENT amount, max price, and status are current.",
      "Use this before every bid because auction conditions can change.",
    ],
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows the estimated bid result for the auction at current conditions.",
    nextStep: "Only place the bid after reviewing the quote and signing the matching wallet transaction.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch subjects get": {
    summary: "Open one launched subject by subject id.",
    usage: "regents autolaunch subjects get <subject-id> [--json]",
    flags: ["<subject-id> - Subject id from an auction, launch, or claim record.", "--json", "--config <path>"],
    examples: ["regents autolaunch subjects get subject_123 --json"],
    prerequisites: autolaunchPrerequisites,
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows subject state, revenue lanes, staking status, and available prepared actions.",
    nextStep: "Run staking, claim, or ingress commands only after checking the current subject state.",
    ifItFails: autolaunchFailureChecks,
  },
  "autolaunch subjects staking": {
    summary: "Show staking state for one Autolaunch subject.",
    usage: "regents autolaunch subjects staking <subject-id> [--json]",
    flags: ["<subject-id> - Subject id.", "--json", "--config <path>"],
    examples: ["regents autolaunch subjects staking subject_123 --json"],
    prerequisites: autolaunchPrerequisites,
    auth: "Needs Autolaunch sign-in and a saved Agent account.",
    output: "Shows staking balances, reward state, and whether stake or unstake actions are available.",
    nextStep: "Review the subject page or available contract actions before changing subject state.",
    ifItFails: autolaunchFailureChecks,
  },
  "techtree notebooks init": {
    summary: "Create a local notebook workspace for paper or freeform work.",
    usage: "regents techtree notebooks init --kind <paper|freeform> --title <title> --workspace-path <path> [--source <source>]",
    flags: ["--kind paper|freeform", "--title <title>", "--workspace-path <path>", "--source <source>", "--json", "--config <path>"],
    prerequisites: techtreePrerequisites,
    auth: "No saved sign-in is needed.",
    output: "Creates the local notebook workspace and prints the next pairing command.",
    nextStep: "Run `regents techtree notebooks pair --workspace-path <path>`.",
    ifItFails: techtreeFailureChecks,
  },
  "techtree notebooks pair": {
    summary: "Open the next step for a local notebook workspace.",
    usage: "regents techtree notebooks pair --workspace-path <path> [--json]",
    flags: ["--workspace-path <path>", "--json", "--config <path>"],
    examples: ["regents techtree notebooks pair --workspace-path ./paper-note --json"],
    prerequisites: techtreePrerequisites,
    auth: "No saved sign-in is needed.",
    output: "Shows the notebook path and marimo launch command.",
    nextStep: "Open the notebook with the printed marimo command.",
    ifItFails: techtreeFailureChecks,
  },
});

const groupHelp: Record<string, HelpGroup> = {
  setup: {
    summary: "Install local support files for agents and first-run use.",
    auth: "No saved sign-in is needed.",
    output: "Shows what was installed and the next action.",
    commands: (CLI_COMMANDS_BY_TOP_LEVEL_GROUP as Readonly<Record<string, readonly string[]>>).setup ?? [],
    nextStep: "Start with `regents setup skills`.",
  },
  autolaunch: {
    summary: "Launch and manage Agent account projects from the terminal.",
    auth: "Most commands need `regents auth login --audience autolaunch` and `regents identity ensure`.",
    output: "Human output uses panels and status lines. `--json` prints raw JSON.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.autolaunch,
    nextStep: "Start with `regents autolaunch agents list --launchable` or `regents autolaunch prelaunch wizard`.",
  },
  auth: {
    summary: "Manage saved Agent account sign-ins.",
    auth: "No saved sign-in is needed.",
    output: "Shows the saved session, account, and expiry.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.auth,
    nextStep: "For Autolaunch, run `regents auth login --audience autolaunch`.",
  },
  identity: {
    summary: "Create or refresh the local Agent account.",
    auth: "Uses the local wallet configured for Regent.",
    output: "Shows wallet, chain, registry, token, and saved status.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.identity,
    nextStep: "Run `regents identity ensure` after signing in.",
  },
  "regent-staking": {
    summary: "Manage Regent staking for the saved Agent account.",
    auth: "Needs `regents auth login --audience regent-services` and `regents identity ensure`.",
    output: "Shows balances, prepared actions, and claim results.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP["regent-staking"],
    nextStep: "Start with `regents regent-staking get`.",
  },
  platform: {
    summary: "Use the Regent website account from the terminal.",
    auth: "Use `regents platform auth login` with a Platform access token.",
    output: "Shows account, readiness, billing, and runtime status. Some beta actions return an unavailable status.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.platform,
    nextStep: "Start with `regents platform auth login`, then `regents platform formation status`.",
  },
  work: {
    summary: "Create and run regent work from the terminal.",
    auth: "Work setup uses `regents platform auth login`; local worker loops use `regents auth login --audience platform` and `regents identity ensure`.",
    output: "Shows concise work summaries, run status, and update lists.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.work,
    nextStep: "Start with `regents work create --regent-id <id> --title <title>`.",
  },
  techtree: {
    summary: "Create and pair local research notebooks.",
    auth: "No saved sign-in is needed.",
    output: "Shows local notebook paths and next steps. `--json` prints raw JSON.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.techtree,
    nextStep: "Start with `regents techtree notebooks init`.",
  },
  runtime: {
    summary: "Manage regent runtimes from the terminal.",
    auth: "Hosted runtime commands use `regents platform auth login`; local runtime status needs no saved sign-in.",
    output: "Shows runtime status, services, health, checkpoints, and restore results. `--json` prints raw JSON.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.runtime,
    nextStep: "Start with `regents runtime get <runtime-id> --regent-id <id>` or create a runtime from the regent setup.",
  },
  agent: {
    summary: "Manage local Agent setup, hosted agent replies, and regent workers.",
    auth: "Hosted agent commands use `regents platform auth login`; local worker connection uses `regents auth login --audience platform` and `regents identity ensure`.",
    output: "Shows hosted replies, connected worker ids, work links, and workers a manager can assign.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.agent,
    nextStep: "Use `regents agent chat \"message\" --slug <slug>` for a hosted reply, or `regents agent connect openclaw --regent-id <id> --role executor` for local work.",
  },
  feynman: {
    summary: "Open the Feynman research shell from Regents CLI.",
    auth: "Feynman manages its own setup.",
    output: "Shows Feynman's terminal output directly.",
    commands: CLI_COMMANDS_BY_TOP_LEVEL_GROUP.feynman,
    nextStep: "Install Feynman, then run `regents feynman setup`.",
  },
};

const AREA_SUMMARIES: Readonly<Record<string, string>> = {
  techtree: "local research notebooks",
  autolaunch: "launches, auctions, bids, subjects, holdings",
  platform: "hosted account, billing, pause and resume",
  work: "regent work runs and the local worker loop",
  wallet: "wallet setup and the agentic wallet",
  x402: "paid endpoints, quotes, payments, receipts",
  mcp: "the Regents MCP server and Codex setup",
  chat: "saved chat follows for Autolaunch chat",
  commands: "the machine-readable index of every shipped command",
  budget: "capped local spending budgets for paid agent calls",
  receipt: "local receipts for completed paid or published work",
  doctor: "local and product readiness diagnostics",
};

const sentenceCase = (value: string): string =>
  value.length === 0 ? value : `${value.charAt(0).toUpperCase()}${value.slice(1)}`;

const sentenceFromAreaSummary = (area: string): string => {
  const summary = AREA_SUMMARIES[area];
  return summary ? `${sentenceCase(summary)}.` : `Commands in the ${area} area.`;
};

const fallbackGroupHelp = (area: string): HelpGroup | undefined => {
  const commands = (CLI_COMMANDS_BY_TOP_LEVEL_GROUP as Readonly<Record<string, readonly string[]>>)[
    area
  ];
  if (!commands || commands.length === 0) {
    return undefined;
  }

  return {
    summary: sentenceFromAreaSummary(area),
    auth: "Run a command with `--help` to see its sign-in needs.",
    output: "Human output uses panels and status lines. `--json` prints raw JSON.",
    commands,
    nextStep: `Run \`regents ${area} <command> --help\` for one command.`,
  };
};

const helpGroupForCommand = (command: string): HelpGroup | null => {
  if (command.startsWith("autolaunch ")) {
    return groupHelp.autolaunch;
  }

  if (command.startsWith("auth ")) {
    return groupHelp.auth;
  }

  if (command.startsWith("identity ")) {
    return groupHelp.identity;
  }

  if (command.startsWith("regent-staking ")) {
    return groupHelp["regent-staking"];
  }

  if (command.startsWith("platform ")) {
    return groupHelp.platform;
  }

  if (command.startsWith("work ")) {
    return groupHelp.work;
  }

  if (command.startsWith("techtree ")) {
    return groupHelp.techtree;
  }

  if (command.startsWith("runtime ")) {
    return groupHelp.runtime;
  }

  if (command.startsWith("agent ")) {
    return groupHelp.agent;
  }

  if (command.startsWith("setup ")) {
    return groupHelp.setup;
  }

  if (command === "feynman") {
    return groupHelp.feynman;
  }

  return null;
};

const isPlaceholderPart = (part: string): boolean => part.startsWith("<") && part.endsWith(">");

interface HelpMatchScore {
  readonly literalMatches: number;
  readonly placeholderMatches: number;
  readonly totalParts: number;
}

const scoreHelpMatch = (command: string, input: readonly string[]): HelpMatchScore | null => {
  const commandParts = command.split(" ");
  if (input.length > commandParts.length) {
    return null;
  }

  let literalMatches = 0;
  let placeholderMatches = 0;

  for (const [index, inputPart] of input.entries()) {
    const commandPart = commandParts[index];
    if (!commandPart) {
      return null;
    }

    if (isPlaceholderPart(commandPart)) {
      if (!inputPart) {
        return null;
      }
      placeholderMatches += 1;
      continue;
    }

    if (commandPart !== inputPart) {
      return null;
    }

    literalMatches += 1;
  }

  if (!commandParts.slice(input.length).every((part) => isPlaceholderPart(part))) {
    return null;
  }

  return {
    literalMatches,
    placeholderMatches,
    totalParts: commandParts.length,
  };
};

const commandForInput = (positionals: readonly string[]): string | null => {
  const helpMatches = CLI_COMMANDS.flatMap((command) => {
    const score = scoreHelpMatch(command, positionals);
    return score ? [{ command, score }] : [];
  });

  if (helpMatches.length === 0) {
    return null;
  }

  return helpMatches.reduce((best, candidate) => {
    if (candidate.score.literalMatches !== best.score.literalMatches) {
      return candidate.score.literalMatches > best.score.literalMatches ? candidate : best;
    }

    if (candidate.score.placeholderMatches !== best.score.placeholderMatches) {
      return candidate.score.placeholderMatches < best.score.placeholderMatches ? candidate : best;
    }

    if (candidate.score.totalParts !== best.score.totalParts) {
      return candidate.score.totalParts < best.score.totalParts ? candidate : best;
    }

    return best;
  }).command;
};

const isCommandFieldMetadata = (value: unknown): value is CommandFieldMetadata =>
  Boolean(value) && typeof value === "object" && typeof (value as CommandFieldMetadata).name === "string";

const fieldTypeSuffix = (field: CommandFieldMetadata): string => {
  if (!field.type || field.type === "boolean") {
    return "";
  }

  if (field.name?.includes("<")) {
    return "";
  }

  if (field.enum && field.enum.length > 0) {
    return ` <${field.enum.join("|")}>`;
  }

  return ` <${field.type}>`;
};

const formatFieldMetadata = (field: CommandFieldMetadata): string => {
  const name = field.name ?? "";
  const required = field.required ? " required" : "";
  const description = field.description ? ` - ${field.description}` : "";
  return `${name}${fieldTypeSuffix(field)}${required}${description}`;
};

const generatedFields = (value: unknown): string[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(isCommandFieldMetadata)
    .map(formatFieldMetadata)
    .filter((line) => line.length > 0);
};

const detailAuthMode = (detail: CommandDetailMetadata | undefined): string | undefined =>
  detail?.auth_mode ?? detail?.agent_metadata?.auth_mode;

const detailAuthAudience = (detail: CommandDetailMetadata | undefined): string | undefined =>
  detail?.auth_audience;

const generatedAuthText = (detail: CommandDetailMetadata, group: HelpGroup | null): string => {
  const authMode = detailAuthMode(detail);
  const authAudience = detailAuthAudience(detail);

  if (authMode === "none" || authMode === "local") {
    return "No saved sign-in is needed.";
  }

  if (authMode === "session-file") {
    return "Needs a saved Regent website session from `regents platform auth login`.";
  }

  if (authAudience) {
    return `Needs \`regents auth login --audience ${authAudience}\` and \`regents identity ensure\`.`;
  }

  if (authMode === "agent-siwa") {
    return "Needs a saved Agent sign-in and `regents identity ensure`.";
  }

  return group?.auth ?? "Check the command group help for sign-in needs.";
};

const generatedOutputText = (detail: CommandDetailMetadata): string => {
  if (detail.output_envelope === "passthrough") {
    return "Shows the launched tool output directly.";
  }

  if (detail.agent_metadata?.json_support === "supported") {
    return "Human output is concise. `--json` prints raw JSON.";
  }

  if (detail.agent_metadata?.json_support === "not_supported") {
    return "Shows human terminal output.";
  }

  return "Prints command results. `--json` keeps output script-safe where supported.";
};

const generatedPrerequisites = (command: string, detail: CommandDetailMetadata | undefined): readonly string[] => {
  const authMode = detailAuthMode(detail);
  const authAudience = detailAuthAudience(detail);

  if (authMode === "none" || authMode === "local") {
    return [];
  }

  if (authMode === "agent-siwa") {
    return [
      authAudience
        ? `Run \`regents auth login --audience ${authAudience}\`.`
        : "Run `regents auth login --audience <product>` for this command.",
      "Run `regents identity ensure` before signed agent actions.",
    ];
  }

  if (command.startsWith("service ")) {
    return serviceOwnerPrerequisites;
  }

  if (authMode === "session-file") {
    return platformPrerequisites;
  }

  if (command.startsWith("autolaunch ")) {
    return autolaunchPrerequisites;
  }

  if (command.startsWith("techtree ")) {
    return techtreePrerequisites;
  }

  if (command.startsWith("platform ") || command.startsWith("runtime ") || command.startsWith("work ") || command === "agent chat" || command.startsWith("agent connect ") || command.startsWith("agent link") || command.startsWith("agent execution-pool")) {
    return platformPrerequisites;
  }

  if (command.startsWith("regent-staking ")) {
    return agentIdentityPrerequisites;
  }

  if (command.startsWith("x402 ")) {
    return command === "x402 search" || command === "x402 details" || command === "x402 quote" ? ["No payment is needed to inspect or quote a paid service."] : paymentPrerequisites;
  }

  if (command.startsWith("wallet ")) {
    return walletPrerequisites;
  }

  if (authAudience) {
    return [`Run \`regents auth login --audience ${authAudience}\`.`, "Run `regents identity ensure` before signed agent actions."];
  }

  return ["Run the command with `--help` before using it in an unattended agent loop."];
};

const generatedFailureChecks = (
  command: string,
  detail: CommandDetailMetadata | undefined,
): readonly string[] => {
  const authMode = detailAuthMode(detail);
  const authAudience = detailAuthAudience(detail);

  if (authMode === "none" || authMode === "local") {
    return ["Check the local config path and rerun with `--json` if you need machine-readable output."];
  }

  if (authMode === "agent-siwa") {
    return [
      authAudience
        ? `If the command says auth is missing, run \`regents auth login --audience ${authAudience}\` and \`regents identity ensure\`.`
        : "If the command says auth is missing, run the product-specific `regents auth login --audience ...` command and `regents identity ensure`.",
      "If a regent, worker, or work id is not found, copy it again from the Regent website or the previous command output.",
    ];
  }

  if (command.startsWith("service ")) {
    return [
      "If the command says no saved platform session exists, run `regents platform auth login`.",
      "If access is denied, confirm the regent slug and service slug belong to the signed-in owner.",
      "If a buyer needs to call the service, use the existing `regents x402` commands instead.",
    ];
  }

  if (authMode === "session-file") {
    return [
      "If the command says no saved platform session exists, run `regents platform auth login`.",
      "If a regent, runtime, worker, or work id is not found, copy it again from the Regent website or the previous command output.",
    ];
  }

  if (command.startsWith("autolaunch ")) {
    return autolaunchFailureChecks;
  }

  if (command.startsWith("techtree ")) {
    return techtreeFailureChecks;
  }

  if (command.startsWith("platform ") || command.startsWith("runtime ") || command.startsWith("work ") || command === "agent chat" || command.startsWith("agent connect ") || command.startsWith("agent link") || command.startsWith("agent execution-pool")) {
    return [
      "If the command says sign-in is missing, run `regents platform auth login`.",
      "If a regent, runtime, worker, or work id is not found, copy it again from the Regent website or the previous command output.",
    ];
  }

  if (command.startsWith("x402 ")) {
    return [
      "If the command needs payment, check `regents wallet agentic status` and `regents budget status`.",
      "If the endpoint is unavailable, run `regents x402 details --url <url>` before paying.",
    ];
  }

  return ["Check the command spelling, required flags, saved sign-in, and local Regent status, then run the command again."];
};

const requiredFlagUsage = (field: CommandFieldMetadata): string | undefined => {
  if (!field.name || !field.required || !field.name.startsWith("--")) {
    return undefined;
  }

  return field.type === "boolean" ? field.name : `${field.name} <${field.name.slice(2)}>`;
};

const generatedUsage = (command: string, detail: CommandDetailMetadata | undefined): string => {
  if (detail?.usage) {
    return detail.usage;
  }

  const flagFields = Array.isArray(detail?.flags) ? detail.flags.filter(isCommandFieldMetadata) : [];
  const requiredParts = flagFields
    .map(requiredFlagUsage)
    .filter((part): part is string => Boolean(part));

  return ["regents", command, ...requiredParts].join(" ");
};

const exampleParts = (example: string): readonly string[] => {
  const trimmed = example.trim();
  const withoutBinary = trimmed.startsWith("regents ") ? trimmed.slice("regents ".length) : trimmed;
  return withoutBinary.split(/\s+/).filter((part) => part.length > 0);
};

const exampleMatchesCommand = (command: string, example: string): boolean => {
  const commandParts = command.split(" ");
  const parts = exampleParts(example);
  if (parts.length < commandParts.length) {
    return false;
  }

  return commandParts.every((part, index) => isPlaceholderPart(part) || parts[index] === part);
};

const generatedExamples = (command: string, detail: CommandDetailMetadata | undefined): readonly string[] => {
  const matchingExample = detail?.examples?.find((example) => exampleMatchesCommand(command, example));
  return [matchingExample ?? generatedUsage(command, detail)];
};

const summarizeCommand = (command: string): HelpEntry => {
  const group = helpGroupForCommand(command);
  const detail = commandDetailsByCommand[command];
  const flags = [
    ...generatedFields(detail?.args),
    ...generatedFields(detail?.flags),
    "--config <path>",
    "--json where supported",
  ];

  return {
    summary: detail?.summary ?? `Run ${command}.`,
    usage: generatedUsage(command, detail),
    flags: Array.from(new Set(flags)),
    examples: generatedExamples(command, detail),
    prerequisites: generatedPrerequisites(command, detail),
    auth: detail ? generatedAuthText(detail, group) : group?.auth ?? "Check the command group help for sign-in needs.",
    output: detail ? generatedOutputText(detail) : "Prints command results. `--json` keeps output script-safe where supported.",
    nextStep: detail?.next_step ?? group?.nextStep ?? globalNextStep,
    ifItFails: generatedFailureChecks(command, detail),
  };
};

const mergeHelp = (skeleton: HelpEntry, overlay: Partial<HelpEntry> | undefined): HelpEntry => {
  if (!overlay) {
    return skeleton;
  }

  return {
    summary: overlay.summary ?? skeleton.summary,
    usage: overlay.usage ?? skeleton.usage,
    flags: overlay.flags ?? skeleton.flags,
    examples: overlay.examples ?? skeleton.examples,
    prerequisites: overlay.prerequisites ?? skeleton.prerequisites,
    auth: overlay.auth ?? skeleton.auth,
    output: overlay.output ?? skeleton.output,
    nextStep: overlay.nextStep ?? skeleton.nextStep,
    ifItFails: overlay.ifItFails ?? skeleton.ifItFails,
  };
};

const helpForCommand = (command: string): HelpEntry =>
  mergeHelp(summarizeCommand(command), commandHelpOverlay[command]);

const columnLines = (rows: ReadonlyArray<readonly [string, string]>): string[] => {
  const width = rows.reduce((max, [left, right]) => (right ? Math.max(max, left.length) : max), 0);
  return rows.map(([left, right]) =>
    right
      ? `${padRight(tone(left, CLI_PALETTE.accent, true), width)}  ${tone(right, CLI_PALETTE.secondary)}`
      : tone(left, CLI_PALETTE.accent, true),
  );
};

const flagLines = (flags: readonly string[]): string[] =>
  columnLines(
    flags.map((flag) => {
      const separator = flag.indexOf(" - ");
      return separator === -1
        ? ([flag, ""] as const)
        : ([flag.slice(0, separator), flag.slice(separator + 3)] as const);
    }),
  );

const commandLine = (command: string): string =>
  command.startsWith("regents ")
    ? `${tone("regents", CLI_PALETTE.accent, true)} ${tone(command.slice("regents ".length), CLI_PALETTE.primary)}`
    : command;

const renderEntry = (title: string, entry: HelpEntry): string =>
  [
    renderPanel(title, [
      entry.summary,
      "",
      `${tone("usage", CLI_PALETTE.secondary, true)} ${entry.usage}`,
      `${tone("auth", CLI_PALETTE.secondary, true)} ${entry.auth}`,
      `${tone("output", CLI_PALETTE.secondary, true)} ${entry.output}`,
      `${tone("next", CLI_PALETTE.secondary, true)} ${entry.nextStep}`,
    ]),
    entry.prerequisites?.length
      ? renderPanel("◆ BEFORE YOU RUN THIS", entry.prerequisites.map((prerequisite) => prerequisite))
      : undefined,
    entry.flags?.length
      ? renderPanel("◆ FLAGS", flagLines(entry.flags))
      : undefined,
    entry.examples?.length
      ? renderPanel("◆ EXAMPLES", entry.examples.map(commandLine))
      : undefined,
    entry.ifItFails?.length
      ? renderPanel("◆ IF THIS FAILS", entry.ifItFails.map((failure) => failure))
      : undefined,
  ]
    .filter((part): part is string => Boolean(part))
    .join("\n\n");

const sectionTitle = (name: string): string => name.split("-").join(" ").toUpperCase();

const commandRowLines = (
  rows: ReadonlyArray<readonly [string, string]>,
  width: number,
): string[] =>
  rows.map(([command, summary]) =>
    summary
      ? `${padRight(commandLine(command), width)}  ${tone(summary, CLI_PALETTE.secondary)}`
      : commandLine(command),
  );

const renderGroup = (name: string, group: HelpGroup): string => {
  const sections = new Map<string, Array<readonly [string, string]>>();
  for (const command of group.commands) {
    const detail = commandDetailsByCommand[command];
    const section = detail?.group ?? name;
    const rows = sections.get(section) ?? [];
    rows.push([`regents ${command}`, detail?.summary ?? ""] as const);
    sections.set(section, rows);
  }

  const width = group.commands.reduce((max, command) => Math.max(max, `regents ${command}`.length), 0);
  const commandLines = Array.from(sections.entries())
    .sort(([left], [right]) => left.localeCompare(right))
    .flatMap(([section, rows], index) => [
      ...(index > 0 ? [""] : []),
      ...(sections.size > 1 ? [tone(sectionTitle(section), CLI_PALETTE.title, true)] : []),
      ...commandRowLines(rows, width),
    ]);

  return [
    renderPanel(`◆ ${name.toUpperCase()} HELP`, [
      group.summary,
      "",
      `${tone("auth", CLI_PALETTE.secondary, true)} ${group.auth}`,
      `${tone("output", CLI_PALETTE.secondary, true)} ${group.output}`,
      `${tone("next", CLI_PALETTE.secondary, true)} ${group.nextStep}`,
    ]),
    renderPanel("◆ COMMANDS", commandLines),
  ].join("\n\n");
};

const renderRootHelp = (configPath: string): string =>
  [
    renderBanner(),
    renderPanel("◆ REGENT CLI HELP", [
      ...columnLines([
        ["usage", "regents <command> [flags]"],
        ["new here", "run `regents init` for guided setup"],
        ["sign in", "protected commands use a saved Agent account"],
        ["config", configPath],
      ]),
      "",
      tone(globalNextStep, CLI_PALETTE.secondary),
    ]),
    renderPanel(
      "◆ GETTING STARTED",
      columnLines([
        ["regents init", "guided setup for this machine"],
        ["regents setup skills", "install the Regents agent skills"],
        ["regents run", "start local Regent and keep it ready"],
        ["regents techtree notebooks init", "start a local research notebook"],
        ["regents status", "readiness at a glance"],
        ["regents doctor", "check the local stack"],
      ]),
    ),
    renderPanel(
      "◆ COMMAND AREAS",
      [
        ...columnLines(
          ["techtree", "autolaunch", "platform", "work", "wallet", "x402", "mcp"].map(
            (area) => [area, AREA_SUMMARIES[area] ?? ""] as const,
          ),
        ),
        "",
        tone("use `regents <area> --help` for every command in an area", CLI_PALETTE.secondary),
      ],
    ),
    renderPanel(
      "◆ FLAGS",
      columnLines([
        ["--json", "plain JSON output where supported"],
        ["--config <path>", "pin a specific config file"],
        ["--no-input", "never prompt; fail instead"],
        ["--help", "scoped help for any command"],
      ]),
    ),
    renderPanel(
      "◆ EXIT CODES",
      columnLines([
        ["0", "success"],
        ["1", "operation failed"],
        ["2", "usage error: unknown command, missing argument, or invalid flag"],
        ["3", "sign-in or Agent identity missing"],
        ["4", "not found"],
        ["5", "service or local runtime unreachable"],
      ]),
    ),
  ]
    .filter(Boolean)
    .join("\n\n");

export function renderScopedHelp(positionals: readonly string[], configPath: string): string {
  if (positionals.length === 0) {
    return renderRootHelp(configPath);
  }

  const command = commandForInput(positionals);
  if (command) {
    return renderEntry(`◆ ${command.toUpperCase()} HELP`, helpForCommand(command));
  }

  const groupName = positionals[0];
  if (groupName && positionals.length === 1) {
    const group = groupHelp[groupName] ?? fallbackGroupHelp(groupName);
    if (group) {
      return renderGroup(groupName, group);
    }
  }

  return renderPanel("◆ COMMAND NOT FOUND", [
    `No shipped command matches: regents ${positionals.join(" ")}`,
    "Check the spelling or run `regents --help`.",
  ]);
}

export function nextStepForPositionals(positionals: readonly string[]): string | undefined {
  const command = commandForInput(positionals);
  if (command) {
    return commandDetailsByCommand[command]?.next_step;
  }

  const area = positionals[0];
  return area && area in CLI_COMMANDS_BY_TOP_LEVEL_GROUP ? `regents ${area} --help` : undefined;
}

const levenshtein = (left: string, right: string): number => {
  let previousRow = Array.from({ length: right.length + 1 }, (_, index) => index);

  for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    const currentRow = [leftIndex];
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      const substitutionCost = left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1;
      currentRow.push(
        Math.min(
          (currentRow[rightIndex - 1] ?? 0) + 1,
          (previousRow[rightIndex] ?? 0) + 1,
          (previousRow[rightIndex - 1] ?? 0) + substitutionCost,
        ),
      );
    }
    previousRow = currentRow;
  }

  return previousRow[right.length] ?? 0;
};

const literalCommandText = (command: string): string =>
  command
    .split(" ")
    .filter((part) => !isPlaceholderPart(part))
    .join(" ");

const nearestCommands = (positionals: readonly string[]): string[] => {
  const input = positionals.join(" ");
  const threshold = Math.max(3, Math.ceil(input.length / 2));

  return CLI_COMMANDS.map((command) => ({
    command,
    distance: levenshtein(input, literalCommandText(command)),
  }))
    .filter((entry) => entry.distance <= threshold)
    .sort((leftEntry, rightEntry) => leftEntry.distance - rightEntry.distance)
    .slice(0, 3)
    .map((entry) => `regents ${entry.command}`);
};

export function unroutedCommandError(positionals: readonly string[]): CliUsageError {
  const entered = positionals.join(" ");
  const command = commandForInput(positionals);

  if (command && command.split(" ").length > positionals.length) {
    const missing = command.split(" ").slice(positionals.length);
    const entry = helpForCommand(command);
    return new CliUsageError({
      code: "missing_required_argument",
      message: `Missing required argument${missing.length > 1 ? "s" : ""}: ${missing.join(" ")}.`,
      command: `regents ${command}`,
      usage: entry.usage,
      missing,
      example: entry.examples?.[0],
    });
  }

  if (knownCliCommand(positionals)) {
    return new CliUsageError({
      code: "command_not_available",
      message: `Command is not available yet: ${entered}`,
    });
  }

  return new CliUsageError({
    code: "unknown_command",
    message: `Unknown command: ${entered}`,
    validValues: nearestCommands(positionals),
  });
}

export function usageHintForPositionals(positionals: readonly string[]): {
  readonly command: string;
  readonly usage: string;
  readonly example?: string;
} | undefined {
  const command = commandForInput(positionals);
  if (!command) {
    return undefined;
  }

  const entry = helpForCommand(command);
  return {
    command: `regents ${command}`,
    usage: entry.usage,
    example: entry.examples?.[0],
  };
}

export function printScopedHelp(positionals: readonly string[], configPath: string): void {
  printText(renderScopedHelp(positionals, configPath));
}
