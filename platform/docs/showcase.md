# Local component workshop

Open `/showcase` on a development or test server using `localhost` or `127.0.0.1`.
The production configuration omits its routes. HTTP requests and connected
LiveView mounts both require a loopback peer and a loopback hostname; forwarded
headers do not grant access. Gallery styles and metadata use the same guard.

## Privy working reference

`/showcase/privy` uses the **real Regents account control and auth bridge**, not
the separate wallet fixture in the main gallery. It includes configuration
instructions, header Sign In/Disconnect, in-page connection controls, the selected
wallet, asynchronous Base balance hydration, and the shared protocol reading.
Controls are disabled with an explanation when configuration is missing or the
server uses a test verifier. No configuration values, tokens or provider objects
are displayed. The data panels request no transaction or extra signature.

The production header and this page both render
`AshPlatformWeb.Components.Shell.account_control/1`. The small
`assets/js/hooks/privy_showcase.ts` hook observes the existing wallet store; it
does not create a second `PrivyProvider`. The existing trusted session hook still
owns authentication. `PrivyShowcaseLive` owns only read-only data loading and drops
stale results on a wallet change. Source comments identify those boundaries.

For real testing, use the configured development server and a Privy-allowed
localhost origin. Supply `PRIVY_APP_ID`, `PRIVY_VERIFICATION_KEY`, and the desired
Base/ENS reader configuration to that process. Prepare the local PostgreSQL
database (`ash_platform_dev` by default), run `mix ash_platform.setup_local_auth`,
then `mix assets.build` and `mix phx.server`. Do not use browser-test configuration
as proof of real Privy sign-in. A detailed source map is also on the reference page.

`design-system/regent_ui` is already the shared Phoenix component library,
consumed as a path dependency rather than a Hex release. `regents/identity` and
`elixir-utils/privy` are shared identity/verification libraries. This reference
documents Regents' application-owned browser coordination; it does not yet turn
that coordination into a cross-product template or change the other sites.

The workshop renders the active components installed from `regent_ui` and
`AshPlatformWeb.Components`, plus both layouts. It identifies the two panel
component aliases. Three Autolaunch LiveComponents have static signed-out previews
inside scriptless sandboxed frames. The shell preview includes working navigation
and theme behavior but omits sign-in controls. These product compositions are
Regents-owned, rather than newly shared components.

Eight structural palette cards pair each site’s light/dark colors with a real
surface/text/primary preview, not SVG thumbnails. Defaults import the shared
package’s generated token JSON. Regents uses charcoal, Autolaunch tangerine,
Patchbay platinum, and Techtree powder blue. The selected card reflects live edits;
other cards retain their own stored palette identity.

The route composes actual `Regent.Structure` frames, rows, section bars, panels and
technical figures around the existing live components. Shared skins own cut
corners, square controls and the 24px select-chevron inset. Primary buttons reuse
the Regents Buy Regent diagonal shimmer: 1.15 seconds per sweep on hover/focus.
Capabilities cards use the same sweep at 3.45 seconds, exactly three times slower.
Reduced-motion users get a static card edge; forced colors retain system borders
without decorative gradients. Titles and subtitles use Geist Pixel Square at weight 400; body and
interface use Geist Sans. Code and technical identifiers use Geist Mono. Supporting bands/figures use shared semantic color roles.
The workshop applies canonical tokens locally so product-local legacy type tokens
do not override this collection. It does not change unrelated route styles.

Four editable colors—background, surface, text and primary—are stored separately
for each site/mode in the existing browser storage namespace. Reset affects only
the selected palette. Text contrast is calculated from the chosen colors; accent
panels and controls pair edited primary colors with contrast-selected ink.
Page SVG backgrounds are disabled: the hook no longer chooses a background image.
The retired shared background and product homepage background compatibility demos
remain mounted and catalogued behind a labeled disclosure, without page art.
Existing shell and sandboxed product previews remain independent compositions.

