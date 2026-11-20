# Regents platform

This is the Phoenix/Ash component of the Regents monorepo. Run Mix and npm here.
`lib/regents/` owns domains; `lib/regents_web/` owns routes and LiveViews. Each product
(Stake, Redeem, Cloak, Account) has one folder and namespace on each side
(`Regents.Stake.*` in `lib/regents/stake/`, `RegentsWeb.Stake.*` in
`lib/regents_web/stake/`), chain plumbing two products share is `Regents.Chain.*` and
`RegentsWeb.Chain.*`, and the rest is the site itself. The `boundary` compiler fails the
build when one product's pages use another product's pages, or Account pages other than
`RegentsWeb.Account.Identity` and `RegentsWeb.Account.PrivyPair`; Account's core is
reached only through its exports. Not yet enforced: a product's pages can still call
another product's core, because they inherit what `RegentsWeb` may use.
`contracts/` here contains runtime API/ABI/manifests; Solidity lives in the monorepo's
root `contracts/`. Keep internal OTP/release names stable during layout changes.

Follow the root instructions and the workspace's `regent-workflow`. Use the
assignment's acceptance and applicable focused checks. Twelve shared libraries are
the repository's own `../shared` folders, named by path in `mix.exs`; `siwa`,
`regent_chain` and `regent_ui` are git pins there. `../shared/SOURCE.json` records the
library commit the copies come from; a newer one is taken in by copying the packages
again from it and moving that commit.

## Adding a product

- Add one entry to the list in `products/0` in `lib/regents/products.ex`, the one list of
  products: its lowercase name, the `health/0` of its core, and its schema (or
  `nil`), with its core in that module's Boundary `deps`. The name is its address (`/<name>` for pages, `/api/v1/<name>` for its
  API) and its namespace (`Regents.<Name>`). From that entry `/api/v1/health`
  reports it under `products`, every visit line from its addresses and jobs
  carries `product: "<name>"`, and the release walks its schema. Anything not
  under a product's address is `regents`.
- Its core's `health/0` answers `:ok` or `{:error, reason}` from what the site
  already holds (a stored reading, a database read): never a call to another
  service. The health page asks every product at once and cuts each off at one
  second; a product that fails, raises or is slow reads `unavailable` alone,
  and the answer stays 200 (`RegentsWeb.HealthController`).
- `data-brand` is a different word: the look a page wears, in design-system's
  vocabulary, always `Regent.Site.brand/1` of the page's product. regents.sh's own
  pages, Keyfleet, staking, SIWA and Cloak wear `platform`; Techtree, Autolaunch and
  Patchbay wear their own.
- A page takes its product's colours (design-system's `data-product` blocks: main
  button, links, focus ring, chosen tab). A product with a look of its own restates
  its own in its scoped tokens, per theme, so they win: Techtree in
  `assets/css/techtree/app.css`, Keyfleet in `assets/css/keyfleet/tokens/root.css`.
  Autolaunch and Patchbay wear design-system's until their own pages come in.

### The one-site bar and the page's three attributes

- Every page carries `data-product`, `data-brand` and `data-home` on `<html>`, written
  in one place, the root layout. The product comes from the router (`put_product` in
  each pipeline) or, in the app shell, from the route catalog (`RouteCatalog.product/1`);
  the brand is `Regent.Site.brand/1` of it; `data-home` is the home colour,
  `config :regents, :home_colour`, with a `?home=` preview marked in
  `RegentsWeb.Layouts.home_colour/1` until the founder picks one.
- Every page shows the site's bar, `RegentsWeb.Components.Shell.site_bar/1` around
  `Regent.Site.bar`: the crown, the product menu, the product's own links (its
  `links` slot) and the account control. No product draws a header of its own.
- In the app shell only Regents' and Protocol's pages carry the side menu (the app's
  pages and the reading, `RouteCatalog`); another product's page there carries none,
  and no Menu, and runs the frame's full width. The bar's product menu is the one way
  between products.
- The root layout is not redrawn by live navigation, so a link from one product's
  pages to another's is a plain `href` load, never `navigate` or `patch`.
- Core, `lib/regents/<product>.ex`:
  `use Boundary, top_level?: true, deps: [Regents, Regents.Chain], exports: [...]`
  (drop `Regents.Chain` if it reads no chain). It may use the site core and, through
  `Regents`' exports, the account parts below.
