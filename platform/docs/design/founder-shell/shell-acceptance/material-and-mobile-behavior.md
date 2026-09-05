# Shell material and mobile behavior evidence

Baseline: `2d07d7b78194cfb0f6bf5dd5d2bc100f246bdc48`

This slice changes presentation and accessibility behavior only. It does not change route,
account, authentication, product, or LiveView authority.

| Before | After | Why |
| --- | --- | --- |
| Plain system-color shell scaffold | Shared high-opacity neutral gradient material on the header, contextual navigation, and primary stage | Gives the four products one restrained structural system while keeping product identity in the accent and future background artwork. |
| Mobile menu only toggled visibility | Opening focuses the first available destination, contains Tab and Shift+Tab, makes destination content inert, and exposes a dismissible scrim | Keeps temporary navigation usable without letting focus or pointer input escape behind it. |
| Escape was the only explicit focus-return path | Escape, scrim dismissal, menu-toggle close, and destination selection close the menu and return focus to its trigger | Prevents focus from being lost when the temporary navigation disappears. |
| Native app selector could stay open through a route change | Selecting an application and every subsequent route patch close the selector | Prevents stale disclosure state without replacing native details behavior. |
| Map/List client restoration wrote button-style state onto links | Exactly one selected presentation link receives `aria-current="true"`; unselected links omit it | Uses link semantics for destination presentation while preserving local route state. |
| Theme variables depended on JavaScript adding `data-theme` | Canonical neutral defaults and system-preference CSS keep the shell readable before JavaScript runs | Avoids an unstyled first paint and preserves the existing theme owner. |

## Verification

- `npm test -- --run assets/test/shell_accessibility.test.ts`: 8 tests passed.
- `npm test`: 7 files and 56 tests passed.
- `npm run typecheck`: passed.
- Direct esbuild compilation of `app.ts` and `privy_bridge.tsx`: passed; emitted CSS parsed successfully.
- `git diff --check`: passed.
- Focused CSS audit found no fabricated background asset URL, structural radius above 4px,
  or `transition: all` declaration.

Chief unrestricted exact-byte verification passed: compile without warnings, format,
`ash.codegen`, backend 125/0, TypeScript, frontend 56/0, assets build, initial budgets 2/2,
and diff-check. The initial app bundle is 390.3 KB raw. The deferred Privy bundle is 12.1 MB
raw and remains a known final-acceptance performance choice. Guarded browser, screenshot,
and reset evidence remains pending an immutable commit.
