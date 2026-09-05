# Regents.sh palette rebrand — light and dark tokens

Ticket regent-gu2.12. Base `07b0209`. The founder's Regents light and dark palettes replace
every colour on the marketing page, the shell, Stake, Redeem and Settings. The design does
not change: mono uppercase labels, hairlines, the block primary action and the crown/field
scene all stay exactly as they are. Only the colours behind them move.

## Source of truth

`/Users/sean/Documents/regent/repos/design-system/regents-sites-palettes/regents-light.png`
and `regents-dark.png`, read in place. The eight swatches printed on each sheet agree with
the ticket to the letter, so no value below is invented:

| role | light | dark |
| --- | --- | --- |
| Primary | `#161616` | `#161616` |
| Primary Soft / Deep | `#3A3A3A` | `#0E0E0E` |
| Accent Orange | `#FF5B19` | `#FF5B19` |
| Accent Blue | `#AECACD` | `#AECACD` |
| Background | `#F6F4EA` | `#0B0B0B` |
| Surface | `#FFFFFF` | `#141414` |
| Text | `#161616` | `#E5E3D2` |
| Border | `#DAD8C7` | `#2A2A2A` |

The three hero cards take their product's Primary: techtree `#AECACD`, autolaunch
`#FF5B19`, patchbay `#B9B7A6` — all read off the matching product sheets.

Sampling the raster instead of the printed labels returns values a few 8-bit steps off
(`#1A1A19` for Primary, `#ABA897` for patchbay Primary), because the sheets carry a soft
gradient and were saved lossily. The printed labels are the palette; the pixels are a
picture of it. Every value here is a label.

## Where a colour is allowed to live

One token layer, `assets/css/tokens/root.css`, holds the eight swatches per theme. Every
other file reads a token. The marketing page keeps its own `--rl-*` set because `/` is
pinned dark whatever cookie the visitor carries, so it cannot use `light-dark()`; its values
are the dark palette, stated once at the top of `home.css`.

`assets/css/tokens/material.css` is **not** touched. Its aliases are read only by
`autolaunch.css`, `techtree.css`, `formation.css`, `regent_ops.css` and
`regent_profile.css` — every one of them a surface this ticket must not restyle. Repointing
them at the Regents palette would recolour Autolaunch and Techtree, which is out of scope
and forbidden.

`--shell-background-guide` in `shell.css` is also left alone. The watermark mat follows the
brand the server selected rather than the theme, and every brand's accent already resolves
to a palette hex: Powder Blue `#AECACD` for platform and Autolaunch, Tangerine `#FF5B19`
for Formation, Charcoal `#161616` for Techtree. Pinning it to an Ash token would break that
and change two out-of-scope applications.

## Token map

`old` is the value this change replaces, resolved to sRGB. `new` is what this change writes.
Every new value is a palette swatch or a `color-mix` of exactly two of them.

### Shell, Stake, Redeem, Settings — `assets/css/tokens/root.css`

| token | old light | new light | old dark | new dark |
| --- | --- | --- | --- | --- |
| `--ash-ground` | `oklch(97% 0 0)` `#F5F5F5` | **Background** `#F6F4EA` | `oklch(14.5% 0 0)` `#0A0A0A` | **Background** `#0B0B0B` |
| `--ash-panel` | `oklch(100% 0 0)` `#FFFFFF` | **Surface** `#FFFFFF` | `oklch(18% 0 0)` `#131313` | **Surface** `#141414` |
| `--ash-panel-strong` | `oklch(94% 0 0)` `#EDEDED` | `mix(Border 55%, Surface)` `#EBE9E0` | `oklch(21% 0 0)` `#1C1C1C` | `mix(Border 50%, Surface)` `#1F1F1F` |
| `--ash-ink` | `oklch(14.5% 0 0)` `#0A0A0A` | **Text** `#161616` | `oklch(97% 0 0)` `#F5F5F5` | **Text** `#E5E3D2` |
| `--ash-muted` | ink at 65% | unchanged formula, new ink | ink at 65% | unchanged formula, new ink |
| `--ash-line` | ink at 16% | **Border** `#DAD8C7` | ink at 16% | **Border** `#2A2A2A` |
| `--ash-line-strong` | ink at 28% (1.8:1) | `mix(Text 40%, Border)` `#84837A` | ink at 28% (1.8:1) | `mix(Text 40%, Border)` `#6E6E68` |
| `--ash-accent` | `oklch(50% 0.11 250)` | `mix(Accent Blue 50%, Primary)` `#5C696A` | `oklch(74% 0.11 250)` | **Accent Blue** `#AECACD` |
| `--ash-accent-warm` | *new* | `mix(Accent Orange 68%, Primary)` `#AE4723` | *new* | **Accent Orange** `#FF5B19` |
| `--ash-art` | `oklch(21% 0 0)` | **Primary** `#161616` | same | same |
| `--ash-art-ink` | *new* (was the keyword `white`) | **Surface (light)** `#FFFFFF` | same | same |
| `--ash-scrim` | *new* (was `oklch(black 72%)` at two sites) | `mix(Primary 72%, transparent)` | same | same |
| `--ash-regent` | `oklch(50% 0.11 91)` / `oklch(82% 0.11 91)` | **deleted** — the sites read `--ash-accent-warm` | | |
| `--ash-green` | `oklch(78% 0.17 155)` | **deleted** — the one site reads `--ash-accent-warm` | | |

