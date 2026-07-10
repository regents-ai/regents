# Slice 01 — isolated scaffold (`regent-2mf0.1`)

Generate in an empty temporary directory with current official Phoenix tooling, `--app ash_platform --module AshPlatform --no-ecto --no-mailer --no-agents-md`, then transfer without overwriting this repo's `.git` or `docs`. Add Ash core only. Remove generated deployment, database, dashboard, gettext, and unused runtime surfaces. Use TypeScript at `assets/js/app.ts`.

Acceptance: dependency evidence and exact locks; compile/test; no Repo, DB config, migrations, old-platform reference, or production runtime surface; supported outdated/audit checks.
