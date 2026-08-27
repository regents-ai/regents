# regent-contracts

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![Solidity ^0.8.26](https://img.shields.io/badge/solidity-%5E0.8.26-lightgrey)](https://soliditylang.org)
[![Built with Foundry](https://img.shields.io/badge/built%20with-foundry-lightgrey)](https://getfoundry.sh)
[![Chain: Base](https://img.shields.io/badge/chain-base-lightgrey)](https://base.org)

The canonical home for Regent Solidity: contract source, Foundry tests, deployment scripts,
verified deployment records, canonical ABIs, and the chain-contract manifest. It is maintained
by Regents Labs and covers the shared, Techtree, staking, and Autolaunch contract families.

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

```text
  client surfaces
    ios                               mobile app, wallet, action signing
    regents-cli                       operator control surface
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
    regent-contracts                  canonical Solidity, ABIs, deployment records   ◀ this repository
    autolaunch-contracts              frozen Autolaunch V1 Solidity

  shared libraries and standalone tools
    elixir-utils                      SIWA, ENS, XMTP, cache, Credo checks
    design-system                     tokens and regent_ui components
    python-cli                        offline Techtree skill-tree inspection
    videocontrol                      video project and timeline workflows
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
src/techtree/     TechtreeGraphRegistryV1
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
those live in the product repositories.

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
| `regents-cli` | The operator control surface: the `regents` command line tool, its generated bindings, and its local runtime. | It drives the platform over published contracts and owns no product database or on-chain authority. |
| `regents-techtree-hermes-plugin` | The Hermes plugin that presents Techtree mission control across Forge, Techtree Verify, and Uplift. | It is presentation only: no second task store, no private Verify database, no identity model, no payment system, and no Hermes runtime of its own. |
| `siwa-server` | The shared Sign-In With Anything service for signed agent requests, nonce and replay state, and internal keyring endpoints. | It owns no product data or product authorization policy. |
| `videocontrol` | A separate product: video project workflows, timeline editing, preview rendering, and Codex plugin media control. | It shares the house style but no runtime, database, or contract with the Regent platform. |

## License

MIT — see [LICENSE](LICENSE). Dependencies under `lib/` keep their own licenses.
