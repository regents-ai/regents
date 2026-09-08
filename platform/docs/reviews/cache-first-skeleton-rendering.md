# Cache-first rendering and component skeletons

Local, uncommitted follow-up to the staking reconnect and snapshot-refresh work. Not deployed.

## Root cause

`ShellLive.handle_authorized_params/3` painted the staking cache only after the socket connected. The disconnected HTTP render therefore emitted a loading banner even when the server already held a valid public snapshot. This was unnecessary hydration latency, not an Ash database-query bottleneck.

## Changes

- The first HTTP render of Stake and Overview reads the existing in-memory protocol snapshot. It does not start RPC or wallet requests. The cached projection explicitly merges a blank wallet shape, so it cannot carry another user's balances.
- Wallet reads remain fresh and asynchronous on the connected page. Staking Refresh Data still refreshes both the current wallet and shared protocol data; successful shared refreshes reach other subscribers through the existing cache/PubSub boundary. The previous one-minute background-refresh fix is retained.
- Added local `Components.Loading` primitives and stylesheet. Stake benefit cards, missing contract data, pending wallet data, Overview account/network data, Redeem data regions, public profile loading, shared fallback content, and metadata readiness use component-sized skeletons instead of page-level loading prose.
- Stake's connection instructions, revenue explanations, heading and page structure no longer disappear when protocol data is absent. Failed reads remain explicit errors with non-animated placeholders, not fabricated zero values.
- Skeletons pulse only with normal motion and outside forced-colors mode. They are noninteractive and hidden from assistive technology; the owning region declares its loading status.
- Redemption received component loading placeholders; its separate RPC read boundary was not redesigned into a new shared cache in this change.

## Verification

- Existing warm-cache regression now asserts protocol data is present in the initial HTTP response, before LiveView connects; it failed before the fix and passed afterward.
- Existing cold-cache/error regressions assert layout/skeletons are retained and usable transaction controls are not fabricated.
- Real browser with JavaScript disabled: cached contract data present, no loading banner. After clearing only the owned local test cache: component placeholders and static revenue content present, no horizontal overflow at desktop/mobile widths.
- Computed skeleton animation was `none` with reduced motion and `loading-pulse` with normal motion.
- `mix precommit`: 1,134 tests, zero failures, one external exclusion.
- TypeScript passed; 505 JavaScript tests and 2 asset-budget tests passed.
- Existing Stake, Redeem, authentication and Overview browser selections: 48 passed.
- Removed one unrelated numeric-formatting Credo finding introduced by concurrent showcase work (`10000` → `10_000`) without altering its behavior.

Evidence: `/tmp/regents-cache-ssr-red.log`, `/tmp/regents-skeleton-red.log`, `/tmp/regents-skeleton-precommit-final.log`, `/tmp/regents-skeleton-browser.log`. The temporary local IEx server used only test fixtures and was shut down. No production reads beyond the previously authorized public page inspection, signing, production mutation, commit or deployment was performed.
