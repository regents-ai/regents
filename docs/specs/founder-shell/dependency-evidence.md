# Dependency evidence — 2026-07-10

Versions were observed from the official registries at `2026-07-10T17:29:56Z`; prereleases were excluded. Hex packages use `mix hex.info PACKAGE` and `https://hex.pm/packages/PACKAGE`. npm packages use `npm view PACKAGE version --json` and `https://www.npmjs.com/package/PACKAGE`. “Locked” is read from `mix.lock` or `package-lock.json`, not inferred from the declared range.

## Direct Hex dependencies

| Package | Official query | Current stable | Locked | Why it is direct |
|---|---|---:|---:|---|
| phoenix | `mix hex.info phoenix` | 1.8.9 | 1.8.9 | HTTP router, endpoint, components, and application web foundation. |
| phoenix_live_reload | `mix hex.info phoenix_live_reload` | 1.6.2 | 1.6.2 | Development-only browser reload for local template and asset work. |
| phoenix_live_view | `mix hex.info phoenix_live_view` | 1.2.6 | 1.2.6 | Persistent shell navigation, server-rendered UI, async content, and LiveView tests. |
| ash | `mix hex.info ash` | 3.29.3 | 3.29.3 | Phase 1 application framework boundary and future capability foundation; no resource or data layer is introduced yet. |
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
| animejs | `npm view animejs version --json` | 4.5.0 | 4.5.0 | Approved Design-handoff motion dependency; its use is reserved for the immediate Design slice. |
| @playwright/test | `npm view @playwright/test version --json` | 1.61.1 | 1.61.1 | Browser proof for navigation, history, scroll, persistence, responsive, and accessibility behavior. |
| typescript | `npm view typescript version --json` | 7.0.2 | 7.0.2 | Static checking for Ash-owned browser hooks and Design composition seams. |
| vitest | `npm view vitest version --json` | 4.1.10 | 4.1.10 | Deterministic hook, state, theme, and asset-budget tests. |

Official npm source for every row is the package page formed from the package name, for example `https://www.npmjs.com/package/animejs`; the query command above is the official npm client equivalent.

## Audit evidence

The resolved environment is Elixir 1.19.5, Erlang/OTP 28, Node 25.8.0, and npm 11.11.0. Exact Hex and npm lockfiles are present.

- `mix hex.outdated` completed successfully at `2026-07-10T18:47:47Z`: all direct Hex dependencies were current. The retained transitive exception is unchanged: `lazy_html` 0.1.11 requires `elixir_make ~> 0.9.0`, while 0.10.0 exists. Phase 1 does not promote, override, or otherwise alter that transitive package.
- `mix hex.audit` completed successfully at `2026-07-10T18:47:47Z` with no advisories.
- `npm audit --json` completed successfully at `2026-07-10T18:47:47Z` with 0 vulnerabilities.
- `npm outdated --json` completed successfully at `2026-07-10T18:47:47Z` and returned `{}`.

The local Phoenix generator cache is 1.8.4; it was used only to create the mechanical skeleton. Runtime Phoenix is independently resolved and locked at 1.8.9 as shown above.
