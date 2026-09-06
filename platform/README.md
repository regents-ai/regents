# Regents platform

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](../LICENSE)
[![Elixir 1.19](https://img.shields.io/badge/elixir-1.19-lightgrey)](https://elixir-lang.org)
[![Phoenix 1.8](https://img.shields.io/badge/phoenix-1.8-lightgrey)](https://www.phoenixframework.org)
[![Ash 3.32](https://img.shields.io/badge/ash-3.32-lightgrey)](https://ash-hq.org)
[![PostgreSQL 14](https://img.shields.io/badge/postgres-14-lightgrey)](https://www.postgresql.org)

The Regents platform is the main Regent web application, built by Regents Labs on Phoenix, LiveView,
and Ash. It serves the public site, the signed-in product shell, and the public HTTP API, and
retains Accounts, Formation and older Autolaunch routes during product cutovers.
New Autolaunch features belong to the Autolaunch monorepo.
Techtree remains a named product on the public site; it no longer lives in this app.

> [!IMPORTANT]
> This is a live, in-development application, not a demo. It runs against PostgreSQL, signs
> people in through Privy, and reads Base mainnet. Product surfaces are closed by default and
> only open when a deployment says so explicitly.

## Shared dependencies

From a directory containing sibling product repositories, acquire the shared libraries:

```sh
git clone https://github.com/regents-ai/design-system.git
git clone https://github.com/regents-ai/elixir-utils.git
```

The expected layout is `<workspace>/<product>/platform`,
`<workspace>/design-system/regent_ui` and `<workspace>/elixir-utils/`.
From this component directory, `REGENT_DEPS_ROOT` may point at `<workspace>` when
it is elsewhere. Record both shared repository commit IDs with check results;
release builds and isolated agent worktrees must use their selected immutable
revisions, rather than updating sibling checkouts during verification.
Do not clone recursive Solidity submodules for a web-only change.

## Quickstart

Run these commands from `platform/` after acquiring the shared dependencies.
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

## Product ownership

See the [Regents monorepo overview](../README.md) for current components and related products.
Each product owns its API and authorization; retained cross-product commands are not
a promise that their old server routes still exist.

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
| `PHX_HOST` | Yes in production | Public hostname the endpoint builds URLs from. |
| `SECRET_KEY_BASE` | Yes in production | Session signing secret; must be at least 64 bytes. |
| `PORT` | No | HTTP port. Defaults to `4000`. |
| `ASH_PLATFORM_DEPLOYMENT_ROLE` | Yes in production | `production` or `staging`, naming which venue this deployment is. There is no default: boot fails in production if it is unset or anything else. Each role admits only its own database hosts. |
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
| `/api/autolaunch/v1/auctions` | GET | List auctions; `/:id` for one, `/:id/bid-quote` to price a bid. |
| `/api/autolaunch/v1/tokens` | GET | List launched tokens. |
| `/api/formation/v1/regents/:regent_id/agent-links` | GET, POST | Read and claim agent links. |
| `/auth/privy/session` | POST, DELETE | Start and end a browser session. |
| `/` and `/app`, `/autolaunch`, `/stake`, `/redeem` | LiveView | The public home page and the signed-in product shell. |

## Repository layout

```text
lib/ash_platform/       Ash domains: accounts, formation, autolaunch,
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

The full platform gate is below. For focused changes, run the checks that exercise
the changed behavior; retain the required broader checks for protected changes:

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

The test database name carries whatever `MIX_TEST_PARTITION` holds, just before its `_test` ending.
Setting it is required, not advisory, whenever more than one test run can happen on a machine: every
writer and every working tree gives it its own value, an underscore followed by a short id, so that
the runs use separate databases. `MIX_TEST_PARTITION=_regent_88a` gives the database
`ash_platform_regent_88a_test`. The Autolaunch indexer tests deliberately run outside the sandbox,
empty the whole ledger when they start and finish, and compete for a single chain cursor row, so two
runs sharing one database corrupt each other's results. Run `MIX_ENV=test mix ecto.create` once for
a new value; the suite builds the schema itself on its first run.

## Deployment

> [!WARNING]
> Deploying runs `/app/bin/migrate` as its release command, so a deploy writes database
> migrations. Every deployment must name its venue in `ASH_PLATFORM_DEPLOYMENT_ROLE`, and
> each role admits only its own database hosts. Under the `production` role the migration
> path refuses to run unless the target is the approved rehearsal cluster; a production
> target is refused outright and needs separately authorised configuration. Production boot
> also fails unless `ASH_PLATFORM_APP_SURFACES`, `BASE_READ_RPC_URL`, `PHX_HOST`, and a
> 64-byte `SECRET_KEY_BASE` are all set. `/app/bin/pending-migrations` reports what a
> deployed database and the release image disagree about, without applying anything.
> Confirm the target and its secrets before running a deploy.

The image is built from `Dockerfile` and the Fly configuration lives in `fly.toml`.

## Related products

Use the [current product directory](../README.md#related-products).

## License

MIT — see [LICENSE](../LICENSE).

## Shared private profile

`/profile` uses the shared Regent UI and Regents-owned Ash identity domain.
The private `/api/v1/profile` contract provides `GET`, `PATCH`, and `POST /sync`;
the product CLI and browser WebMCP use the same actions and response schema.
Personal X verification comes from signed Privy evidence. Product sessions,
permissions and existing payout identities remain product-owned.

Resolve `REGENT_IDENTITY_PATH`, `REGENT_PRIVY_PATH` and `REGENT_UI_PATH` to the
recorded dependency snapshots for isolated work. Run `mix assets.build` after
changing a shared package. All deployments must use one Privy application and
one PostgreSQL destination before profiles can be shared between sites.
Regents owns the explicit identity migration; consumers do not run it on startup.
Do not repoint existing databases or replay migration histories: legacy identity
mappings, schema collisions and a recovery copy require a separate verified cutover.
See the identity package README and CLI private-profile contract for proof handling.

Historical names on `/profile` read the preserved `regent_names` tables through Ash.
`GET /api/v1/claims` requires fresh paired Privy proofs and returns only records owned
by verified linked wallets. It is paginated and read-only; private payments and
entitlements are preserved separately. Import these tables through the reviewed
preservation workflow before enabling the display against production records.