The palette carries two accents, so the shell reads them as two: Accent Blue is what the
page points at (focus rings, links, the revenue share), Accent Orange is what carries
value or risk (the REGENT figures, compounding, the disconnect row, an error notice).
`--ash-regent` and `--ash-green` named colours the palette no longer has, and each had a
single meaning already covered by one of the two accents, so both are deleted rather than
re-pointed.

`--color-error` (RegentUI, `#FF9B8F`) is the last colour on the shell that is not in the
palette. It is replaced by `--ash-accent-warm` at all three sites. No RegentUI token needs
to change.

Light accents are darkened against Primary because the raw swatches fail on a pale ground:
Accent Blue reads 1.3:1 and Accent Orange 3.1:1 on Surface. The mixes above are the
lightest ones that clear 4.5:1 on all three light surfaces (Background, Surface and the
deepest panel). Dark takes both swatches raw — they clear 5.3:1 and 9.5:1 there.

`--ash-line-strong` is the only weight that changes. It draws the edge of a control — text
inputs, popovers, the avatar, pills, buttons — and at 28% ink it reads 1.8:1, under the
3:1 that a control boundary needs. At 40% of Text mixed into Border it reads 3.1–3.8:1 on
every surface it is drawn on. `--ash-line` stays the quiet structural hairline and takes
the palette's own Border swatch.

### Marketing page — `assets/css/pages/home.css`

`/` is pinned dark, so these are the dark palette stated literally.

| token | old | new |
| --- | --- | --- |
| `--rl-bg` | `oklch(14.5% 0 0)` `#0A0A0A` | **Background** `#0B0B0B` |
| `--rl-panel` | `oklch(18% 0 0)` `#131313` | **Surface** `#141414` |
| `--rl-ink` | `oklch(97% 0 0)` `#F5F5F5` | **Text** `#E5E3D2` |
| `--rl-line` | ink at 16% | **Border** `#2A2A2A` |
| `--rl-line-strong` | ink at 28% | `mix(Text 40%, Border)` `#6E6E68` |
| `--rl-techtree` | `oklch(72% 0.11 250)` | **Accent Blue** `#AECACD` |
| `--rl-autolaunch` | `oklch(78% 0.17 155)` | **Accent Orange** `#FF5B19` |
| `--rl-patchbay` | `oklch(72% 0.18 300)` | **patchbay Primary** `#B9B7A6` |
| `--rl-nous` | `oklch(68% 0.16 45)` | **Accent Blue** `#AECACD` |
| `--rl-chapter-default` | `oklch(82% 0.11 91)` | **Accent Orange** `#FF5B19` |

Blue proves, orange earns. Techtree's own colour is the palette's Accent Blue, so the
chapter that verifies work and the Nous chapter that runs it share it; Autolaunch and the
Revenue chapter share Accent Orange, the palette's one saturated colour and the only one
that reads as money on the page. Patchbay keeps its own warm grey. Revenue takes the
Orange rather than the Blue because the Blue is already the whole proving half of the loop,
and because Orange clears 6.3:1 on the home ground, well past what the state label at
0.67rem needs.

Neither `--rl-nous` nor `--rl-chapter-default` paints anything today: the Nous and Revenue
chapters carry no number and no proof grid, which are the only two elements that take a
chapter accent. Both tokens are still read — by `.rl-chapter` and `.rl-chapter--nous` — so
neither is dead, and both are stated from the palette so the day a proof lands there it is
already the right colour.

### The focus ring — `home.css`

`--rl-accent` is deleted. It named one thing, the marketing page's focus ring, and under
this palette it can no longer be an accent: both of the palette's accents belong to a
product here, Accent Blue to techtree and the Nous chapter, Accent Orange to autolaunch and
Revenue. A card being read wears its product's colour on its words and its marker edge, so
a ring drawn in that colour disappears into the card exactly where a reader most needs it.

