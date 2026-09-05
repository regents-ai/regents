# Home hero v3

Ticket regent-gu2.15. Base `cc03540`. Five founder items, all on his veto list, all visible
on the marketing page.

## What changes

### 1. Everything down to the stakers band fits the first screen

The hero keeps its two columns for the words and the crown, and gains a third full-width
row for the products:

| row | contents | columns |
| --- | --- | --- |
| 1 | heading, tagline | left only — the crown keeps the right |
| 2 | "Agentic Products" and the three cards, three across | full width |
| 3 | the stakers band | full width |

The crown stays exactly what it is today: a canvas layer behind the whole hero, sized and
positioned as it already is, with the same scrim over it. Nothing about the two canvases,
the palettes, or the hooks moves.

The home hero is then held to exactly one screenful — the window height less the header —
and the first row absorbs whatever is left over, so the words sit against the products and
the products against the stakers band however tall the window is. The header's height is a
bar plus the line under it, and that measurement is written once so the hero and the crown
cannot drift a pixel past the fold. On a window shorter than 44rem the space between the
blocks closes up as well, so a laptop with a tall browser toolbar still shows everything
down to the stakers band without scrolling; no word on the screen gets smaller. Below 60rem
the hero already collapses to one column, and that stack keeps the founder's phone order —
heading, tagline, crown, cards, stakers band — with the products label travelling with the
cards it introduces, and drops the one-screen limit so nothing is squeezed on a phone.

### 2. The heading block reads as the founder wrote it

`Regents Labs` as the headline, then the tagline `A no-equity company with onchain revenue
split`, which the stylesheet shows in capitals, then a blank line's gap, then
`Agentic Products` as the label that introduces the cards. The label names the product list
for a screen reader too, so the list drops its invented label and points at the visible one.

### 3. The stakers band becomes a container

The sentence keeps its wording. "Buy REGENT" and "Stake REGENT" move directly under it
instead of beside it, and the whole band takes the border and panel of a product card.

### 4. Patchbay replaces the Regent chapter

The header tabs become TECHTREE, AUTOLAUNCH, PATCHBAY, ABOUT. Chapter 03 becomes Patchbay:
a title, a description, three proof cards, and a link to the source. The chapter also takes
Patchbay's own colour, the purple its card already wears in the hero, instead of the yellow
the chapters fall back to. The Nous chapter below it is untouched, and the footer line now
names all three products.

The Regent chapter's two controls go with it — the Nous handoff link, the "Copy Instructions
to My Hermes" button, the status line it wrote into, the clipboard listener in the hero hook,
the instruction text, and the tests for all of it. The chapter row that held them was the
only user of a link-or-copy split in the chapter renderer, so that split goes too and the
chapter's action row becomes plain links.

Chapter copy is a draft from the Patchbay README, in plain English, and is flagged for the
founder in the hand-over. It claims no more than the README does: repairs are Patchbay's own
tools only, and all three proof cards are labelled "Working prototype", the same label
Techtree's proofs carry, rather than "Live".

The founder copy the Regent chapter took with it — its eyebrow, headline, body, the Nous
action and the Hermes instruction — is written down verbatim in `docs/copy-for-later-use.md`,
where every other line dropped from this page already lives.

Only Techtree's site is open to visitors, so the chapter links Patchbay's source and nothing
else: the "Visit patchbay.help" action is not there. The hero card keeps the disabled "Open
patchbay" button it already had. Both come back when the founder opens the site.

### 5. The field behind the page reads neutral

The grid behind the hero, its 60°/45°/30° labels and its diagonal are drawn in
`priv/static/images/home/hero-bg-dark.svg`, and every one of them was blue-violet. The picture
is repainted at the source rather than corrected on the page: every mark becomes the same grey
the crown draws its lasers in, and the dark slab it was painted on goes away entirely, along
with the small chips of that slab that were punched in behind the ruler numbers. What is left
is a grey line drawing on nothing, so it takes whatever the page behind it is painted and
reads the same in a light theme as in a dark one. Nothing on the page filters it afterwards.
The hover palettes are untouched, so pointing at a product still tints the ground and both
canvases together.

The file is still called `hero-bg-dark.svg`; the name no longer describes it, and renaming it
is left for whoever picks up the next pass.

## Tests

- The Elixir homepage test follows the copy, the tabs, the chapter list, the stakers
  container and the two remaining hero actions, and loses the Regent chapter's cases.
- The browser homepage spec measures the fold at 1280x640, 1280x720, 1440x900 and 1920x1080,
  checks that the tagline's capitals come from the stylesheet and not from the sentence, follows
  the cards to three across on the desktop and one column on a phone, reads the background
  picture's own pixels to hold it grey with nothing correcting it, and loses the clipboard and
  Nous-handoff cases.
- The founder-shell spec follows the new headline and the Patchbay anchor; nothing else in
  that file changes.
- The hero hook's unit tests lose the clipboard suite; the palette suite is unchanged.
