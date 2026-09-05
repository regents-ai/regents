# Changelog

All notable changes to `@regentslabs/cli` should be recorded here.

## Unreleased

### Added

- Bare `regents` now prints a short readiness summary (local runtime, wallet, identity, saved sign-ins, and Fold state when active) and points to `regents --help`.
- `regents init` is now a guided, re-runnable setup: it writes the local config, installs the missing Hermes/OpenClaw Regent tools, starts local Regent access in the background, runs the runtime doctor checks, and prints the remaining wallet and identity steps. Re-running it when everything is set up reports ready.
- `regents doctor --fix` is now part of the shared CLI contract. It applies only safe local repairs: create the default config, create missing runtime folders, and remove a validated stale runtime socket.
- Failed commands now print `Next: <step>` from the command's contract next_step metadata through the shared error path.
- `regents identity graph` now shows the saved agent identity, product-owned links when available, and chain-owner checks for the identity token.
- Added bundled Regents agent skills for Regents, Platform, Autolaunch, and Techtree.
- Added `regents setup skills` to install those skills through the Agent Skills installer.
- Added a package install note that points users to `regents setup skills`.
- Added the local runtime front door: `regents plugin install --runtime auto`, `regents setup --runtime auto`, `regents runtime status|tools|policy`, and richer `regents run --fold ...` guidance.
- Added Agentic Wallet commands under `regents wallet agentic ...`, keeping it separate from the Regent identity wallet.
- Added local Regent budgets with `regents budget grant|status|ledger|revoke`.
- Added guarded x402 entry points with `regents x402 search` and `regents x402 pay ... --budget ... --max-usdc ...`.
- Added local receipts with `regents receipt create|get|list|share-draft`.

### Changed

- `--runtime` now defaults to `auto` for `regents setup`, `regents plugin install`, `regents plugin status`, and `regents plugin doctor`, so the flag is optional.
- Fold proof now uses `regents techtree fold proof --attempt <attempt-id>` and stays anchored to existing Techtree benchmark attempts.
- Fold copy now describes a reporting/readiness layer over attempts, notebook publications, receipts, and verifier evidence, not a separate Fold run or certificate system.
- Plugin setup owns Hermes/OpenClaw instruction skills; Fold no longer presents skill installation as its own product step.
- Plugin setup now has one install path: `regents plugin install --runtime auto`. Setup reports readiness and next steps instead of writing plugin files.
- Kept the useful Hermes bridge lessons in the current plugin path: runtime agents do not choose wallet providers, identity or wallet changes require explicit approval, and agents call Regent through named tools rather than raw commands.
- Updated the x402 package pin so packed installs use the exported payment client paths required by the CLI.

### Removed

- Removed the positional/`--run` Fold proof shape from the current shipped command surface.
- Removed the old standalone `hermes-regents` bridge. The current Hermes and OpenClaw bridge is installed by Regents CLI.

## 0.5.0 - 2026-05-06

### Added

- Added `regents agent-context`, a JSON command surface that exposes shipped commands, command groups, command metadata, examples, output behavior, and safe local profile/config summaries for agents.
- Added global `--no-input` handling through a shared prompt boundary so automated runs fail with actionable errors instead of waiting for terminal input.
- Added the Feynman bridge: `regents feynman ...` launches the installed Feynman research shell while keeping Feynman's own setup and state.
- Added Techtree benchmark capsule, run, reliability, repeat, materialize, submit, and scoreboard command coverage.
- Added workspace release checks, workspace manifest validation, packed-install checks, and wallet-action schema validation.

### Changed

- Hard-cut read-style commands to conventional names, including `config get`, `agent profile get`, `runtime get`, `work get`, `regent-staking get`, and Autolaunch `get` commands.
- Expanded generated CLI command metadata so contracts, help, route checks, command docs, and `agent-context` use the same command source.
- Updated Techtree defaults and tests for Base mainnet-oriented publishing and identity flows.
- Updated Autolaunch subject and holdings commands around canonical prepared wallet actions.
- Improved terminal panel wrapping for narrow terminal widths while keeping JSON output plain for automation.

### Fixed

- Fixed release checks so banned command verbs, missing examples, missing JSON declarations, missing route coverage, and unbounded list/search-style commands fail in contract validation.
- Fixed Techtree benchmark transaction preparation to use typed chain data and canonical wallet-action shapes.
- Fixed staking and Autolaunch transaction paths to use the current prepared transaction envelope.
- Refreshed Platform, Autolaunch, Techtree, and Regent services generated bindings from the current contracts.

### Removed

- Removed prompt-only staking receiver confirmation; prepared wallet actions plus `--submit` are now the explicit value movement boundary.
- Removed old public command names and stale command docs from the shipped CLI surface.

## 0.4.0 - 2026-04-29

### Added

- Added Regent work commands for creating work, starting runs, watching run events, and connecting local worker agents.
- Added Platform-facing agent commands for Hermes, OpenClaw, agent links, execution pools, formation status, formation doctor, projection, and runtime operations.
- Added Techtree Science Tasks, BBH draft, BBH run, Autoskill, reviewer, certificate, watch, chatbox, and guided `techtree start` flows.
- Added Regent staking commands for account views, staking, unstaking, claiming USDC, claiming Regent rewards, and claiming plus restaking.
- Added reporting commands for bug and security reports from the CLI.
- Added structured product request logging, transport doctor checks, route contract coverage, and packed-install release checks.
- Added generated CLI command metadata from the YAML contracts so shipped commands, help, and release checks use the same command list.

### Changed

- Split large command and runtime areas into focused modules: command routing, Autolaunch commands, Techtree runtime handlers, Techtree clients, doctor checks, and terminal presenters.
- Moved CLI configuration to explicit service base URLs for SIWA, Platform, Autolaunch, and Techtree.
- Replaced duplicated product request helpers with a shared product HTTP client and a shared Base contract client.
- Refreshed generated OpenAPI bindings for Platform, Autolaunch, Techtree, and shared Regent services.
- Aligned shared SIWA signing and audience handling across auth, doctor, Techtree, Autolaunch, Platform, Regent staking, Agentbook, and reports.
- Improved human terminal output for status, doctor, Techtree, Autolaunch, Regent staking, Agentbook, and work-runtime flows while preserving JSON output for scripts.
- Made command tests run serially with realistic timeouts because the CLI suite uses global mocks, local sockets, and local HTTP servers.

### Fixed

- Fixed Techtree command contract drift for id-taking commands such as `techtree node get <id>`, `techtree watch <id>`, and `techtree star <id>`.
- Fixed route and command metadata checks so exact shipped command names must match the route table.
- Fixed product service URL selection so Platform, Autolaunch, Techtree, and shared Regent service calls use their configured owners.
- Fixed chatbox stream failures so failed streams surface as failures instead of being hidden.
- Made runtime state and local secure writes safer under repeated command runs.
- Removed stale JavaScript doctor files and other old-shape handling that no longer matches the current contracts.

### Removed

- Removed older public-beta Autolaunch command paths and compatibility routes that are not part of the current contracts.
- Removed duplicated shared-services request code in favor of the shared product HTTP client.
- Removed stale command metadata that omitted required positional ids.
