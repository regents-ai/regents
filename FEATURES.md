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
| Home page fleet figure: five cards, each a name and a slogan that opens its app, joined by six labelled lines; no card or label covers another and nothing leaves the figure; it fits in the top half of a 1440 by 900 screen; without a GPU frame the still lines show | `browser/fleet_figure.spec.ts` (1440, 1024, 390 and 320, no sideways scroll) | The flowing lines need WebGPU: checked by hand in headless Chromium started with WebGPU switched on |
| Agents read the same example workflows and the exact revenue split, as data and as the home page's Markdown; neither says every fee goes to stakers | `regents_web/example_workflows_test.exs` | |
| The old /stake address sends people to the home page for good | `regents_web/example_workflows_test.exs` | |
| The vgpu demo at /vgpu-demo: the cube of the four products and staking, six worlds in order, every width, keyboard focus, reduced motion, always dark, open while the rest of the app is closed | `browser/vgpu_demo.spec.ts`, `regents_web/vgpu_demo_live_test.exs`, `regents_web/launch_gate_test.exs` | The drawn cube needs WebGPU, which the headless browser lacks: its size and the words over it are checked by hand in headless pictures |
| The "Agents see" window copies every Regent site's tools at once, each site its own section, then how an agent signs in; it stays open when opened while the page is still connecting | `browser/agent_tools.spec.ts` "the tools window copies every site's tools…" (1280 and 390; the test server answers every site's tools from `test/support/test_site_tools.ex`) | |
| Sign in and sign out with Privy; tabs stay in step; a sign-in the server refuses lands the page signed out with one reload, which the server's own disconnect brings | `browser/u3_auth_lazy_acceptance.spec.ts` ("a rejected bearer leaves the browser anonymous…"), `regents_web/live/session_authority_gate_test.exs` | |
| Repeated failed sign-ins are reported at most 20 times a minute; a minute's budget lasts to its last second and returns at the next | `regents_web/controllers/privy_session_controller_test.exs` "repeated rejected sessions share the actionable bound" (the clock stands still), `regents/rate_limiter_test.exs` (both sides of a window's edge) | |
| Walk every page in one visit, signed out and signed in | `browser/shell_walk.spec.ts` (R04) | R04 sometimes logs Chrome's "play() interrupted" on /redeem |
| Stake: every press reaches the signed-in wallet; wrong wallet and signed-out send nothing | `browser/stake.spec.ts`, `regents_web/stake_live_test.exs` | |
| Stake for a different address: ticking opens a window for the address and its warning; the row then reads "Rewards go to 0x….. · Change"; on a touch screen the box and Change each take a 44 px press, Change 44 px wide, and with a mouse both keep the size of their words; consent, credits that address | `browser/stake.spec.ts` "Alternate stake requires fresh address consent…" (window at 1280, 390, 320; Done and Escape close it); "Stake keeps one height…" (1280, 390, 320 with a mouse, words at their own size); "on a touch phone › Stake gives the different-address choice finger-sized press areas" (390 and 320, every edge) | |
| Stake panel keeps one height whatever the different-address box shows, leaves no blank room below a stake of your own, keeps the choice on one row clear of "Amount", never lets 50% and Max cover what is available, and Tab skips the hidden rows; the Unstake tab has its own height | `browser/stake.spec.ts` "Stake keeps one height…" (1280, 390, 320) | A stake for someone else still holds the position preview's room |
| Stake wallet answers: declined, no usable hash | `browser/stake.spec.ts` | |
| Redeem: approvals, Redeem, wrong wallet, refresh keeps place | `browser/redeem.spec.ts`, `regents_web/redeem_live_test.exs` | |
| Redeem gallery: owned NFTs, fair OpenSea lookups per visitor | `regents_web/redeem_gallery_live_test.exs`, `regents/open_sea` | |
| Account page and paired agents | `regents_web/account_agents_live_test.exs`, `browser/shell_walk.spec.ts` | |
| Pair New Agent on the Account page opens the side panel and flashes the agents to choose from there, scrolled into view, on every press; on a phone it opens the covering panel; with less motion asked for the box stays marked instead of flashing | `browser/pair_new_agent.spec.ts` (1280 and 390, a short window, a second press after scrolling away; less motion at 1280) | |
| Account credits and points pages | `regents_web/route_catalog_test.exs` (route exists only) | No check of what the pages show |
| Credits refunds and the credits admin page | `regents_web/route_catalog_test.exs` (route exists only), `regents/credits/credited_test.exs` | No page-level check |
| Articles and the articles admin page | `browser/page_policy.spec.ts`, `regents_web/router_gate_coverage_test.exs` | No check of reading or editing an article |
| Regent profile pages | `regents_web/regent_profile_live_test.exs` | |
| Product pages (Autolaunch, Techtree, Patchbay, Keyfleet) | `regents_web/product_live_test.exs` | |
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
| Tool lists for agents: one for each site's tools (`/api/v1/site-tools/:site`), one complete list of every site (`/api/v1/site-tools`), and how to sign in through siwa-server | `browser/agent_tools.spec.ts` "every page offers a list of each site's tools and the complete list" | |

## Live site

| Feature | Proving check | Gap |
| --- | --- | --- |
| Release runs the committed commit | `make deploy` labels the image; `fly image show` names the commit | |
| Health check | `/healthz` answers 200 | |
| Signed-in pages on the live site | Sentinel's after-read | Not automated: no wallet sign-in on production |