- Actors: `Actors.Human` (built from an account by `Human.for_account/1`), `Actors.Agent`,
  `Actors.System` and `Actors.ConnectedApp` (the struct only). An Agent may be unpaired:
  its `pairing` is the person's `Human`, `:none` or `:person_not_here`, decided only by
  `Agent.with_pairing/1`. Protected work requires the paired shape: a policy admits an
  agent with `{RegentAgents.Checks.Paired, repo: Regents.Repo}`, and a write locks the
  pairing inside its transaction: `change {RegentAgents.RequirePairing, repo:
  Regents.Repo}` on its Ash action, or `Agent.lock_pairing/1` elsewhere (it raises
  outside a transaction); `Agent.valid?/1` and `refresh/1` read it again. A product
  never names `RegentAgents.Authority`.
- Reads: `Accounts.accounts_by_ids/2`, `accounts_by_ids!/2` and
  `accounts_holding_wallets!/2` (wallets in any case), each taking at most 100 ids or
  wallets a read; `PublicIdentity.people/1` for a product that only shows people;
  `SessionAuthority.current_id/2` and `signed_in/2` for a sign-in kept by its id (they
  do not check the generation number).
- `Regents.Alert.report/1` saves what a person must act on with the site's errors, and
  `Regents.Limits.admit/2` and `spend/2` spend a named allowance from the one list,
  `config :regents, :limits`, named `<product>_<name>`: the prefix is required, as the
  allowances share the site's counters.
- Pages, `lib/regents_web/<product>.ex`:
  `use Boundary, deps: [RegentsWeb, RegentsWeb.Chain], exports: [...]`, exporting only
  what the shell and router mount. It may use the `RegentsWeb` toolkit and its two
  Account exports (`Account.Identity`, `Account.PrivyPair`), and `RegentsWeb.Chain`.
- Add the core to `RegentsWeb`'s `deps` in `lib/regents_web.ex` so the shell can mount it.
- Use your own core only; the compiler does not stop a call into another product's core.

### A product with its own look (Techtree)

A product that keeps its own pages and look, rather than living in the shell, follows
Techtree (`lib/regents_web/techtree/`):

- One `scope "/<product>"` in the router with its own `live_session`, layout and
  `on_mount`, and a pipeline that sets `put_product`. Its layout puts the site's bar
  first, with the product's links in it. The regents.sh footer stays off its pages.
- Stylesheets in `assets/css/<product>/`, each file wrapped in
  `@scope (:root[data-brand="<product>"]) { ... }` (or `data-product`, when the
  product wears another product's brand, as Keyfleet does) and imported once from
  `app.css`.
  Inside the scope a selector is read as a descendant of `<html>`, so a rule for the
  page itself is written `:scope` (not `html` or `:root`), or it never applies.
- Hooks in `assets/js/<product>/`, merged into the one `app.ts`. Keep a product's
  lazy imports lazy.
- Static files in `priv/static/images/<product>/`, other files in `priv/<product>/`,
  read with `Application.app_dir(:regents, ...)`. regents.sh's favicon serves every page.
- Record what was taken from the product's own repository, at which commit, in
  `lib/regents/<product>/SOURCE.json`.

### A product with its own frame (Keyfleet)

Keyfleet's pages share one frame (`RegentsWeb.Keyfleet.Components.Shell`), drawn by one
LiveView that patches between them (`RegentsWeb.Keyfleet.ShellLive`, each page named by
its live action in `RegentsWeb.Keyfleet.RouteCatalog`):

- The frame keeps its own element names, which are also regents.sh's frame's
  (`#app-shell`, `#shell-sidebar`, `.mobile-menu-button`). regents.sh's rules for those
  names are keyed on its frame's own class, `:where(.regents-frame)` (no added weight),
  so they reach that frame whatever product its page names and never Keyfleet's.
  Keyfleet wears the `platform` brand, so its stylesheets are scoped
  `@scope (:root[data-product="keyfleet"]) to (.regents-frame)`: they stop at
  regents.sh's frame, which Keyfleet's overview (`/keyfleet`) wears. The sign-in control's rules
  (`.account-control`, `.account-chip`, `.account-name`, `.account-avatar`) stay shared,
  as every product's bar holds the site's control.
- The frame starts with the site's bar (`Shell.site_bar product="keyfleet"`), with no
  links in it: the sidebar holds Keyfleet's pages, behind Menu on a phone.
- The frame's hook is the product's (`KeyfleetShell`), composed with the site's
  `ShellViews`. It never sets the page's attributes; the root layout does.

### A product's carried documents

Guides and pages carried from a product's own site keep every word but their addresses
(each change is listed in its `SOURCE.json`):

- A product page or guide gains the product's address: `{{origin}}/docs` becomes
  `{{origin}}/keyfleet/docs`, `/skill.md` becomes `/keyfleet/skill.md`.
- An API address under `/api/v1/` gains the product: `/api/v1/agent/rooms` becomes
  `/api/v1/keyfleet/agent/rooms`.
- `/mcp`, `/oauth…`, `/api/agents/v1/…` and `/account…` stay as they are: they are
  regents.sh's. A person pairs an agent on `/account/agents`, so `/pair` becomes that.
- The product's own hosts stay (`https://code.keyfleet.ai`, a fleet's notebooks host,
  `https://keyfleet.ai/metadata/…`), the sign-in audience is `regents`, and the
  product's name stays.
