# Homepage parity evidence

## Target

The public slash route follows the old Platform landing page outside the hero:
sticky header, runs-on strip, four-part Formation story, two principle cards,
Techtree grid, stack cards, Autolaunch band and market grid, Techtree research
band, three-card action row, two story cards, closing band, and four-column
footer. Typography, spacing, grid breakpoints, borders, and dark-stock section
rhythm use the old page as the visual reference.

The hero is intentionally different. It uses the founder-supplied cutting-mat
SVG behind four high-opacity, square material cards for Formation,
Autolaunch, Techtree, and Regents Labs. The complete hero is readable before
JavaScript. Anime.js enhances all four cards together after first paint and
cleans up on teardown; reduced-motion users retain the static render.

Visual parity does not import old behavior. Public chat, rooms, fabricated
testimonials and market figures, unadmitted routes, stale CLI commands, and
paid-payload claims are absent. Honest founder-approved content preserves the
reference page's visual density.

## Canonical assets

- `priv/static/images/home/hero-bg-dark.svg` retains SHA-256
  `5d04f865bb1b4611e6c9cf9d44e2377107202782b27064e864fd2c4509e0da8c`.
- Geist Pixel Circle, Geist Pixel Square, Geist UI Sans, and Geist Mono are
  copied byte-for-byte from the canonical Regent design assets into this
  independent application.
- Anime.js is locked at the current approved `4.5.0` release.

## Matched captures

The comparison set lives under `homepage-comparison/`:

- full desktop and 390px mobile captures for the live old Platform and local
  Ash page;
- fixed 1440×1000 Formation crops;
- fixed 1440×1000 closing/footer crops;
- grayscale, edge, absolute-difference, pixelmatch, and side-by-side outputs
  under `homepage-comparison/diff/`.

The old page's smooth scrolling and reveal classes were neutralized only for
capture so the screenshots show the real content instead of offscreen hidden
states.

The Techtree band retains the reference page's 3×3 card rhythm. Its first five
cards are the five founder-approved tree roots; the remaining four describe
participation surfaces rather than inventing more roots. The BBH Training
Corpus stays inside the BixBench Capsule Lab card. Map/List, record comments,
and credentialless local Marimo execution are labeled as available. Agent
publishing remains visibly planned until its owning transport contract lands.

The Formation pair is the strongest non-hero parity sample:

- fixed-pair distance: `0.09890`;
- candidate/reference edge-energy ratio: `0.93582`;
- material edge-difference ratio: `0.12349`;
- average luminance delta: `-4.97715`.

Those measurements are diagnostic, not an acceptance score. Visual review
shows the same two-column geometry, type hierarchy, divider positions, action
placement, and first figure layout. Copy and the static Formation artwork
differ intentionally.

The closing/footer pair is farther apart (`0.31843`) because the old reference
contains a public-chat control, social destinations, and retired links that
the founder explicitly excluded. The retained structure still matches: wide
closing artwork, centered call to action, brand block, four link columns, and
legal row.

## Executable proof

- homepage LiveView tests pin the old section order, exact four destinations,
  five founder tree roots, mat asset, no chat, no unadmitted docs/CLI links,
  no application shell, and the HTML budget;
- HomeHero tests pin same-time four-card entry, 400 ms voxel delight,
  reduced-motion behavior, pending-frame cancellation, active-animation
  cancellation, and clean teardown;
- browser tests pin the exact mat path, four card routes, section order, real
  Geist Pixel font load, no chat, mobile single-column order, and zero
  horizontal overflow;
- full frontend, Phoenix, budget, and browser suites cover the shared shell,
  Privy session boundary, Stake, and Redeem after Design integration.
