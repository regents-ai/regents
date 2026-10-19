# Feature map

Each thing a person or an agent can do on regents.sh, and the automated check
that proves it. A row with no check is a gap. Add or update a row in the same
commit that changes the feature.

`make check` runs every check: the server tests in `platform/test` and the
browser suite in `platform/test/browser` (headless Chromium). The browser suite
also runs alone with `cd platform && npx playwright test`.

## People

| Feature | Proving check | Gap |
| --- | --- | --- |
| Home page: hero, six worlds in order, every width, keyboard focus, reduced motion | `browser/homepage.spec.ts`, `regents_web/home_live_test.exs` | |
| Home code cube: a press of a side copies its text with a note by the pointer; View Tools opens its card | `browser/homepage.spec.ts` "a code cube side copies its text…" (1280 and 390, siwa-server side, mouse and keyboard) | The drawn cube needs WebGPU, which the headless browser lacks: checked by hand in headless Chrome |
| Home code cube: each side copies its own site's card, never another's | `browser/homepage.spec.ts` "each code cube side copies its own site's card" (1280 and 390, all six sides against each card's own copy and its first entry; the test server answers every site's tools from `test/support/test_site_tools.ex`) | |
| Home code cube on a touch screen: every View Tools is at least 44 px, with a strip of at least 44 px below it that copies | `browser/homepage.spec.ts` "code cube sides are finger-sized on a touch screen" (390 and 320) | |
| Sign in and sign out with Privy; tabs stay in step; a sign-in the server refuses lands the page signed out with one reload, which the server's own disconnect brings | `browser/u3_auth_lazy_acceptance.spec.ts` ("a rejected bearer leaves the browser anonymous…"), `regents_web/live/session_authority_gate_test.exs` | |
| Repeated failed sign-ins are reported at most 20 times a minute; a minute's budget lasts to its last second and returns at the next | `regents_web/controllers/privy_session_controller_test.exs` "repeated rejected sessions share the actionable bound" (the clock stands still), `regents/rate_limiter_test.exs` (both sides of a window's edge) | |
| Walk every page in one visit, signed out and signed in | `browser/shell_walk.spec.ts` (R04) | R04 sometimes logs Chrome's "play() interrupted" on /redeem |
| Stake: every press reaches the signed-in wallet; wrong wallet and signed-out send nothing | `browser/stake.spec.ts`, `regents_web/stake_live_test.exs` | |
| Stake for a different address: ticking opens a window for the address and its warning; the row then reads "Rewards go to 0x….. · Change"; the box and Change each take a 44 px press, Change 44 px wide; consent, credits that address | `browser/stake.spec.ts` "Alternate stake requires fresh address consent…" (window at 1280, 390, 320; Done and Escape close it); "Stake keeps one height…" (press areas at 1280, 390, 320, every edge) | |
| Stake panel keeps one height whatever the different-address box shows, leaves no blank room below a stake of your own, keeps the choice on one row clear of "Amount", never lets 50% and Max cover what is available, and Tab skips the hidden rows; the Unstake tab has its own height | `browser/stake.spec.ts` "Stake keeps one height…" (1280, 390, 320) | A stake for someone else still holds the position preview's room |
| Stake wallet answers: declined, no usable hash | `browser/stake.spec.ts` | |
| Redeem: approvals, Redeem, wrong wallet, refresh keeps place | `browser/redeem.spec.ts`, `regents_web/redeem_live_test.exs` | |
| Redeem gallery: owned NFTs, fair OpenSea lookups per visitor | `regents_web/redeem_gallery_live_test.exs`, `regents/open_sea` | |
| Account page and paired agents | `regents_web/account_agents_live_test.exs`, `browser/shell_walk.spec.ts` | |
| Account credits and points pages | `regents_web/route_catalog_test.exs` (route exists only) | No check of what the pages show |
| Credits refunds and the credits admin page | `regents_web/route_catalog_test.exs` (route exists only), `regents/credits/credited_test.exs` | No page-level check |
| Articles and the articles admin page | `browser/page_policy.spec.ts`, `regents_web/router_gate_coverage_test.exs` | No check of reading or editing an article |
| Regent profile pages | `regents_web/regent_profile_live_test.exs` | |
| Product pages (Autolaunch, Techtree, Patchbay, Keyfleet) and Overview | `browser/regent_overview_token.spec.ts`, `regents_web/product_live_test.exs` | |
| Paper Pro Daily and Literature | `regents_web/paper_pro_daily_live_test.exs`, `regents_web/controllers/literature_controller_test.exs` | |
| Free name claim | `regents/names/claim_free_test.exs`; production has the unique index on each name | |
| No page is refused by its security policy; no sideways scroll at any width | `browser/page_policy.spec.ts`, `browser/founder_shell.spec.ts` | |
| The browser suite never leaves the test machine: the page's requests to other hosts are answered in the browser, the test server refuses every outside request before it leaves, and either fails the test | `browser/support/offline.ts`, imported by every browser spec; `test/support/outside_requests.ex`, the test server's Req adapter | Calls made without Req are seen only while their connection is open |
| The test wallet drives the wallet buttons on whatever port the browser test server runs | `assets/test/connected_wallet.test.ts`; the browser suite runs on `PORT` | |

## Agents

| Feature | Proving check | Gap |
| --- | --- | --- |
| Signed agent reads: account, claims, staking position, credits, points | `regents_web/api_contract_test.exs`, `regents_web/agent_requests_test.exs` | |
| Agent guides: agents.md, skill.md, llms.txt, openapi.json, docs | `regents_web/public_documents_test.exs`, `regents_web/content_negotiation_test.exs`, `make check-cli` | |
| Profile API | `regents_web/controllers/profile_api_test.exs` | |
| Site tools listing (`/site-tools/:site`) | none | No check |

## Live site

| Feature | Proving check | Gap |
| --- | --- | --- |
| Release runs the committed commit | `make deploy` labels the image; `fly image show` names the commit | |
| Health check | `/healthz` answers 200 | |
| Signed-in pages on the live site | Sentinel's after-read | Not automated: no wallet sign-in on production |