The ring is drawn in Text instead — `#E5E3D2`, the one colour the page wears whichever card
is being read, and a colour no product owns. It is measured against the surface it is
actually drawn on: 15.2:1 on the hero at rest, 13.9:1 on the techtree ground, 14.3:1 on
autolaunch's, 14.0:1 on patchbay's and 14.4:1 on the card panel itself. And it can never be
the same colour as the dress, which is the defect the review caught — cream is not any
product's colour, and the browser test now checks both halves: that the card really is
wearing techtree's blue while its own control is focused, and that the ring on it is not.
The one control already carrying the ink block, the strong action, keeps its existing dark
ring against its own cream fill.

This is the one visible decision in the rebrand that is not a straight substitution, and it
is forced: there is no palette colour that is both an accent and not a product's.

### Hero hover — `home.css` and `assets/js/home_field/palette.ts`

At rest the hero stays monochrome exactly as the founder approved it today: a neutral grid
on the Background, a white beam, no product colour anywhere. Pointing at or focusing a card
is the only thing that brings colour in.

| product | card colour and laser | hero ground while pointed at |
| --- | --- | --- |
| techtree | `#AECACD` | `mix(#AECACD 8%, Background)` `#151717` |
| autolaunch | `#FF5B19` | `mix(#FF5B19 8%, Background)` `#1B120F` |
| patchbay | `#B9B7A6` | `mix(#B9B7A6 8%, Background)` `#161615` |

The field's squares move from the Techtree cream `#F4EEE4` to the palette's own Text
`#E5E3D2`. At the field's strongest cell that is a four-step change on a near-black ground,
so the grid keeps the weight the founder signed off.

Both canvases have to be handed the same picture in the two forms their pipelines expect.
The page canvas writes straight to the screen and takes the displayed values. The crown
composes in high dynamic range and finishes with one ACES curve and one sRGB encode, so it
takes the values that come out of that pass as the displayed ones:

* every ground is solved exactly — `encode(aces(composed)) = displayed` per channel, so the
  crown clears to the same colour the page canvas paints and both match `--rl-bg`;
* the square is solved so both canvases present the same colour at a lit amount of `0.118`,
  which is the operating point the shipped pair is already matched at. Keeping that point
  keeps the grid's weight identical rather than quietly re-fitting it.

A laser is the product colour in linear light, scaled so its brightest channel is as bright
as white — scaling, not clamping, so a colour the screen cannot reach loses brightness
rather than hue. That is the rule already in the tests; only its input changes, from an
oklch triple to the palette hex.

### Redeem's two remaining literals

| site | old | new |
| --- | --- | --- |
| `--redeem-return-edge` | six hexes taken off the Animata artwork | a sweep of `--ash-accent-warm`, `--ash-ink`, `--ash-accent` |
| collection art scrim | `rgb(0 0 0 / 55%)` from 20% down | `--ash-art` at 48% grading to 66% |
| collection monogram | the keyword `white` | `var(--ash-art-ink)` |
| result dialog backdrop | `color-mix(in oklch, black 72%, transparent)` | `var(--ash-scrim)` |

The scrim is the one weight this change moves for a reason other than the palette. The
numeral is set in Surface white over photography that reaches a blown highlight, and the
old gradient started at nothing 20% down, so the numeral measured 1.4:1 against the
brightest pixel behind it. Carrying the artwork under the numeral at 48% of Primary,
grading to 66% under the card's copy, holds it at 4.5:1 in light and 4.5:1 in dark while
leaving the photograph readable.

### Settings' connection buttons

The Connect and Disconnect buttons in the verified-connections rows carry no class of their
own, so they fell through to `app.css`, which paints a bare button with RegentUI's
`--color-surface-elevated`. That token is `#2A2A27` in both themes: a raised charcoal chip
that is not in the palette, does not turn over with the theme, and in the light theme sits
on a cream page looking like something switched off. They are now drawn as what they are —
the row's primary action, in the same ink block Stake and Redeem use — so they read as one
family across the three pages and flip with the theme. `app.css` itself is left exactly as
it is: its fallbacks are a contract the branded products still rely on, and a contract test
asserts them.

## Order of work

1. This plan.
2. `tokens/root.css` — the palette, both themes.
3. `pages/home.css` — `--rl-*` and the hero's three hover pairs.
4. `pages/settings.css`, `components/shell.css`, `pages/stake.css`, `pages/redeem.css` —
   the sites that named a deleted token or a literal.
5. `home_field/palette.ts` — grounds, squares and lasers re-solved.
6. Contrast measured on the running page in both themes, with Playwright reading computed
   colours.
7. `assets/test/home_palette.test.ts` updated to the new derivation; full gate run.
8. Screenshots of every page at 1280 and 375 in both themes, plus the hero with each
   product pointed at.

