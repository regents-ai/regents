# Homepage U2 acceptance evidence

This directory records the isolated U2 homepage candidate built from Ash Platform commit
`747c953e83343107ce6100c65252514fa52cac95`.

## Included result

- The public page is an indexed four-product marketing surface with one mat hero and exactly
  four chapters: Formation, Autolaunch, Techtree, and Regents Labs.
- Header tabs stay on the page through `#formation`, `#autolaunch`, `#techtree`, and
  `#regents-labs`. The four `OPEN` cards enter `/formation`, `/autolaunch`, `/techtree`, and
  `/app` respectively.
- The exact founder-provided hero artwork is present at
  `priv/static/images/home/hero-bg-dark.svg`; its SHA-256 is
  `5d04f865bb1b4611e6c9cf9d44e2377107202782b27064e864fd2c4509e0da8c`.
- The page uses the canonical dark crown and the minimal Geist UI Sans, Pixel Circle, and Pixel
  Square fonts. It intentionally remains dark under System, Light, and Dark preferences.
- Regents Labs, Stake, and Redeem are labelled as previews; the page says their actions are not
  yet available rather than implying that a destination is live.
- White primary actions use a square 3px near-black inset keyboard-focus ring. The neutral token
  pair has approximately 18.15:1 non-text contrast, above the required 3:1 threshold.
- Content is visible before JavaScript runs. The optional Anime.js 4.5.0 introduction is finite,
  cancellable, and publishes deterministic `enhanced` and `settled` readiness states. Reduced
  motion settles without travel.

## Candidate-local verification

- `npm ci`: completed from the committed lockfile.
- `npm test`: 5 files, 28 tests, 0 failures.
- `npm test -- --run assets/test/home_hero.test.ts`: 1 file, 8 tests, 0 failures.
- `npm run typecheck`: passed.
- `git diff --check`: passed.
- Asset-reference, scope, and hash checks: passed.

## Unrestricted acceptance still required

This sandbox does not permit the local TCP sockets required by Elixir 1.19 Mix PubSub or the
controlled Phoenix browser server. It also cannot produce trustworthy browser captures without
that server. No historical screenshots are included or described as fresh evidence.

Run these commands from the immutable candidate commit in an unrestricted local environment:

```sh
npm ci
MIX_OS_CONCURRENCY_LOCK=0 mix deps.get
MIX_OS_CONCURRENCY_LOCK=0 HEX_OFFLINE=1 mix compile --warnings-as-errors
MIX_OS_CONCURRENCY_LOCK=0 HEX_OFFLINE=1 mix format --check-formatted
MIX_OS_CONCURRENCY_LOCK=0 HEX_OFFLINE=1 mix test test/ash_platform_web/home_live_test.exs
npm test -- --run assets/test/home_hero.test.ts
npm run typecheck
MIX_OS_CONCURRENCY_LOCK=0 HEX_OFFLINE=1 mix assets.build
npm run test:budgets
MIX_OS_CONCURRENCY_LOCK=0 HEX_OFFLINE=1 npx playwright test test/browser/homepage.spec.ts
git diff --check
```

The browser test waits for
`#public-home[data-hero-enhanced="true"][data-hero-motion="settled"]`, loaded fonts, and decoded
images. It then verifies no-JavaScript readability, reduced motion, keyboard focus, hover
contrast, no horizontal overflow, 2×2 mobile cards without text/voxel collision, 320, 390, 768,
desktop, effective 200%, and pixel-identical pinned-dark Light/Dark captures. It writes the fresh
PNG evidence into this directory.
