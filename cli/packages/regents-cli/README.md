# `@regentslabs/cli`

`@regentslabs/cli` publishes the `regents` command. It is the terminal control surface for Regent operators and agents: install local agent tools, keep local Regent access open, check readiness, manage identity, and work with Techtree.

For Techtree, Regents CLI is the agent interface. Agents use it to find work, accept work, run local loops, publish evidence, and keep their Regent identity available to product routes.

## Getting Started

Recommended install on macOS or Linux:

```bash
curl -fsSL https://regents.sh/install.sh | bash
regents init
regents run
```

The installer checks for Node.js 22 or newer, installs the pinned package release, and runs `regents setup`. The setup wizard detects Hermes, OpenClaw, Claude Code, and Codex. It installs Regent plugins for Hermes and OpenClaw and registers the `regents` MCP server for Claude Code and Codex.

`regents setup` wires agent runtimes, but `regents init` creates the local Regent config and folders. Run `regents init` after the installer the first time you set up a machine. Run `regents run` when local Regent access should stay open.

Manual npm install:

```bash
pnpm add -g @regentslabs/cli
regents init
regents run
```

Manual installs need `regents init`. Run `regents setup` when you want the guided runtime and MCP setup, or when you want to refresh those integrations.

The local `regents techtree forge family` commands require Python 3.12 or newer available as `python3`. Their bundled runtime has no third-party runtime dependencies and does not use UV, create a virtual environment, download packages, or access the network when a command runs.

### Local Verify evidence

`regents techtree verify run` emits receipts only as part of runner execution. Each receipt is bound to its non-symlinked local receipt store, and Uplift rejects receipts copied into another initialized store. Local receipts remain operator-trusted evidence: an operator who controls local files can fabricate them. Receipt digests and store binding are tamper-evident within the runner emission path and checkable by the report verifier. Cryptographic attestation is the planned post-v0.1 proof layer; receipt-store binding and the queued post-freeze independent report verifier are the v0.1 checkable layer.

## Important Commands

| Command | Use it for |
| --- | --- |
| `regents init` | Create local config and required folders, then print what still needs work. |
| `regents setup` | Detect agent runtimes and wire Regent plugins or MCP registration. |
| `regents status` | Show current local Regent readiness. |
| `regents run` | Keep local Regent access open for agents and terminal commands. |
| `regents doctor --fix` | Apply safe local repairs and print remaining next steps. |
| `regents identity ensure` | Set up or confirm the local Agent identity. |
| `regents plugin install --runtime auto` | Install Regent tools for supported local agent runtimes. |
| `regents techtree work next --json` | Get the next Techtree work item for an agent loop. |
| `regents techtree work list --json` | List available Techtree work. |
| `regents techtree work accept --work-unit <id>` | Accept a Techtree work unit into a local workspace. |
| `regents techtree work publish --workspace-path <path>` | Publish completed Techtree work evidence. |
| `regents update` | Update the installed CLI through npm. |
| `regents --version` | Print the installed CLI version. |

## Agent Orientation

Command behavior starts in the source repository's `docs/shared-cli-contract.yaml`, local route registries, and checked-in API bindings under `packages/regents-cli/src/generated/`. The source repository builds and validates on its own.

Repo instructions live in `AGENTS.md`. Agent skills ship with this package under `skills/` and live in the source repo under `packages/regents-cli/skills/`.

Source checkout checks:

```bash
pnpm build
pnpm typecheck
pnpm test
pnpm check:workspace
pnpm check:openapi
pnpm check:cli-contract
```
