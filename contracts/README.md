# regent-contracts

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![Solidity ^0.8.26](https://img.shields.io/badge/solidity-%5E0.8.26-lightgrey)](https://soliditylang.org)
[![Built with Foundry](https://img.shields.io/badge/built%20with-foundry-lightgrey)](https://getfoundry.sh)
[![Chain: Base](https://img.shields.io/badge/chain-base-lightgrey)](https://base.org)

The canonical home for Regent Solidity: contract source, Foundry tests, deployment scripts,
verified deployment records, canonical ABIs, and the chain-contract manifest. It is maintained
by Regents Labs and covers the shared, staking, and Autolaunch contract families.

> [!IMPORTANT]
> No release is currently admitted by this repository's chain manifest. Some historical
> contracts represented here are already live on Base; the empty manifest means this checkout
> has not admitted a new deployment from the current tree. Files under `deployments/` remain
> historical reconstructions rather than records of a release made from this tree.

## Quickstart

You need [Foundry](https://getfoundry.sh). Clone with submodules, then build and test:

```bash
git submodule update --init --recursive
forge build
forge test
```

Formatting and static analysis:

```bash
forge fmt --check
slither .
```

## Where this sits

This directory is one component of the Regents monorepo:

```text
  platform/     regents.sh: Phoenix, LiveView and Ash web app and HTTP API
  identity/     shared Ash identity domain consumed by every product
  cli/          the regents command line tool and its local runtime
  contracts/    Solidity, ABIs, deployment records and the chain manifest   ◀ this directory
  blog/         the site's blog posts
  plugins/      home for standalone runtime plugin packages (none yet)
```

## Stack

| Layer | What | Pin |
| --- | --- | --- |
| Language | Solidity | `^0.8.26` across `src/`, with two files pinned to `0.8.28` |
| Toolchain | Foundry (`forge`) | `auto_detect_solc`, optimizer on at 200 runs, `via_ir` |
| Static analysis | Slither | configured by `slither.config.json` |
| Dependencies | git submodules under `lib/` | exact revisions recorded in `foundry.lock` |
| Target chains | Base mainnet (`8453`) and Base Sepolia | RPC endpoints supplied by environment variables |

Dependencies include forge-std, OpenZeppelin Contracts, Solady, Solmate, Permit2, Safe smart
account, Uniswap v4 core and periphery, and the UERC20 factory. `foundry.lock` records the
exact commit of each; treat it as the source of truth over any version written in prose.

## Repository layout

```text
src/shared/       Shared auth, libraries, and interfaces
src/staking/      RegentRevenueStaking
src/autolaunch/   Autolaunch factory, CCA, launch fees, vesting, revenue split
test/             Foundry unit, invariant, and proof-of-concept suites
script/           Deployment and example scripts
contracts/        chain-contracts.yaml manifest and draft economics manifests
deployments/      Per-network deployment records (base-mainnet, base-sepolia)
docs/             Gate proofs, security notes, migration inventory
reference/        Read-only reference copies of prior implementations
bin/gate.sh       The repository gate script
```

## Boundaries

This repository owns Solidity source, Foundry tests, deployment scripts, verified deployment
records, canonical ABIs, the chain-contract manifest, and contract version history. It does
not own HTTP or CLI contracts, Ash resources, workflow logic, UI, or projection workers —
those live in the other components of this monorepo and in the separate product repositories.

Archived Autolaunch contracts are not promoted here automatically. A contract family moves in
only through an explicit source-of-truth and deployment migration, decided by the founder.

## Configuration

| Variable | Required | What it is for |
| --- | --- | --- |
| `BASE_MAINNET_RPC_URL` | For the `base` RPC alias | Base mainnet JSON-RPC endpoint used by fork tests and scripts. |
| `BASE_SEPOLIA_RPC_URL` | For the `base_sepolia` RPC alias | Base Sepolia JSON-RPC endpoint. |

> [!WARNING]
> Deployment is founder-gated. Deployment scripts are prepared here and run only with explicit
> founder authorisation. Nothing in this repository authorises you to broadcast a transaction,
> and none of the scripts should be pointed at a funded key without that authorisation.

> [!WARNING]
> Never put a private key, mnemonic, or keystore password in this repository, in an
> environment file, or on a command line. Deployment signing happens outside this tree.

## Checks

These must pass before a change is proposed:

| Command | What it does |
| --- | --- |
| `forge build` | Compiles every contract. |
| `forge test` | Runs the unit, invariant, and proof-of-concept suites. |
| `forge fmt --check` | Fails on any formatting drift. |
| `slither .` | Static analysis against `slither.config.json`. |

`bin/gate.sh` runs the repository's own combined gate.

## The rest of the monorepo

| Directory | What it is | What it deliberately does not do |
| --- | --- | --- |
| `platform/` | The Phoenix, LiveView, and Ash application behind regents.sh: public pages, the signed-in shell, the HTTP API, $REGENT staking and Animata pass redemption. | It does not hold Solidity source or user signing keys; wallet actions remain browser-signed. |
| `identity/` | The shared Ash identity domain and `regent_identity` schema that every product reads. | It owns no product workflow, contract, or wallet action. |
| `cli/` | The `regents` command line tool, its generated bindings, and its local runtime. | It drives the platform over published contracts and owns no product database or on-chain authority. |
| `blog/` | The site's blog posts, rendered by `platform/`. | It holds content only. |
| `plugins/` | The home for standalone runtime plugin packages; none exist yet. | Agent-runtime integrations live in `cli/` until a package moves here. |

The shared design system and the other Elixir libraries stay separate sibling repositories,
and Autolaunch keeps its own repository.

## License

MIT — see [LICENSE](LICENSE). Dependencies under `lib/` keep their own licenses.
