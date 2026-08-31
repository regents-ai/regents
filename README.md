# Ash Platform

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![Elixir 1.19](https://img.shields.io/badge/elixir-1.19-lightgrey)](https://elixir-lang.org)
[![Phoenix 1.8](https://img.shields.io/badge/phoenix-1.8-lightgrey)](https://www.phoenixframework.org)
[![Ash 3.29](https://img.shields.io/badge/ash-3.29-lightgrey)](https://ash-hq.org)
[![PostgreSQL 14](https://img.shields.io/badge/postgres-14-lightgrey)](https://www.postgresql.org)

Ash Platform is the main Regent web application, built by Regents Labs on Phoenix, LiveView,
and Ash. It serves the public site, the signed-in product shell, and the public HTTP API, and
it owns human identity, billing, Formation, public Regent records, and the Techtree and
Autolaunch product areas.

> [!IMPORTANT]
> This is a live, in-development application, not a demo. It runs against PostgreSQL, signs
> people in through Privy, and reads Base mainnet. Product surfaces are closed by default and
> only open when a deployment says so explicitly.

## Quickstart

You need Erlang, Elixir, Node, and PostgreSQL at the versions pinned in `.tool-versions`.

```bash
createdb ash_platform_dev
cp .env.example .env
touch .env.local
printf '%s\n' 'source_env .env' 'source_env_if_exists .env.local' > .envrc
mix setup
mix ash_platform.setup_local_auth
mix phx.server
```

The site is then at `http://localhost:4000`. Sign-in needs real Privy credentials — see
[docs/local-privy-auth.md](docs/local-privy-auth.md) for where they come from and how to load
them. The values are loaded from `.env` and `.env.local` through direnv; put real values
only in the ignored `.env.local`, never in `.env.example`, and commit none of the three.

> [!NOTE]
> The local flow talks to one loopback PostgreSQL database, `ash_platform_dev`, on
> `127.0.0.1`, and database startup stays off unless it is explicitly enabled. What does
> leave the machine: Privy for sign-in verification, the configured Base RPC endpoint for
> Stake and Redeem reads, and the Sprites API when Formation runtimes are used.

## Where this sits

```text
  client surfaces
    ios                               mobile app, wallet, action signing
    regents-cli                       operator control surface
    regents-techtree-hermes-plugin    Hermes mission-control tab
                    │
                    ▼
  platform
    ash-platform                      Phoenix, LiveView, Ash: web, API, product domains   ◀ this repository
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

## Configuration

Read at runtime by `config/runtime.exs`. Values come from your ignored `.env.local` in
development and from the deployment's secret store in production.

| Variable | Required | What it is for |
| --- | --- | --- |
| `PRIVY_APP_ID` | For sign-in | The Privy application that browser sign-in runs against. |
| `PRIVY_VERIFICATION_KEY` | For sign-in | Privy's PEM-encoded ES256 verification **public** key — not the app secret. |
| `SIWA_SERVER_URL` | For signed agent requests | Base URL of the `siwa-server` verification service. |
| `SIWA_AUDIENCE` | For signed agent requests | Audience value required for agent request verification. |
| `SPRITES_TOKEN` | For Formation | Server-only token used to provision and inspect Formation runtimes. |
| `BASE_READ_RPC_URL` | Yes in production | Base mainnet JSON-RPC endpoint the Stake and Redeem pages read. Development falls back to a public endpoint. |
| `AUTOLAUNCH_INDEXER_RPC_URL` | For the indexer | Dedicated endpoint for the Base log ledger, kept separate from the simple-read RPC. |
| `ASH_PLATFORM_APP_SURFACES` | Yes in production | `on` opens the product surfaces. Anything else keeps them closed, so a typo closes rather than opens. Boot fails in production if unset. |
| `ASH_PLATFORM_AUTOLAUNCH_SURFACES` | No | `on` opens the Autolaunch pages and endpoints. Closed unless set. |
| `REGENT_ADMIN_WALLET_ADDRESSES` | No | Comma-separated wallets allowed to remove comments from any public record. |
| `TECHTREE_PUBLICATION_RATE_LIMIT` | No | Publications allowed per window. Defaults to `10`. |
| `TECHTREE_PUBLICATION_RATE_WINDOW_SECONDS` | No | Length of that window in seconds. Defaults to `60`. |
| `PHX_HOST` | Yes in production | Public hostname the endpoint builds URLs from. |
| `SECRET_KEY_BASE` | Yes in production | Session signing secret; must be at least 64 bytes. |
| `PORT` | No | HTTP port. Defaults to `4000`. |
| `DATABASE_POOLED_URL` | Yes in production | Pooled Postgres connection string. Rejected unless it is a well-formed PostgreSQL URL for an approved target. |
| `DATABASE_DIRECT_URL` | Only when migrating | Direct Postgres connection string, used by the migration release command. |
| `ASH_PLATFORM_DATABASE_TARGET_MODE` | Only when migrating | Must be `rehearsal`. `production` is refused outright. |
| `ASH_PLATFORM_DATABASE_CLUSTER_ID` | For a remote target | Must match the approved cluster, in development and when migrating. |
| `ASH_PLATFORM_DATABASE_CLUSTER_NAME` | For a remote target | Must match the approved cluster name. Set neither this nor the id to stay on the loopback database. |
| `ASH_PLATFORM_RELEASE_COMMAND` | Set by the release | `migrate` switches the boot into migration mode. |

## Public HTTP surface

`contracts/api-contract.openapiv3.yaml` is the source of truth for the API; the table below
is a map, not the contract.

| Route | Method | Purpose |
| --- | --- | --- |
| `/healthz` | GET | Liveness check, used by the Fly health check. |
| `/api/techtree/v1/trees` | GET | List published skill trees. |
| `/api/techtree/v1/trees/:slug/nodes` | GET | Nodes of one tree. |
| `/api/techtree/v1/nodes/:id` | GET | One node, and `/payload` for its contents. |
| `/api/techtree/v1/nodes` | POST | Publish a node (authenticated). |
| `/api/autolaunch/v1/auctions` | GET | List auctions; `/:id` for one, `/:id/bid-quote` to price a bid. |
| `/api/autolaunch/v1/tokens` | GET | List launched tokens. |
| `/api/formation/v1/regents/:regent_id/agent-links` | GET, POST | Read and claim agent links. |
| `/auth/privy/session` | POST, DELETE | Start and end a browser session. |
| `/` and `/app`, `/techtree`, `/autolaunch`, `/stake`, `/redeem`, `/settings` | LiveView | The public home page and the signed-in product shell. |

## Repository layout

```text
lib/ash_platform/       Ash domains: accounts, billing, formation, techtree, autolaunch,
                        discussions, identity, durable work
lib/ash_platform_web/   Endpoint, router, LiveViews, controllers, components
lib/mix/tasks/          Local setup, reset, contract sync, and route-handoff checks
contracts/              The OpenAPI contract, chain-contract manifest, and ABIs
config/                 Compile-time and runtime configuration
assets/                 TypeScript and CSS, built with esbuild
priv/                   Migrations, static assets, generated resource snapshots
test/                   ExUnit suites, including browser and budget tests
docs/                   Local setup guides, operations notes, plans, and specs
bin/, scripts/          Local acceptance and release helpers
rel/                    Release overlays, including the migrate command
```

## Checks

All three repository acceptance commands must pass before a change is proposed:

```bash
mix precommit
npm run typecheck
npm test
```

It compiles with warnings as errors, checks unused dependency locks and formatting, runs
Credo in strict mode and Sobelow, holds the compile-connected `xref` graph under its limit,
runs the test suite with warnings as errors, and verifies the Ash codegen and route handoff
are up to date.

Other relevant checks are available for browser behavior, asset budgets, and external tooling:

| Command | What it does |
| --- | --- |
| `npm run typecheck` | Type-checks the TypeScript assets. |
| `npm test` | Runs the Vitest unit suite. |
| `npm run test:browser` | Builds assets and runs the Playwright browser suite. |
| `npm run test:budgets` | Enforces the asset size budgets. |
| `mix test.external` | Runs three browser-fixture tests and one Docker build-context test. Excluded from `mix precommit` because they require local services or tools outside the hermetic test suite. |

## Deployment

> [!WARNING]
> Deploying runs `/app/bin/migrate` as its release command, so a deploy writes database
> migrations. The migration path refuses to run unless the target is the approved rehearsal
> cluster; a production target is refused outright and needs separately authorised
> configuration. Production boot also fails unless `ASH_PLATFORM_APP_SURFACES`,
> `BASE_READ_RPC_URL`, `PHX_HOST`, and a 64-byte `SECRET_KEY_BASE` are all set. Confirm the
> target and its secrets before running a deploy.

The image is built from `Dockerfile` and the Fly configuration lives in `fly.toml`.

## The other repositories

| Repository | What it is | What it deliberately does not do |
| --- | --- | --- |
| `autolaunch-contracts` | A clean-room Solidity implementation of the founder-frozen Autolaunch V1 system, controlled by its own `SPEC.md`. | It authorises no deployment, signature, or value movement; the older Autolaunch code in `regent-contracts` is historical reference only. |
| `design-system` | The shared Regent visual language: the style guide, design tokens, logos, fonts, and the `regent_ui` Phoenix component library. | Shared components never own product workflow state, authorisation decisions, money movement, or product database behaviour. |
| `elixir-utils` | A collection of standalone Elixir libraries used across the family: SIWA, ENS, XMTP, a cache, agentbook helpers, and the in-house `credo_ash` lint checks. | Each package is a library only; none of them runs a service or holds product behaviour. |
| `fly-sentinel` | A small Phoenix service that reports Fly.io observability and operator preview checks. | It observes and reports; it does not deploy, scale, or change any other application. |
| `ios` | The Expo and React Native mobile app: the mobile wallet, action signing, and mobile Regent records. | It consumes the platform HTTP contracts and owns no server-side product logic. |
| `media-web` | A standalone Phoenix service that serves hosted Regents card images and video files from `media.regents.sh`. | It only serves bytes over HTTP; it holds no identity, database, or product logic. |
| `python-cli` | The installable `regents-techtree` Python package, whose shipped surface is a deterministic offline inspection of one champion/challenger skill-tree pair. | It does not evaluate or execute an agent, and it makes no network calls once its locked dependencies are installed. |
| `regent-contracts` | The canonical home for Regent Solidity source, Foundry tests, deployment scripts, verified deployment records, ABIs, and the chain-contract manifest. | It holds no HTTP or CLI contracts, Ash resources, workflow logic, UI, or projection workers. |
| `regents-cli` | The operator control surface: the `regents` command line tool, its generated bindings, and its local runtime. | It drives the platform over published contracts and owns no product database or on-chain authority. |
| `regents-techtree-hermes-plugin` | The Hermes plugin that presents Techtree mission control across Forge, Techtree Verify, and Uplift. | It is presentation only: no second task store, no private Verify database, no identity model, no payment system, and no Hermes runtime of its own. |
| `siwa-server` | The shared Sign-In With Anything service for signed agent requests, nonce and replay state, and internal keyring endpoints. | It owns no product data or product authorization policy. |
| `videocontrol` | A separate product: video project workflows, timeline editing, preview rendering, and Codex plugin media control. | It shares the house style but no runtime, database, or contract with the Regent platform. |

## License

MIT — see [LICENSE](LICENSE).
