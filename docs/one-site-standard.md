# Regents One-Site Architecture Standard

Every Regents Labs product (`cloak`, `techtree`, `keyfleet`, `autolaunch`, `patchbay`, plus core `regents` protocol/account/SIWA) lives inside this single monorepo (`regents-ai/regents`) and serves from `https://regents.sh`.

All product threads must converge onto the exact same four shapes below so every product reads, behaves, scales, and deploys identically.

---

## 1. Code Shape (`platform/lib/`)

| Concern | Canonical pattern | Avoid |
| --- | --- | --- |
| Domain core | `platform/lib/regents/<product>/` with a single top-level `use Boundary, top_level?: true` module (`Regents.<Product>`) | Placing `Ash.Domain` modules under `lib/regents_web/` |
| Web surface | `platform/lib/regents_web/<product>/` with thin LiveViews, controllers, and function components calling domain code interfaces | Business rules, policy checks, or multi-step persistence inside LiveViews |
| Router pipelines | Compose from core `:browser`, `:api`, `:paired_agent`, `:read_only` + a small product plug (`put_product`, `put_layout`) | Copying the 12-plug `:browser` pipeline or rolling parallel SIWA/profile stacks |
| Auth & session | Human sessions via `RegentsWeb.Live.Session` (`SessionAuthority`); paired agents via `RegentsWeb.Account.PairedAgent` (audience `"regents"`, `SIWA_SERVER_URL = https://siwa.regents.sh`) | Product-local `SIWA_*` env vars, unprefixed `"/"` redirects, or legacy `patchbay.help` error hints |
| API routes | Public JSON: `/api/v1/<product>/*` · Signed agent JSON: `/api/agent/v1/<product>/*` · Discovery: `/<product>/{llms.txt,skill.md,agents.md}` | Unprefixed `/api/v1/*`, `/<product>/*.json` root leaks, or standalone host links |
| Errors & rate limits | Structured `%{error: %{code, message, hint}}` via `RegentsWeb.ErrorJSON`; canonical `429` code `too_many_requests` with `Retry-After` and IETF `RateLimit` headers | Product-specific error shapes or flat `%{error: "string"}` payloads |
| Documentation | Authoritative product docs live under unified `/docs/<product>` (`RegentsWeb.Docs.Pages`); product `/<product>/docs` pages redirect or share the exact same source | Duplicating diverging doc copy between `/docs` and `/<product>/docs` |

---

## 2. UI Structure & Emil Design Engineering Craft

- **Shared chrome:** Every product page renders inside `RegentsWeb.Components.Shell.site_bar` with the shared `Regent.Account.menu`, shared `Regent.Primitives` / `Regent.Structure` components from `regent_ui`, and one consistent footer (`product_links`) pointing to unified `/docs/<product>`, `/about`, `/privacy`, and `/terms`.
- **Scoped CSS:** Every product stylesheet wraps its rules in:
  ```css
  @scope (:root[data-product="<product>"]:not([data-marketing])) to (.regents-frame) { ... }
  ```
  Never leak unscoped base `a`, `h1`-`h6`, or hover selectors onto `[data-marketing]` pages or into `.regents-frame` chrome.
- **Shared motion:** Use the single shared motion kit under `platform/assets/js/hooks/motion/` (never copy-paste per-product motion folders).
- **Emil design craft rules (alongside `design-system/STYLE.md` Layers):**
  - Specify explicit transition properties (never `transition: all`).
  - Use strong `ease-out` (`var(--ease-out, cubic-bezier(0.23, 1, 0.32, 1))`) for UI enter/exit and interactive feedback; never use `ease-in` on UI elements.
  - Keep UI animations under `300ms`: `100-160ms` for button press, `125-200ms` for popovers/tooltips, `150-250ms` for dropdowns.
  - Give pressable controls crisp `:active` feedback (`scale(0.97)` on buttons, `scale(0.985)` on cards) without rubbery post-release `outBack` bounce.
  - Never animate from `scale(0)`; enter popovers/menus with `@starting-style` from `opacity: 0; transform: scale(0.96) translateY(-4px)` with `transform-origin` anchored to their trigger (modals stay centered).
  - Never animate keyboard-initiated shortcuts or command palettes.
  - Gate hover styles in `@media (hover: hover) and (pointer: fine)` and positional/scale motion in `@media (prefers-reduced-motion: no-preference)`.
  - Enforce `44px` (`2.75rem`) minimum touch targets on coarse pointers.
  - Never shift layout height when switching tabs, modes, or inline error states (`STYLE.md` *Choices never change the height*).

---

## 3. WebMCP, Hosted MCP & CLI Structure

- **One manifest per product:** Each product commits `platform/priv/<product>/tool_manifest.json` (`audience: "regents"`), defining strict JSON Schemas, `readOnlyHint`/`untrustedContentHint`/`consequentialHint` annotations, and `requires` (`none` | `siwa` | `siwa_and_pairing`).
- **Browser WebMCP (`document.modelContext`):** All browser tools register through the shared registrar using the committed `priv/*/tool_manifest.json` files and `regent_agent_access/signed_tools` (exact tool names matching `regents browser`, zero hand-coded name drift).
- **Hosted MCP (`POST /mcp`):** All 5 products expose their agent-safe read/action tools through `AshAi.Mcp.Router` (authenticated via SIWA or OAuth 2.1 Bearer token). No MCP tool ever signs an onchain transaction.
- **Unified CLI (`regents-cli`):** Each product owns `cli/<product>/commands.json` inside `regents-ai/regents` (validated against `platform/priv/public/openapi.json` and `api-contract.openapiv3.yaml`), consumed by the single `regents-cli` package (`regents overview`, `regents <product> ...`, `regents browser`, `regents mcp`).

---

## 4. Database & Oban Structure

- **One schema per product:** Every product owns its dedicated Postgres schema (`regents_app`, `techtree_app`, `keyfleet_app`, `autolaunch_app`, `patchbay_app`) beside shared schemas (`regent_names`, `regent_identity`, `regent_agents`, `regent_points`, `regent_payments`).
- **Explicit schema prefixes everywhere:**
  - Every folded-product AshPostgres resource declares `schema("<product>_app")`.
  - Every direct Ecto `Repo.*` query or string-table `from(... in "table")` MUST pass `prefix: "<product>_app"` (`Regents.Repo` defaults to `regents_app`).
  - Every raw SQL string MUST schema-qualify every table (`<product>_app.<table>`).
- **Shared operational infrastructure in `regents_app`:**
  - One Oban instance (`prefix: "regents_app"`), one `ErrorTracker` (`regents_app`), one `session_authorities` table, and one `left_messages` inbox (`regents_app`). Never add new per-product `oban_jobs`, `error_tracker_*`, or `session_authorities` tables.
  - Isolate Oban queues by failure domain (`<product>_default`, `<product>_chain`, `<product>_webhooks`, etc.) and keep concurrency sized to `Regents.DatabaseConfig` `@server_pool_size` (`15` on PgBouncer).
- **Migrations & snapshots:** Every product's migrations live in `platform/priv/<product>/migrations` and snapshots in `platform/priv/<product>/resource_snapshots/repo`, run in deterministic order by `Regents.Release.migrate/0` via `Regents.Products.migration_areas/0`.
