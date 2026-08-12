# Homepage marketing-index evidence

Status: implementation evidence only. Browser acceptance remains with the Platform motion/integration lane.

## Design result

- Uses Prime Intellect only as a structural reference for a strong indexed header and thesis-led hero. No Prime assets, branding, claims, partner marks, announcements, or metrics are present.
- Keeps the exact founder-provided cutting-mat artwork as the hero background.
- Gives the header four contiguous marketing links: `#techtree`, `#autolaunch`, `#regent`, and `#home-closing`.
- Keeps three hero cards as product gateways to the `#techtree`, `#autolaunch`, and `#regent` sections; while the launch gate holds the product routes, no card leaves the homepage.
- Presents three numbered product chapters in that same order, with the evidence, revenue, Nous, and summary beats between and after them. Each chapter carries its own supporting proof; no chapter offers an app-entry action while the routes are held.
- Uses square Regent geometry, the canonical crown, Regent type, one product accent per chapter, and plain inner proof surfaces.

## Verification performed

- `mix test test/ash_platform_web/home_live_test.exs`: 4 tests, 0 failures.
- `mix compile --warnings-as-errors`: passed.
- `mix format --check-formatted` for the owned Elixir and test files: passed.
- `git diff --check` for the three implementation files: passed.
- `shasum -a 256 priv/static/images/home/hero-bg-dark.svg`: `5d04f865bb1b4611e6c9cf9d44e2377107202782b27064e864fd2c4509e0da8c`.
- Chromium layout probe at 320, 390, and 1440 CSS pixels: page scroll width equalled viewport width; every tab, header action, hero action, and hero card was at least 44px tall; cards were 2×2 at 320/390 and four columns at 1440.
- A 320px geometry probe compared each voxel cluster with its card's OPEN label, index, title, tagline, and arrow. All 20 comparisons were non-intersecting. Voxels occupy the unused top-center zone rather than the text baseline.

## Browser acceptance status

Final captures use the exact readiness contract: `#public-home[data-hero-enhanced="true"][data-hero-motion="settled"]`, `document.fonts.ready`, and decoding every incomplete image. They cover desktop dark and light, 390×844 dark, 768×1024 light, and effective 200% dark without horizontal overflow. The public marketing surface deliberately remains dark in both theme modes so the founder artwork and product colors stay stable; this follows the STYLE direction for the dark-stock marketing surface. The two desktop captures are byte-identical with SHA-256 `b6c34f22f097dd52201b3bd5d4966a818ff5fa92c190e7a676e8a430e17aa058`.

## Independent convergence

Chief's unrestricted convergence run on 2026-07-11 passed: HomeLive 4/4, full Mix 159/0, frontend 59/59, budgets 2/2, and Playwright 21/21. Warnings-as-errors compilation, formatting, Ash code generation checks, the asset build, and the repository diff check also passed. The sole browser-suite update replaced a stale expectation for the former eleven-section page with the canonical four marketing chapters.

## Visual critique

- The thesis leads clearly, while the mat remains legible as a precision-work backdrop rather than competing with the copy.
- The indexed header reads as one contiguous product map. At narrow widths it becomes a horizontally scrollable rail without widening the page.
- The four OPEN cards form a compact desktop ribbon and a balanced 2×2 composition at 320 and 390 pixels. Their voxel clusters stay clear of every label and keep product identity restrained.
- The body copy uses Geist UI Sans. The captured implementation still gives CTA actions the pixel face; independent review identified this as a remaining typography mismatch with the founder correction.
- The four chapters keep proof inside its owning product. Three-card and four-card proof groups balance through an adaptive grid.
- Independent screenshot review found that the horizontally scrolling product-tab rail does not make the off-canvas fourth tab sufficiently discoverable at 390px and effective 200%. The convergence suites pass, but these two presentation findings remain recorded rather than silently described as accepted.
