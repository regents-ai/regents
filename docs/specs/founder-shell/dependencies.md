# Dependency provenance and policy

Immediately before generation and again before commit, query official registries:

```sh
mix hex.info phx_new
mix hex.info phoenix
mix hex.info phoenix_live_view
mix hex.info ash
mix hex.info bandit
mix hex.info esbuild
mix hex.info tailwind
mix hex.info igniter_new
mix hex.info igniter
npm view typescript version
npm view animejs version
npm view vitest version
npm view @playwright/test version
```

Use only current stable releases. Record the observed version, UTC time, command, resolved lock version, and reason each direct dependency exists. Exact lockfiles are mandatory. `AshPostgres`, direct Ecto/EctoSQL/Postgrex/PhoenixEcto, a Repo, database config, and migration aliases are forbidden in Phase 1. Ash core's locked transitive Ecto is allowed. Anime.js is the sole approved pre-use exception for the immediate Design handoff and must be used by that slice or removed.

Before commit run `mix hex.outdated`, `mix hex.audit`, `npm outdated`, and `npm audit --audit-level=high`, distinguishing unavoidable transitives from avoidable direct pins.