- An address a guide fills in when served reads a plain setting,
  `config :regents, :<product>_<name>` (Keyfleet's sign-in, code and notebook
  addresses), never a secret.

### A product's tables

A folded product's tables stay in its own schema of the one database (Techtree's is
`techtree_app`), with its own migrations and its own ledger, all on `Regents.Repo`:

- Its resources say `schema "<product>_app"` and `repo Regents.Repo`, keep their table
  names, and its domains are in `config :regents, ash_domains` under `Regents.<Product>.*`.
- Give its entry in `lib/regents/products.ex` `schema: "<product>_app"`.
  `bin/migrate`, `bootstrap-staging`, `mix regents.setup_local_auth` and
  `bin/pending-migrations` then walk it after `regents_app`, each schema with its own
  `<schema>.schema_migrations`; `pending-migrations` names every entry as schema and version.
- Migrations in `priv/<product>/migrations/`, snapshots in
  `priv/<product>/resource_snapshots/`. `mix ash.codegen` (and `--check`) runs once for
  regents.sh's domains and once for each product's, each into its own folders. Name a
  product's migration after it (`mix ash.codegen techtree_add_x`): every migration module
  is `Regents.Repo.Migrations.<Name>`, and the product's carried ones start with its name.
- Migrations carried from the product's own repository keep their versions and SQL; only
  the module name changes, plus `prefix()` wherever the SQL named another schema or none.
  Tables this site does not read yet are still created. Its `extensions.json` is carried;
  its resource snapshots are generated here (`--snapshots-only`), for its resources here.
- Locally, `mix regents.setup_local_auth` applies a product's new migrations; the stock
  `mix ecto.migrate` covers `regents_app` only.

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- ash-start -->
## ash usage
_A declarative, extensible framework for building Elixir applications._

