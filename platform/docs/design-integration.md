# Regents structural design integration

Regents consumes the current `design-system/STYLE.md` and top-level contract in
`CONSUMERS.md`. Historical homepage/background exceptions are superseded.

## Ownership

- `assets/css/app.css` imports generated canonical tokens and primitives (including
  Structure and Ratio). Legacy `regent.css` is isolated in a lower cascade layer;
  product page styles own composition, not a replacement primitive skin.
- All Regents routes, including the nested Autolaunch area and homepage, retain
  `data-brand="platform"`. The existing `regent_theme` cookie selects light/dark.
  Root HTML and the existing `app.ts` synchronizer agree; `/` is no longer skipped.
  The shared footer exposes the existing theme control without introducing an
  authentication path or separate script.
- Marketing uses actual frame/row, section-bar, technical-figure and capability-card
  components. The application keeps its persistent shell/scroller and route owners,
  adding the ruled frame and canonical cut-panel skins. Native account-menu markup
  remains specialized to its avatar/profile/menu semantics.
- Buttons and form/disclosure wrappers use `Regent.Primitives`. Native fields keep
  their original IDs, names, values, validators and LiveView attributes. Primary
  HTML links have `rg-button__label`; secondary/quiet controls do not shimmer.
- Product background components/mounts are retired. Existing SVG assets and dormant
  background hook implementations remain available; the homepage uses existing crown
  art only inside a bounded technical figure. No page canvas is mounted.
- The approved local showcase remains intact.

## Staking ratio data

`StakeLive.supply_basis_points/1` reads `total_staked_raw` over
`regent_circulating_supply_raw` from the **existing** shared staking snapshot.
`Staking.RPCClient` creates these as decimal integer strings from same-block uint
readings. Both use REGENT's 18-decimal atomic unit. The denominator is existing
`Staking.Supply.circulating/4`: total minus treasury, Animata redeemer, staking reward
inventory and the existing 40-billion-REGENT Clanker-vault estimate. The estimate
is now explicitly disclosed beside the ratio; it is not a newly sourced reading.

Basis points are `div(staked * 10_000, circulating)` using arbitrary-precision
integers. No wei value is converted to Float. Missing/malformed/negative values,
zero denominator and staked greater than circulating yield `nil`, not a fabricated
zero or a clamped percentage. Valid zero staked produces 0%. The shared ratio card
owns label, complement, meter ARIA and fill from this one value. Total staked,
circulating and total supply facts remain present. Reward entitlement still uses
its existing separate denominator and action logic.

The existing cache and loading owners are unchanged: no snapshot means the
existing loading/error presentation; retained last-good snapshots keep their
values and timestamp during refresh/failure. The ratio does not start reads,
change cache lifetimes or disable transaction presses.

## Local build

Run from `platform/`, with explicit dependencies:

```sh
env REGENT_DEPS_ROOT=/Users/sean/Documents/regent/repos MIX_ENV=dev mix compile --warnings-as-errors
env REGENT_DEPS_ROOT=/Users/sean/Documents/regent/repos MIX_ENV=dev mix assets.build
env REGENT_DEPS_ROOT=/Users/sean/Documents/regent/repos MIX_ENV=dev npm run typecheck
```

The existing asset alias stages `regent_ui` and identity assets before esbuild.
Generated vendor assets and `/fonts/regent-ui/` are ignored, not hand-maintained.
The existing static allowlist already serves `fonts` and `images`.

The implementation route inventory, preimages/hashes, offline render diagnostics,
and verification limitations live in the workspace artifact directory
`artifacts/design-adoption/regents/`; the handoff report is
`artifacts/design-adoption/regents-implementation.md`. Offline component diagnostics
are not substitutes for authenticated, database-backed browser acceptance.
