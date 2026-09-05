# Local component workshop

Open `/showcase` on a development or test server using `localhost` or `127.0.0.1`.
The production configuration omits its routes. HTTP requests and connected
LiveView mounts both require a loopback peer and a loopback hostname; forwarded
headers do not grant access. Gallery styles and metadata use the same guard.

The workshop renders the active components installed from `regent_ui` and
`AshPlatformWeb.Components`, plus both layouts. It identifies the two panel
component aliases. Three Autolaunch LiveComponents have static signed-out previews
inside scriptless sandboxed frames. The shell preview includes working navigation
and theme behavior but omits sign-in controls. These product compositions are
Regents-owned, rather than newly shared components.

Eight thumbnail selectors pair each site’s light/dark palette with its supplied SVG
cutting mat. The defaults import the shared package’s generated token JSON, matching the hex labels in
`design-system/site color palettes`; the exact SVGs are generated from
`design-system/site svg backgrounds` into the shared package and copied by its asset task.
Regents uses charcoal, Autolaunch tangerine, Patchbay platinum, and Techtree powder
blue. All palette roles and the full background are available behind a disclosure.

Four editable colors—background, surface, text and primary—are stored separately
for each site/mode in a new browser storage namespace, so old experimental palettes
cannot override these defaults. Reset affects only the selected palette. Text
contrast is calculated from the chosen colors. The founder approved these defaults for all four sites. Production pages consume
the matching packaged tokens and SVGs; Regents and Techtree home backgrounds stay intact.

Expandable details remain in the document. `/showcase/catalog` exposes component
attributes and slots, installed Ash domain/resource/action metadata, and exported
shared and Regents-owned utility APIs. It never reads resource records. AshPhoenix
is not installed in this application; the working form uses Phoenix and an actual
Ash action with an in-memory data layer.

## Utility effects

- Wallet fixture: a separate local provider demonstrates connect/disconnect,
  overlapping presses, confirmation, rejection and revert. It never enters the
  real wallet store or sends a network request.
- Privy controls: the explicitly labeled main-page buttons use the existing real
  bridge and local session endpoints. They require a configured app and allowed
  origin. The automated checks never invoke them.
- Privy verification: signs an ephemeral fixture token and calls `RegentPrivy`
  for valid, expired and incorrect-audience outcomes. No fixture token enters an
  authentication endpoint; no key or token is displayed or retained.
- Address checksums, token formatting and ERC20 calldata call existing functions.
  Encoded calldata is never submitted.
- Postgres: a fixed read-only diagnostic accepts only the prepared loopback
  worktree test database naming convention. It refuses other database settings.
- Comments and linked identities are synthetic LiveView state, lost on reload.
  Comments use the real Markdown validator and renderer. Headings, lists, quotes,
  tables, emphasis, strikethrough, code and HTTP(S) links are supported. Use `$...$`
  for inline LaTeX and `$$...$$` for display LaTeX. Code stays literal. Raw HTML and
  embedded images remain disallowed. KaTeX is loaded only when math is present;
  malformed expressions retain their readable source, and unsafe HTML/link commands
  are disabled. See [KaTeX options](https://katex.org/docs/options.html).

## Run in an isolated worktree

Use Control's `worktree-prepare` and `worktree-run` for the ticket so Mix uses the
pinned shared dependencies, unique local database and port. Install locked Mix and
npm dependencies, then run `mix assets.build` through `worktree-run`.

A prepared test database can be created with `mix ecto.create`. This showcase does
not require replaying the app's migration history. Existing ExUnit setup creates
its disposable local account fixtures. Do not run production migrations to support
this gallery.

Run the disposable test server through `worktree-run`:

```sh
env ASH_PLATFORM_BROWSER_TEST=1 mix run --no-halt -e 'Ecto.Adapters.SQL.Sandbox.mode(AshPlatform.Repo, :auto)'
```

That command belongs only in the isolated test context. Use its printed URL and
append `/showcase`. The current candidate's prepared context is ticket
`regent-qht.9`, port `51454`.

## Focused verification

Through the prepared worktree context:

```sh
mix test test/ash_platform_web/showcase/showcase_test.exs
npm run typecheck
npm test -- assets/test/auth_lazy.test.ts assets/test/connected_wallet.test.ts assets/test/hook_composition.test.ts
```

Against the already-running disposable server:

```sh
PORT=51454 npx playwright test --config playwright.showcase.config.ts
```

The dedicated browser configuration avoids the product suite's seeding and global
teardown. Browser tests block external origins and cover eight palettes, persistent
edits, keyboard focus, reduced motion, mobile overflow, Ash validation, utility
results, repeat wallet presses and expandable fixtures. Failures retain screenshots
and traces in `test-results/`.