## Contrast, measured

Nothing here is estimated from the token map. Every figure is read off the running pages in
both themes, at 1280 and 375 wide, with Playwright reading computed colours and painted
pixels: 410 pieces of text and 78 control edges across the four pages.

Each piece of text is measured twice and the reading that is actually true wins. The first
is the composited stack: the element's own computed colour, alpha-composited over every
painted ancestor down to the page. The second is a pixel walk — the text is hidden and the
backdrop under each fully visible line box is sampled, the element's ink is composited over
each sampled pixel, and the worst pixel is kept. The walk is the ruling measurement wherever
it reached the element, because it is the only one that sees photography, gradients and
canvases; 380 of the 410 pieces were reachable. The other 30 all sit on a flat panel, where
the composited stack is exact by construction, and the lowest of them is 5.44:1.

A control's boundary is measured the way it is drawn. A solid block — the primary actions on
Stake and Redeem, the connection buttons on Settings — is measured as the block against the
page, because its border is its own fill and comparing the two says nothing. An outlined
control is measured against the better of the two sides its edge separates.

Bars: 4.5:1 for body text, 3:1 for large text (18.66px bold or 24px) and for control edges.
The worst case on each page follows, with what set it.

| view | body text, 4.5:1 | large text, 3:1 | control edge, 3:1 |
| --- | --- | --- | --- |
| light / | **4.65** p `Utilize your Hermes ag` | **6.34** p.rl-chapter-index `02` | **3.23** button.rl-action |
| light / at 375 | **4.65** p.rl-mode-caption `From a real workflow t` | **8.71** h2 `Prove what makes an ag` | **3.23** button.rl-action |
| light /stake | **5.12** a.stake-contract-link `View verified staking` | **4.63** span `1,250.50 USDC` | **18.10** button.stake-primary |
| light /stake at 375 | **4.63** span `1,250.50 USDC` | **18.10** h1 `Put REGENT to work.` | **18.10** button.stake-primary |
| light /redeem | **4.69** a `View collection on Ope` | **4.63** span `I` | **3.81** span.redeem-pill |
| light /redeem at 375 | **4.69** a `View collection on Ope` | **6.71** span `I` | **3.81** span.redeem-pill |
| light /settings | **5.42** span.shell-chevron `⌄` | **16.28** h2 `Verified connections` | **16.41** button |
| light /settings at 375 | **5.42** span `Not connected` | **16.10** h2 `Verified connections` | **3.81** div.account-menu__content |
| dark / | **4.65** p `Utilize your Hermes ag` | **6.34** p.rl-chapter-index `02` | **3.23** button.rl-action |
| dark / at 375 | **4.65** p.rl-mode-caption `From a real workflow t` | **8.71** h2 `Prove what makes an ag` | **3.23** button.rl-action |
| dark /stake | **5.93** span `01` | **5.31** span `1,250.50 USDC` | **14.26** button.stake-primary |
| dark /stake at 375 | **5.31** span `1,250.50 USDC` | **14.26** h1 `Put REGENT to work.` | **14.26** button.stake-primary |
| dark /redeem | **6.16** p `Redemption source` | **4.46** span `I` | **3.59** span.redeem-pill |
| dark /redeem at 375 | **6.16** p `Redemption source` | **6.61** span `I` | **3.59** span.redeem-pill |
| dark /settings | **5.93** span `Disconnect` | **14.94** h2 `Verified connections` | **15.23** button |
| dark /settings at 375 | **5.93** span `Disconnect` | **14.52** h2 `Verified connections` | **3.84** div.account-menu__content |

No view fails. The tightest body text on the site is the marketing page's chapter copy at
4.65:1 and Redeem's OpenSea link at 4.69:1; the tightest control edge is the marketing
page's outlined action at 3.23:1 and Redeem's status pill at 3.59:1.

Two of these decided a colour rather than merely reporting one. `--ash-line-strong` at the
old 28 per cent of ink measured 1.8:1 and had to be re-weighted to clear a control edge.
Redeem's collection numeral measured 1.4:1 over the artwork's blown highlight and the art
scrim had to be re-graded under it; it now reads 4.63:1 in light and 4.46:1 in dark.

The two hero canvases were checked the same way, by reading back what they present rather
than what they were handed. The page canvas and the crown clear to the same colour as the
CSS ground in all four states, within half of an 8-bit step: `#0B0B0B` at rest, `#1B120F`
under autolaunch, `#151717` under techtree, `#161615` under patchbay.

## What does not change

No copy. No markup. No fallbacks, no compatibility branches, no dual-shape support: the old
values are gone rather than kept beside the new ones. No Autolaunch file, no `techtree.css`,
no design-system file, no Beads or control file.