`Regent.Structure.capability_card/1` is the shared card, not workshop-specific HTML.
Supply `title`, `description`, optional `index`, `tone`, `image_src` and `image_alt`.
Use its `:media` slot for custom SVG/content instead of an image, and `:actions` for
application-owned links or buttons. The Capabilities section demonstrates both
illustration and image inputs. Its API also appears in `/showcase/catalog`.

The Shimmer color picker overrides `--rg-shimmer-color` for this workshop document,
including after a LiveView patch or theme change. “Use automatic color” restores
the component's local contrasting ink. This override does not change the four
palette colors and resets on reload. Consumers can set the same CSS custom property
on a primary button, capability card or ancestor; `--rg-shimmer-duration` controls
the base button duration and cards multiply it by three.

The Staking overview section previews `Regent.Structure.ratio_card/1`: a square,
corner-bracketed readout with paired percentages, a Tangerine-filled ratio meter,
striped remainder, scale and caller-supplied footer. Values are integer basis points;
the preview selector exercises a sample, zero, full and unavailable value. It reads
no staking contracts and changes no product state. `nil` means unavailable, not zero.
All figures and the displayed change are explicitly illustrative. This prepares the
component for a future `/stake` integration; that route remains unchanged by this work.

Expandable details remain in the document. `/showcase/catalog` exposes component
attributes and slots, installed Ash domain/resource/action metadata, and exported
shared and Regents-owned utility APIs. It never reads resource records. AshPhoenix
is not installed in this application; the working form uses Phoenix and an actual
Ash action with an in-memory data layer.

## Utility effects

- Wallet fixture: a separate local provider demonstrates connect/disconnect,
  overlapping presses, confirmation, rejection and revert. It never enters the
  real wallet store or sends a network request.
- Privy controls use the existing bridge and trusted session loader. A configured
  development server offers only the action matching its verified account state.
  The test verifier or missing configuration instead shows a disabled control and
  an adjacent explanation; the browser-fixture server is not real human sign-in.
  A real app, verification key and Privy-allowed origin are required for that canary.
- Create/add/reset items and chamber edits use the local Ash sample action. Copy
  writes the displayed ledger or utility result through the browser clipboard API.
  These examples never write product records. Comment validation failures remain
  visible beside the preserved draft rather than silently ignoring the submission.
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

Give the worktree its own `MIX_TEST_PARTITION`, a unique `PORT` and, when the shared
repositories are elsewhere, `REGENT_DEPS_ROOT`, so Mix uses the pinned shared
dependencies, a unique local database and port. Install locked Mix and npm
dependencies, then run `mix assets.build`.

A prepared test database can be created with `MIX_ENV=test mix ecto.create`. This
showcase does not require replaying the app's migration history. Existing ExUnit
setup creates its disposable local account fixtures. Do not run production
migrations to support this gallery.

Run the disposable test server in the test environment with that partition and port:

```sh
env MIX_ENV=test ASH_PLATFORM_BROWSER_TEST=1 mix run --no-halt -e 'Ecto.Adapters.SQL.Sandbox.mode(AshPlatform.Repo, :auto)'
```

That command belongs only in the isolated test context. Use its printed URL and
append `/showcase`.

## Focused verification

From the worktree, with the same partition:

```sh
mix test test/ash_platform_web/showcase/showcase_test.exs
npm run typecheck
npm test -- assets/test/auth_lazy.test.ts assets/test/connected_wallet.test.ts assets/test/hook_composition.test.ts
```

Against the already-running disposable server, naming its port:

```sh
PORT=<port> npx playwright test --config playwright.showcase.config.ts
```

The dedicated browser configuration avoids the product suite's seeding and global
teardown. Browser tests block external origins and cover eight palettes, persistent
edits, keyboard focus, reduced motion, mobile overflow, Ash validation, utility
results, repeat wallet presses and expandable fixtures. Failures retain screenshots
and traces in `test-results/`.
