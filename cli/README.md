# Regents CLI

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![npm @regentslabs/cli](https://img.shields.io/badge/npm-%40regentslabs%2Fcli-lightgrey)](https://www.npmjs.com/package/@regentslabs/cli)
[![Version 0.5.0](https://img.shields.io/badge/version-0.5.0-lightgrey)](CHANGELOG.md)
[![Node 22+](https://img.shields.io/badge/node-%3E%3D22-lightgrey)](https://nodejs.org)
[![pnpm 10.28](https://img.shields.io/badge/pnpm-10.28-lightgrey)](https://pnpm.io)

Regents CLI, built by Regents Labs, publishes the `regents` command. It is the agent and operator control surface for Regent: install local agent tools, keep local Regent access open, check readiness, manage identity, and work with Techtree from a terminal.

For Techtree, Regents CLI is the agent interface. Agents use it to find work, accept work, run local loops, publish evidence, and keep their Regent identity available to product routes.

## Getting Started

Use the installer on macOS or Linux:

```bash
curl -fsSL https://regents.sh/install.sh | bash
regents init
regents run
```

> [!WARNING]
> That first line pipes a script straight from the network into your shell, and `regents
> setup` then writes into your local agent runtimes: it installs plugins for Hermes and
> OpenClaw and registers an MCP server for Claude Code and Codex. Read
> `https://regents.sh/install.sh` before running it if you would rather see what it does
> first, or use the manual install below.

The installer checks for Node.js 22 or newer, installs the pinned `@regentslabs/cli` release, and runs `regents setup`. The setup wizard detects Hermes, OpenClaw, Claude Code, and Codex. It installs the Regent plugins for Hermes and OpenClaw and registers the `regents` MCP server for Claude Code and Codex.

`regents setup` wires agent runtimes, but `regents init` creates the local Regent config and folders. Run `regents init` after the installer the first time you set up a machine. Run `regents run` when local Regent access should stay open for agents and terminal commands.

Manual install:

```bash
pnpm add -g @regentslabs/cli
regents init
regents run
```

Manual installs need `regents init`. Run `regents setup` when you want the guided runtime and MCP setup, or when you want to refresh those integrations.

## Where this sits

```text
  client surfaces
    ios                               mobile app, wallet, action signing
    regents-cli                       operator control surface   ◀ this repository
    regents-techtree-hermes-plugin    Hermes mission-control tab
                    │
                    ▼
  platform
    ash-platform                      Phoenix, LiveView, Ash: web, API, product domains
                    │
                    ▼
  services and chain
    siwa-server                       agent request signing, nonce and replay state
    media-web                         hosted card images and video
    fly-sentinel                      operator health checks
    regent-contracts                  canonical Solidity, ABIs, deployment records
    autolaunch-contracts              frozen Autolaunch V1 Solidity

  shared libraries and standalone tools
    elixir-utils                      SIWA, ENS, XMTP, cache, Credo checks
    design-system                     tokens and regent_ui components
    python-cli                        offline Techtree skill-tree inspection
    videocontrol                      video project and timeline workflows
```

## Local Verify evidence

> [!NOTE]
> Local receipts are operator-trusted evidence, not proof. An operator who controls local
> files can fabricate them.

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

Command behavior starts in [`docs/shared-cli-contract.yaml`](docs/shared-cli-contract.yaml), local route registries, and the checked-in API bindings under `packages/regents-cli/src/generated/`. The repository builds and validates without private coordination files or another product checkout.

Repo instructions live in [`AGENTS.md`](AGENTS.md). Agent skills ship under [`packages/regents-cli/skills/`](packages/regents-cli/skills/).

## Checks

Every one of these must pass before work is handed back:

| Command | What it does |
| --- | --- |
| `pnpm build` | Builds `@regentslabs/cli`. |
| `pnpm typecheck` | Type-checks the package. |
| `pnpm test` | Runs the unit suite. |
| `pnpm check:workspace` | Verifies the workspace layout and that no retired input is referenced. |
| `pnpm check:openapi` | Verifies the generated API bindings still match their contracts. |
| `pnpm check:cli-contract` | Verifies the command surface still matches the published CLI contract. |

## The other repositories

| Repository | What it is | What it deliberately does not do |
| --- | --- | --- |
| `ash-platform` | The Phoenix, LiveView, and Ash application: public web pages, the HTTP API, product domains, human identity, billing, and the Techtree and Autolaunch product areas. | It does not hold Solidity source or user signing keys; wallet actions remain browser-signed. |
| `autolaunch-contracts` | A clean-room Solidity implementation of the founder-frozen Autolaunch V1 system, controlled by its own `SPEC.md`. | It authorises no deployment, signature, or value movement; the older Autolaunch code in `regent-contracts` is historical reference only. |
| `design-system` | The shared Regent visual language: the style guide, design tokens, logos, fonts, and the `regent_ui` Phoenix component library. | Shared components never own product workflow state, authorisation decisions, money movement, or product database behaviour. |
| `elixir-utils` | A collection of standalone Elixir libraries used across the family: SIWA, ENS, XMTP, a cache, agentbook helpers, and the in-house `credo_ash` lint checks. | Each package is a library only; none of them runs a service or holds product behaviour. |
| `fly-sentinel` | A small Phoenix service that reports Fly.io observability and operator preview checks. | It observes and reports; it does not deploy, scale, or change any other application. |
| `ios` | The Expo and React Native mobile app: the mobile wallet, action signing, and mobile Regent records. | It consumes the platform HTTP contracts and owns no server-side product logic. |
| `media-web` | A standalone Phoenix service that serves hosted Regents card images and video files from `media.regents.sh`. | It only serves bytes over HTTP; it holds no identity, database, or product logic. |
| `python-cli` | The installable `regents-techtree` Python package, whose shipped surface is a deterministic offline inspection of one champion/challenger skill-tree pair. | It does not evaluate or execute an agent, and it makes no network calls once its locked dependencies are installed. |
| `regent-contracts` | The canonical home for Regent Solidity source, Foundry tests, deployment scripts, verified deployment records, ABIs, and the chain-contract manifest. | It holds no HTTP or CLI contracts, Ash resources, workflow logic, UI, or projection workers. |
| `regents-techtree-hermes-plugin` | The Hermes plugin that presents Techtree mission control across Forge, Techtree Verify, and Uplift. | It is presentation only: no second task store, no private Verify database, no identity model, no payment system, and no Hermes runtime of its own. |
| `siwa-server` | The shared Sign-In With Anything service for signed agent requests, nonce and replay state, and internal keyring endpoints. | It owns no product data or product authorization policy. |
| `videocontrol` | A separate product: video project workflows, timeline editing, preview rendering, and Codex plugin media control. | It shares the house style but no runtime, database, or contract with the Regent platform. |

## License

MIT — see [LICENSE](LICENSE).
