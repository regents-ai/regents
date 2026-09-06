# Regents CLI

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![npm @regentslabs/cli](https://img.shields.io/badge/npm-%40regentslabs%2Fcli-lightgrey)](https://www.npmjs.com/package/@regentslabs/cli)
[![Version 1.0.0](https://img.shields.io/badge/version-1.0.0-lightgrey)](CHANGELOG.md)
[![Node 22+](https://img.shields.io/badge/node-%3E%3D22-lightgrey)](https://nodejs.org)
[![pnpm 10.28](https://img.shields.io/badge/pnpm-10.28-lightgrey)](https://pnpm.io)

Regents CLI, built by Regents Labs, publishes the `regents` command. It is the agent and operator control surface for Regent: install local agent tools, keep local Regent access open, check readiness, manage identity, and use Regents wallet and payment tools.

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

For existing wallets, delegated funds, and provider choices, start with the
[agent wallet guide](docs/agent-wallets.md). `regents wallet setup` only shows
choices until you explicitly select an action.

## Getting started from this checkout

The checkout contains the 1.0.0 release candidate. Hosted installer availability and
registry publication are separate release checks; do not infer either from this README.
With Node 22+ and the package manager version declared in `package.json`:

```sh
cd cli
pnpm install --frozen-lockfile
pnpm build
node packages/regents-cli/dist/index.js --help
```

Use `--help` and the [command contract](docs/shared-cli-contract.yaml) before choosing
an operation. Initialization and runtime/plugin setup write local configuration;
wallet and paid operations require their own signer and spending authority.
The checked-in `scripts/install.sh` is a release artifact to review, not a promise
that `regents.sh/install.sh` is currently served.

## Product ownership

See the [Regents monorepo overview](../README.md) for current components and related products.
Each product owns its API and authorization; retained cross-product commands are not
a promise that their old server routes still exist.

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
| `regents update` | Update the installed CLI through npm. |
| `regents --version` | Print the installed CLI version. |

## Agent Orientation

Command behavior starts in [`docs/shared-cli-contract.yaml`](docs/shared-cli-contract.yaml), local route registries, and the checked-in API bindings under `packages/regents-cli/src/generated/`. The repository builds and validates without private coordination files or another product checkout.

Repo instructions live in [`AGENTS.md`](AGENTS.md). Agent skills ship under [`packages/regents-cli/skills/`](packages/regents-cli/skills/).

## Checks

Choose the checks that exercise the changed behavior. Run the complete CLI gate for
CLI releases and changes to its command contracts:

| Command | What it does |
| --- | --- |
| `pnpm build` | Builds `@regentslabs/cli`. |
| `pnpm typecheck` | Type-checks the package. |
| `pnpm test` | Runs the unit suite. |
| `pnpm check:workspace` | Verifies the workspace layout and that no retired input is referenced. |
| `pnpm check:openapi` | Verifies the generated API bindings still match their contracts. |
| `pnpm check:cli-contract` | Verifies the command surface still matches the published CLI contract. |

## Related products

Use the [current product directory](../README.md#related-products).

## License

MIT — see [LICENSE](LICENSE).