[ash usage rules](deps/ash/usage-rules.md)
<!-- ash-end -->
<!-- ash:actions-start -->
## ash:actions usage
[ash:actions usage rules](deps/ash/usage-rules/actions.md)
<!-- ash:actions-end -->
<!-- ash:aggregates-start -->
## ash:aggregates usage
[ash:aggregates usage rules](deps/ash/usage-rules/aggregates.md)
<!-- ash:aggregates-end -->
<!-- ash:authorization-start -->
## ash:authorization usage
[ash:authorization usage rules](deps/ash/usage-rules/authorization.md)
<!-- ash:authorization-end -->
<!-- ash:calculations-start -->
## ash:calculations usage
[ash:calculations usage rules](deps/ash/usage-rules/calculations.md)
<!-- ash:calculations-end -->
<!-- ash:code_interfaces-start -->
## ash:code_interfaces usage
[ash:code_interfaces usage rules](deps/ash/usage-rules/code_interfaces.md)
<!-- ash:code_interfaces-end -->
<!-- ash:code_structure-start -->
## ash:code_structure usage
[ash:code_structure usage rules](deps/ash/usage-rules/code_structure.md)
<!-- ash:code_structure-end -->
<!-- ash:data_layers-start -->
## ash:data_layers usage
[ash:data_layers usage rules](deps/ash/usage-rules/data_layers.md)
<!-- ash:data_layers-end -->
<!-- ash:exist_expressions-start -->
## ash:exist_expressions usage
[ash:exist_expressions usage rules](deps/ash/usage-rules/exist_expressions.md)
<!-- ash:exist_expressions-end -->
<!-- ash:generating_code-start -->
## ash:generating_code usage
[ash:generating_code usage rules](deps/ash/usage-rules/generating_code.md)
<!-- ash:generating_code-end -->
<!-- ash:migrations-start -->
## ash:migrations usage
[ash:migrations usage rules](deps/ash/usage-rules/migrations.md)
<!-- ash:migrations-end -->
<!-- ash:query_filter-start -->
## ash:query_filter usage
[ash:query_filter usage rules](deps/ash/usage-rules/query_filter.md)
<!-- ash:query_filter-end -->
<!-- ash:querying_data-start -->
## ash:querying_data usage
[ash:querying_data usage rules](deps/ash/usage-rules/querying_data.md)
<!-- ash:querying_data-end -->
<!-- ash:relationships-start -->
## ash:relationships usage
[ash:relationships usage rules](deps/ash/usage-rules/relationships.md)
<!-- ash:relationships-end -->
<!-- ash:signals-start -->
## ash:signals usage
[ash:signals usage rules](deps/ash/usage-rules/signals.md)
<!-- ash:signals-end -->
<!-- ash:temporal-start -->
## ash:temporal usage
[ash:temporal usage rules](deps/ash/usage-rules/temporal.md)
<!-- ash:temporal-end -->
<!-- ash:testing-start -->
## ash:testing usage
[ash:testing usage rules](deps/ash/usage-rules/testing.md)
<!-- ash:testing-end -->
<!-- ash_oban-start -->
## ash_oban usage
_The extension for integrating Ash resources with Oban._

[ash_oban usage rules](deps/ash_oban/usage-rules.md)
<!-- ash_oban-end -->
<!-- ash_oban:best_practices-start -->
## ash_oban:best_practices usage
[ash_oban:best_practices usage rules](deps/ash_oban/usage-rules/best_practices.md)
<!-- ash_oban:best_practices-end -->
<!-- ash_oban:debugging_and_error_handling-start -->
## ash_oban:debugging_and_error_handling usage
[ash_oban:debugging_and_error_handling usage rules](deps/ash_oban/usage-rules/debugging_and_error_handling.md)
<!-- ash_oban:debugging_and_error_handling-end -->
<!-- ash_oban:defining_triggers-start -->
## ash_oban:defining_triggers usage
[ash_oban:defining_triggers usage rules](deps/ash_oban/usage-rules/defining_triggers.md)
<!-- ash_oban:defining_triggers-end -->
<!-- ash_oban:multi_tenancy_support-start -->
## ash_oban:multi_tenancy_support usage
[ash_oban:multi_tenancy_support usage rules](deps/ash_oban/usage-rules/multi_tenancy_support.md)
<!-- ash_oban:multi_tenancy_support-end -->
<!-- ash_oban:scheduled_actions-start -->
## ash_oban:scheduled_actions usage
[ash_oban:scheduled_actions usage rules](deps/ash_oban/usage-rules/scheduled_actions.md)
<!-- ash_oban:scheduled_actions-end -->
<!-- ash_oban:setting_up_ash_oban-start -->
## ash_oban:setting_up_ash_oban usage
[ash_oban:setting_up_ash_oban usage rules](deps/ash_oban/usage-rules/setting_up_ash_oban.md)
<!-- ash_oban:setting_up_ash_oban-end -->
<!-- ash_oban:triggering_jobs_programmatically-start -->
## ash_oban:triggering_jobs_programmatically usage
[ash_oban:triggering_jobs_programmatically usage rules](deps/ash_oban/usage-rules/triggering_jobs_programmatically.md)
<!-- ash_oban:triggering_jobs_programmatically-end -->
<!-- ash_oban:working_with_actors-start -->
## ash_oban:working_with_actors usage
[ash_oban:working_with_actors usage rules](deps/ash_oban/usage-rules/working_with_actors.md)
<!-- ash_oban:working_with_actors-end -->
<!-- ash_phoenix-start -->
## ash_phoenix usage
_Utilities for integrating Ash and Phoenix_

