# Dependency evidence — 2026-07-11

Versions were rechecked from the official registries on 2026-07-11; prereleases were excluded. Hex packages use `mix hex.info PACKAGE` and `https://hex.pm/packages/PACKAGE`. npm packages use `npm view PACKAGE version --json` and `https://www.npmjs.com/package/PACKAGE`. “Locked” is read from `mix.lock` or `package-lock.json`, not inferred from the declared range.

## Direct Hex dependencies

| Package | Official query | Current stable | Locked | Why it is direct |
|---|---|---:|---:|---|
| phoenix | `mix hex.info phoenix` | 1.8.9 | 1.8.9 | HTTP router, endpoint, components, and application web foundation. |
| phoenix_live_reload | `mix hex.info phoenix_live_reload` | 1.6.2 | 1.6.2 | Development-only browser reload for local template and asset work. |
| phoenix_live_view | `mix hex.info phoenix_live_view` | 1.2.6 | 1.2.6 | Persistent shell navigation, server-rendered UI, async content, and LiveView tests. |
| ash | `mix hex.info ash` | 3.29.3 | 3.29.3 | Canonical domain, action, policy, and code-interface framework. |
| ash_postgres | `mix hex.info ash_postgres` | 2.10.0 | 2.10.0 | Generated additive schemas for admitted application state. |
| igniter | `mix hex.info igniter` | 0.8.2 | 0.8.2 | Development/test-only Ash generators and source patching. |
| mdex | `mix hex.info mdex` | 0.13.3 | 0.13.3 | Restricted, sanitized record-comment Markdown. |
| picosat_elixir | `mix hex.info picosat_elixir` | 0.2.3 | 0.2.3 | SAT support required by Ash policy tooling. |
| simple_sat | `mix hex.info simple_sat` | 0.1.4 | 0.1.4 | SAT support required by Ash policy tooling. |
| req | `mix hex.info req` | 0.6.2 | 0.6.2 | Base chain read boundary. |
| sourceror | `mix hex.info sourceror` | 1.12.2 | 1.12.2 | Development/test-only source support required by the configured Spark formatter. |
| lazy_html | `mix hex.info lazy_html` | 0.1.11 | 0.1.11 | Test-only HTML parser used by LiveView/Floki assertions. |
| esbuild | `mix hex.info esbuild` | 0.10.0 | 0.10.0 | Mix-managed asset build and development watcher. |
| telemetry_metrics | `mix hex.info telemetry_metrics` | 1.1.0 | 1.1.0 | Declares endpoint and VM metric definitions consumed by telemetry supervision. |
| telemetry_poller | `mix hex.info telemetry_poller` | 1.3.0 | 1.3.0 | Periodically emits the VM measurements used by those metric definitions. |
| jason | `mix hex.info jason` | 1.4.5 | 1.4.5 | Canonical route-handoff JSON encoding and Phoenix JSON serialization. |
| bandit | `mix hex.info bandit` | 1.12.0 | 1.12.0 | HTTP/WebSocket server for development, tests, and later runtime packaging. |

Official Hex source for every row is the package page formed from the package name, for example `https://hex.pm/packages/phoenix`; the query command above is the official Hex client equivalent.

## Direct npm dependencies

| Package | Official query | Current stable | Locked | Why it is direct |
|---|---|---:|---:|---|
| @privy-io/react-auth | `npm view @privy-io/react-auth version` | 3.34.0 | 3.34.0 | Browser-human authentication and wallet provider. |
| @solana-program/system | `npm view @solana-program/system version` | 0.12.2 | 0.12.2 | Wallet dependency used by Privy’s supported Solana surface. |
| @solana-program/token | `npm view @solana-program/token version` | 0.14.0 | 0.14.0 | Wallet dependency used by Privy’s supported Solana token surface. |
| @solana/kit | `npm view @solana/kit version` | 7.0.0 | 6.10.0 | Latest stable compatible line; the current system/token packages require Kit 6. |
| animejs | `npm view animejs version` | 4.5.0 | 4.5.0 | Cancellable shell and voxel motion. |
| react | `npm view react version` | 19.2.7 | 19.2.7 | Privy bridge host. |
| react-dom | `npm view react-dom version` | 19.2.7 | 19.2.7 | Privy bridge host. |
| viem | `npm view viem version` | 2.55.0 | 2.55.0 | Typed Base wallet actions. |
| @playwright/test | `npm view @playwright/test version --json` | 1.61.1 | 1.61.1 | Browser proof for navigation, history, scroll, persistence, responsive, and accessibility behavior. |
| @types/react | `npm view @types/react version` | 19.2.17 | 19.2.17 | Strict React bridge types. |
| @types/react-dom | `npm view @types/react-dom version` | 19.2.3 | 19.2.3 | Strict React DOM bridge types. |
| typescript | `npm view typescript version --json` | 7.0.2 | 7.0.2 | Static checking for Ash-owned browser hooks and Design composition seams. |
| vitest | `npm view vitest version --json` | 4.1.10 | 4.1.10 | Deterministic hook, state, theme, and asset-budget tests. |

Official npm source for every row is the package page formed from the package name, for example `https://www.npmjs.com/package/animejs`; the query command above is the official npm client equivalent.

## Audit evidence

The resolved environment is Elixir 1.19.5, Erlang/OTP 28, Node 25.8.0, and npm 11.11.0. Exact Hex and npm lockfiles are present.

- `mix hex.outdated` completed successfully on 2026-07-11: every direct Hex dependency is current.
- `mix hex.audit` completed successfully on 2026-07-11 with no retired or advisory packages.
- `npm audit --omit=dev --audit-level=high` completed successfully after pinning transitive WebSocket 8.x packages to fixed release 8.21.0. Ten moderate `uuid` findings remain beneath Privy’s MetaMask/Wagmi path; npm’s suggested forced remediation would downgrade Privy and is not accepted.
- `npm outdated --json` reports only `@solana/kit` 7.0.0. The lock remains 6.10.0 because the latest stable `@solana-program/system` and `@solana-program/token` packages require Kit 6.

The local Phoenix generator cache is 1.8.4; it was used only to create the mechanical skeleton. Runtime Phoenix is independently resolved and locked at 1.8.9 as shown above.

## Reproducible artifact tooling

Marimo 0.23.14 is the current stable release observed from the official Python package source on 2026-07-11. It is not an application runtime dependency. The browser-notebook proof invokes that exact release through `uvx` to generate a static WebAssembly application, then hashes the complete export before admission. The web application serves and frames the resulting files; it never starts Python while someone views a node. See [local-techtree-notebooks.md](../../local-techtree-notebooks.md) for the publishing boundary and the [official Marimo WebAssembly export guide](https://docs.marimo.io/guides/exporting/webassembly_html/).
