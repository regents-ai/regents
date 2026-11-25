# Regents One-Site Cross-Product Alignment Standard

Every Regents Labs product (`patchbay`, `techtree`, `autolaunch`, `keyfleet`, plus `cloak` and core `regents` protocol/account/SIWA) lives inside this single monorepo (`regents-ai/regents`) and serves from `https://regents.sh`.

All four backend products (`patchbay`, `techtree`, `autolaunch`, `keyfleet`) **must converge on one exact shape** across all four pillars below. Run `make check-alignment` from the repository root to inspect per-product compliance at any time.

---

## Cross-Product Alignment Rule (Canonical Contract)

### 1. Code

- **Boundaries:** `Regents.<Product>` + `RegentsWeb.<Product>` top-level boundaries registered in `Regents.Products` (`platform/lib/regents/products.ex`).
- **Shared agent auth & actor:** Use the shared `RegentsWeb.Account.PairedAgent` plug (exported from `RegentsWeb`) and `%Regents.Account.Actors.Agent{}` actor struct everywhere — never maintain duplicate per-product SIWA/pairing plugs or custom actor structs.
- **Ash policies:** Authorize paired agents using `{RegentAgents.Checks.Paired, repo: Regents.Repo}` and `{RegentAgents.RequirePairing, repo: Regents.Repo}` inside Ash domain/resource policies.
- **Unified `/mcp` domain:** Expose each product's hosted MCP tools through `RegentsWeb.<Product>.AgentTools` (registered in `:regents, :ash_domains`), naming every tool `<product>_*` and returning structured `%{error: %{code, message, hint}}` refusals. No MCP tool ever signs an onchain transaction.

### 2. UI

- **Frame & bar:** Render every product inside `RegentsWeb.Layouts.root` + `<Shell.site_bar product="<product>">` + `<Regent.Structure.frame>`.
- **Active navigation across controllers and LiveViews:** Use `RegentsWeb.Layouts.on_mount(:page, ...)` (exported from `RegentsWeb`) on LiveViews alongside the router's `:put_current_path` plug so both controller and LiveView routes assign `@current_path` and highlight active nav identically.
- **Scoped CSS & shared tokens:** Wrap all product CSS strictly under:
  ```css
  @scope (:root[data-product="<product>"]:not([data-marketing])) to (.regents-frame) { ... }
  ```
  (Never use `data-brand` or unscoped base selectors that leak onto `[data-marketing]` or `.regents-frame` chrome.) Use Regents' shared `--color-*`, `--space-*`, `--radius`, and `--font-*` tokens across light and dark modes.
- **Emil design engineering craft (alongside `design-system/STYLE.md` Layers):**
  - Explicit transition properties only (never `transition: all`); strong `ease-out` (`var(--ease-out, cubic-bezier(0.23, 1, 0.32, 1))`) under `300ms`; never `ease-in` on UI chrome.
  - Crisp `:active` press feedback (`scale(0.97)` on buttons, `scale(0.985)` on cards) without post-release `outBack` bounce.
  - Origin-aware `@starting-style` popover/dropdown transitions (never `scale(0)`); zero animation on keyboard-triggered shortcuts.
  - Gate hover rules inside `@media (hover: hover) and (pointer: fine)` and positional/scale motion inside `@media (prefers-reduced-motion: no-preference)`.
  - Enforce `44px` (`2.75rem`) touch targets on coarse pointers and keep tab/mode switches layout-height invariant.

### 3. WebMCP & CLI

- **Single canonical manifest:** One `platform/priv/<product>/tool_manifest.json` per product (`audience: "regents"`) feeds all four consumers:
  1. `GET /api/v1/<product>/capabilities` (`RegentsWeb.ProductCapabilitiesController`)
  2. `RegentsWeb.<Product>.AgentTools` (Hosted MCP at `POST /mcp`)
  3. `platform/assets/js/product_webmcp.ts` (`document.modelContext` browser tools, hydrated from `/api/v1/<product>/capabilities`)
  4. Local `Regents.SiteTools` (`GET /api/v1/site-tools`, never fetching redirecting legacy domains)
- **Consistent product agent entry points:** Every product exposes:
  - `GET /<product>/skill.md`
  - `GET /<product>/llms.txt`
  - `GET /<product>/agents.md`
  - `GET /api/v1/<product>/capabilities`
  - Product docs under `/docs/<product>` and unified CLI docs at `/docs/cli` following `regents <product> <resource> <action>` using one `regents.sh` SIWA pairing (`regents auth login --site regents`).

### 4. Database

- **Single repo, isolated schema:** Use the single `Regents.Repo` with an isolated `<product>_app` schema (`patchbay_app`, `techtree_app`, `autolaunch_app`, `keyfleet_app`) and dedicated `platform/priv/<product>/migrations` ledger managed by `Regents.Products.migration_areas/0` and `Regents.Release.prepare_database!/1`.
- **Explicit prefixes everywhere:** Declare `schema("<product>_app")` on every folded AshPostgres resource, pass `prefix: "<product>_app"` on every direct `Repo.*` call or string-table query, and schema-qualify every raw SQL table (`<product>_app.<table>`).
- **Canonical identity anchors:** Anchor all user and agent ownership on `human_account_id` / `privy_user_id` / `pairing_id` (matching `regents_app` and `regent_agents`).
- **Shared ops in `regents_app`:** Keep one Oban instance (`prefix: "regents_app"`), one `ErrorTracker`, one `session_authorities` table, and one `left_messages` inbox in `regents_app`. Isolate Oban queues by product/failure domain within `Regents.DatabaseConfig`'s connection pool budget (`@server_pool_size = 15`).