[ash_phoenix usage rules](deps/ash_phoenix/usage-rules.md)
<!-- ash_phoenix-end -->
<!-- ash_phoenix:best_practices-start -->
## ash_phoenix:best_practices usage
[ash_phoenix:best_practices usage rules](deps/ash_phoenix/usage-rules/best_practices.md)
<!-- ash_phoenix:best_practices-end -->
<!-- ash_phoenix:debugging_form_submissions-start -->
## ash_phoenix:debugging_form_submissions usage
[ash_phoenix:debugging_form_submissions usage rules](deps/ash_phoenix/usage-rules/debugging_form_submissions.md)
<!-- ash_phoenix:debugging_form_submissions-end -->
<!-- ash_phoenix:error_handling-start -->
## ash_phoenix:error_handling usage
[ash_phoenix:error_handling usage rules](deps/ash_phoenix/usage-rules/error_handling.md)
<!-- ash_phoenix:error_handling-end -->
<!-- ash_phoenix:form_integration-start -->
## ash_phoenix:form_integration usage
[ash_phoenix:form_integration usage rules](deps/ash_phoenix/usage-rules/form_integration.md)
<!-- ash_phoenix:form_integration-end -->
<!-- ash_phoenix:nested_forms-start -->
## ash_phoenix:nested_forms usage
[ash_phoenix:nested_forms usage rules](deps/ash_phoenix/usage-rules/nested_forms.md)
<!-- ash_phoenix:nested_forms-end -->
<!-- ash_phoenix:union_forms-start -->
## ash_phoenix:union_forms usage
[ash_phoenix:union_forms usage rules](deps/ash_phoenix/usage-rules/union_forms.md)
<!-- ash_phoenix:union_forms-end -->
<!-- ash_postgres-start -->
## ash_postgres usage
_The PostgreSQL data layer for Ash Framework_

[ash_postgres usage rules](deps/ash_postgres/usage-rules.md)
<!-- ash_postgres-end -->
<!-- ash_postgres:advanced_features-start -->
## ash_postgres:advanced_features usage
[ash_postgres:advanced_features usage rules](deps/ash_postgres/usage-rules/advanced_features.md)
<!-- ash_postgres:advanced_features-end -->
<!-- ash_postgres:best_practices-start -->
## ash_postgres:best_practices usage
[ash_postgres:best_practices usage rules](deps/ash_postgres/usage-rules/best_practices.md)
<!-- ash_postgres:best_practices-end -->
<!-- ash_postgres:check_constraints-start -->
## ash_postgres:check_constraints usage
[ash_postgres:check_constraints usage rules](deps/ash_postgres/usage-rules/check_constraints.md)
<!-- ash_postgres:check_constraints-end -->
<!-- ash_postgres:configuration-start -->
## ash_postgres:configuration usage
[ash_postgres:configuration usage rules](deps/ash_postgres/usage-rules/configuration.md)
<!-- ash_postgres:configuration-end -->
<!-- ash_postgres:custom_indexes-start -->
## ash_postgres:custom_indexes usage
[ash_postgres:custom_indexes usage rules](deps/ash_postgres/usage-rules/custom_indexes.md)
<!-- ash_postgres:custom_indexes-end -->
<!-- ash_postgres:custom_sql_statements-start -->
## ash_postgres:custom_sql_statements usage
[ash_postgres:custom_sql_statements usage rules](deps/ash_postgres/usage-rules/custom_sql_statements.md)
<!-- ash_postgres:custom_sql_statements-end -->
<!-- ash_postgres:foreign_keys-start -->
## ash_postgres:foreign_keys usage
[ash_postgres:foreign_keys usage rules](deps/ash_postgres/usage-rules/foreign_keys.md)
<!-- ash_postgres:foreign_keys-end -->
<!-- ash_postgres:migrations-start -->
## ash_postgres:migrations usage
[ash_postgres:migrations usage rules](deps/ash_postgres/usage-rules/migrations.md)
<!-- ash_postgres:migrations-end -->
<!-- ash_postgres:multitenancy-start -->
## ash_postgres:multitenancy usage
[ash_postgres:multitenancy usage rules](deps/ash_postgres/usage-rules/multitenancy.md)
<!-- ash_postgres:multitenancy-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
[phoenix:phoenix usage rules](deps/phoenix/usage-rules/phoenix.md)
<!-- phoenix:phoenix-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
[phoenix:liveview usage rules](deps/phoenix/usage-rules/liveview.md)
<!-- phoenix:liveview-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
[phoenix:html usage rules](deps/phoenix/usage-rules/html.md)
<!-- phoenix:html-end -->
<!-- usage-rules-end -->
