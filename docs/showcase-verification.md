# Showcase candidate evidence

Ticket: `regent-qht.7` · base: `1bc9c1286312282da9bae17a89e621d0d848719b`.
Shared UI: `0e3804ff60c96064e0efc2638c5056f3bd6b8ee2`.
Elixir utilities: `39e388713aebe25d27581f0799f3d166a12429ea`.
Local database: `ash_platform_08a3d06209a7_test`.
Local URL: `http://127.0.0.1:52363/showcase`.

## Verified

- Nineteen focused and existing routing ExUnit tests pass, including seven
  showcase tests: non-loopback and forged-host HTTP rejection,
  connected mount rejection, component inventory, in-memory Ash validation,
  utility values and offline Privy signature/claim verification. Production route
  catalog, handoff and launch-gate checks retain their existing coverage; the
  compile-disabled local pipeline is checked separately.
- Four Chromium scenarios pass: all eight palette combinations and color edits,
  overlapping wallet fixture requests and failures, Ash/utility/database results,
  mobile layout, keyboard focus, reduced motion and isolated previews.
- Eighty existing authentication-loader, connected-wallet and hook-composition
  checks pass. TypeScript, formatting and warning-free compilation pass.
- Recompiled the router in a separate process with the production-default
  `local_showcase: false`: no `/showcase` routes. This was a route-exclusion proof,
  not a production deployment or a full production-build test.
- Read-only independent review found the two issues below; both were corrected.
  The final review found no remaining concrete access concern in its scope.
- Screenshots inspected at desktop 1440 px and mobile 390 px. Images are retained
  under the workspace's `artifacts/showcase/` directory.

## Design and interaction review

| Before | After | Why |
|---|---|---|
| Updating a nested fixture could close its open disclosure. | Client-owned disclosure state survives LiveView updates. | Keep the user's current work visible. |
| The shell preview could launch real sign-in. | Preview account controls are omitted; real Privy buttons have a separate, explicit section. | Make example effects clear. |
| Static wallet previews requested a nonexistent stylesheet. | Scriptless previews load the actual application stylesheet. | Show the real components accurately. |
| Four themes required separate product pages to compare. | One compact gallery switches site and mode, with four editable colors. | Make visual inspection quick. |

The review applies Emil's design guidance: short pointer feedback, no movement
on keyboard activation, reduced motion, visible focus and detail behind chevrons.

## Limits

No real Privy login, wallet signature, transaction, remote database read, deployment
or push was performed. Real Privy use depends on the user's local configuration.
The Ash and identity fixtures are demonstrations, not evidence of complete product
journey coverage. The broader application suites were not rerun.

The existing full migration sequence initially failed because it expects a
`platform` schema. The showcase needs no migrated product records; its focused
checks use the repository's existing disposable test fixture setup. This finding
belongs to the broader fresh-checkout workstream, not a migration change here.
