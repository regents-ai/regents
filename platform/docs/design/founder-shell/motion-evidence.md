# Motion evidence

Regents moves the way Patchbay does (Patchbay `45a7c92`), with Anime.js 4.5.0. `RegentsWeb.Motion` names the version of each part; a live part of a page carries it in `data-variant`.

## Where each part is used

| Part | Version | Where | Code |
| --- | --- | --- | --- |
| Press | squish | Every button, `.rg-button`, `[role=button]` and menu summary, except the theme switch, which turns its own cube | `assets/js/motion.ts`, `hooks/motion/press.ts` |
| Drawer | spring | The phone menu (`#shell-sidebar`, `data-panel="drawer"`) and its shade (`data-backdrop`) | `motion.ts`, `hooks/motion/slides.ts` |
| Sheet | spring | Every `<dialog>` as it opens: supply info, stake and redeem receipts | `motion.ts`, `slides.ts` |
| Menu | pop | The account menu and the $REGENT menu (`data-panel="menu"`) | `motion.ts`, `slides.ts` |
| Toast | pop | The "copied" note in the $REGENT menu | `hooks/home_token_menu.ts`, `hooks/motion/moments.ts` |
| List | bounce | Owned NFTs on Redeem, names on Account (`MotionList`) | `moments.ts` |
| Count | roll | Staking benefits and wallet figures on Stake, the redemption summary (`MotionCount`, figures marked `data-count` by `TokenDisplay`) | `moments.ts` |
| Tabs | glide | The app's page as the sidebar moves between views (`ShellViews`, composed after `shellBehavior`) | `hooks/motion/reveals.ts` |
| Headline | rise | The `<h1>` of a page the server draws once, such as the blog | `motion.ts`, `reveals.ts` |
| Grid | cascade | The blog's card grid | `motion.ts`, `reveals.ts` |

Note peel and stamp thunk stay in `RegentsWeb.Motion` until the site has a place for them. The "nope" press is not used: no press on the site is answered with a refusal.

## Rules every part follows

- A press from the keyboard, and any reader who asked their system for less motion, gets the result at once with no movement.
- Only transform and opacity move. Each move ends at the element's normal look and removes the inline styles it wrote.
- Pages inside a live view never run the headline rise or card cascade; their parts move from their hooks, one Anime.js scope per hook, reverted on teardown.
- Motion never waits for, stops, disables or repeats a press. A wallet button reaches the wallet the moment it is pressed.
- A menu or dialog that the page redraws while open does not move again.

## Browser check (2026-09-26)

Each part was watched in a real browser with a recorder on inline style changes: it started from its first frame without a flash, reached its normal look and left no inline style. A keyboard press and reduced motion were checked for the press, drawer, menu, sheet, glide, toast and roll, and each opened or changed with no style writes. The blog's headline and cards were checked with three temporary posts that were removed afterwards.
