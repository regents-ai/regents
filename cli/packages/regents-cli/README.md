# `@regentslabs/cli`

`@regentslabs/cli` publishes the `regents` command. It is the terminal control surface for Regent operators and agents: install local agent tools, keep local Regent access open, check readiness, manage identity, and use Regents wallet and payment tools.

Each product owns its CLI: `regents` (`@regentslabs/cli`), `autolaunch`
(`@regentslabs/autolaunch-cli`), `patchbay` (`@regentslabs/patchbay-cli`), and
Techtree's existing Python `techtree` package. New sibling packages are local
release candidates until published. Techtree's Python CLI and Hermes plugin own
its campaign, proof and publication interface. Older `regents techtree` local
Verify/notebook commands have different contracts and remain pending migration;
they are not aliases for the Python CLI.

Version 1.0.0 removes the five public Autolaunch market commands. Install the
Autolaunch CLI and use `autolaunch auctions list`, `autolaunch auction <id>`,
`autolaunch bids quote`, `autolaunch tokens list`, or
`autolaunch treasury security <address>`. Its domain payload is `body` inside
`{ok, status, body}`; HTTP failures use stdout and exit 1. It uses
`AUTOLAUNCH_BASE_URL` or `--base-url`, not Regents config files. Other older
Autolaunch commands remain unverified against the current product API.
No release, installer pin or registry package is changed by this local candidate.

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
| `regents update` | Update the installed CLI through npm. |
| `regents --version` | Print the installed CLI version. |

## Existing wallets and x402

Start with `regents wallet setup --json` to discover wallet options without creating
an account, importing keys or signing in. Use `regents wallet setup --provider external` for guidance on an existing wallet and its x402 client. An agent may use
its own authorized signer or a human-delegated wallet; using Regent tools does not
require moving custody to Regent.

`regents x402 details --url <url> --json` returns the complete challenge in
`payment_required_response`, including all offers and extensions. Preserve the
original method, headers and body when using `--method`, `--header` and `--body` or
passing the challenge to an external x402 SDK. Details sends the HTTP request
without signing; the endpoint may execute it if no payment is required. A non-402
response retains its actual status and body. External clients keep their own
request authentication and payment records.

For CLI payments, `regents x402 pay --help` describes both `agentic-wallet` and
`regent-wallet` rails. The local USDC budget is accounting, not signer-enforced
spending authority. The Regent budget path accepts exact Base or Base Sepolia
USDC; use the raw atomic flow for other assets. Agentic Wallet accepts canonical
JSON objects or arrays, rejects caller headers and other body forms, and controls
its own redirects. Setup guidance alone does not establish signer readiness or
funding.

Payment results distinguish `payment_status` from the product's HTTP result.
Unknown outcomes retain a reservation and recovery references: inspect the local
receipt, intent or provider correlation ID and budget ledger before authorizing
another payment. Do not automatically retry. Provider-reported settlement and
locally recorded payment references are not independent chain proof.

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
