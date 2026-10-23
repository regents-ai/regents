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
| Home page shows one cube in the middle of the stage, with "Human Browsing" above it, about half again as big on a computer | `browser/homepage.spec.ts` (the six worlds) | The drawn cube needs WebGPU, which the headless browser lacks: its size and the words over it are checked by hand in headless pictures |
| The "Agents see" window copies every Regent site's tools at once, each site its own section, then how an agent signs in; it stays open when opened while the page is still connecting | `browser/agent_tools.spec.ts` "the tools window copies every site's tools…" (1280 and 390; the test server answers every site's tools from `test/support/test_site_tools.ex`) | |
| Sign in and sign out with Privy; tabs stay in step; a page's own sign-out reloads it at once, and a sign-out from another tab or a sign-in the server refuses lands the page signed out with one reload, which the server's own disconnect brings within LiveView's 5 to 10 seconds | `browser/u3_auth_lazy_acceptance.spec.ts` ("a rejected bearer leaves the browser anonymous…"), `browser/stake.spec.ts` "After sign-out Stake asks for the sign-in again…", `regents_web/live/session_authority_gate_test.exs` | |
| A page whose browser still holds a Privy sign-in with a wallet signs the person back in when it loads, unless they pressed Disconnect; sign-out lets go of every connected wallet and never waits on one; on a signed-out page Connect wallet first ends a Privy sign-in the browser still remembers | `assets/test/privy_session_pickup.test.ts`, `assets/test/privy_bridge.test.ts`, `assets/test/privy_bridge_wallets.test.ts`, `assets/test/auth_lazy.test.ts` | No real Privy or wallet app runs headless |
| The Account page names the person's Regents embedded wallet, and their own wallet only when they signed in with one; their own wallet stays their main wallet; a wallet the account no longer holds is never named | `regents_web/sign_in_wallets_test.exs` (signs in with tokens signed as Privy signs them) | Browser sign-ins carry no Regents wallet, so the walk sees "Made for you at your next sign-in" |
| Repeated failed sign-ins are reported at most 20 times a minute; a minute's budget lasts to its last second and returns at the next | `regents_web/controllers/privy_session_controller_test.exs` "repeated rejected sessions share the actionable bound" (the clock stands still), `regents/rate_limiter_test.exs` (both sides of a window's edge) | |
| Walk every page in one visit, Paper Pro Daily and AI & SCIFI included, signed out and signed in | `browser/shell_walk.spec.ts` (R04) | R04 sometimes logs Chrome's "play() interrupted" on /redeem |
| Stake: every press reaches the signed-in wallet; wrong wallet and signed-out send nothing | `browser/stake.spec.ts`, `regents_web/stake_live_test.exs` | |
| Stake for a different address: ticking opens a window for the address and its warning; the row then reads "Rewards go to 0x….. · Change"; on a touch screen the box and Change each take a 44 px press, Change 44 px wide, and with a mouse both keep the size of their words; consent, credits that address | `browser/stake.spec.ts` "Alternate stake requires fresh address consent…" (window at 1280, 390, 320; Done and Escape close it); "Stake keeps one height…" (1280, 390, 320 with a mouse, words at their own size); "on a touch phone › Stake gives the different-address choice finger-sized press areas" (390 and 320, every edge) | |
| Stake panel keeps one height whatever the different-address box shows, leaves no blank room below a stake of your own, keeps the choice on one row clear of "Amount", never lets 50% and Max cover what is available, and Tab skips the hidden rows; the Unstake tab has its own height | `browser/stake.spec.ts` "Stake keeps one height…" (1280, 390, 320) | A stake for someone else still holds the position preview's room |
| Stake wallet answers: declined, no usable hash | `browser/stake.spec.ts` | |
| Stake says when Base was last read; the shared reading runs every five minutes, again after a confirmed press or the read-again icon, and presses close together cost one read | `browser/stake.spec.ts` "Stake shows when Base was last read…" (1280, 390); `regents_web/stake_live_test.exs` "REFRESH_SOON_AFTER_A_READING", "CONFIRMED_STEP_REFRESHES", "REFRESH_WHILE_A_PASS_RUNS" (an ask during a running pass still gets one more) | Other people's stakes show up to five minutes late |
| Redeem: approvals, Redeem, wrong wallet, refresh keeps place | `browser/redeem.spec.ts`, `regents_web/redeem_live_test.exs` | |
| Redeem gallery: owned NFTs, fair OpenSea lookups per visitor | `regents_web/redeem_gallery_live_test.exs`, `regents/open_sea` | |
| Account page and paired agents | `regents_web/account_agents_live_test.exs`, `browser/shell_walk.spec.ts` | |
| Pair New Agent on the Account page opens the side panel and flashes the agents to choose from there, scrolled into view, on every press; on a phone it opens the covering panel; with less motion asked for the box stays marked instead of flashing | `browser/pair_new_agent.spec.ts` (1280 and 390, a short window, a second press after scrolling away; less motion at 1280) | |
| In the side panel's pairing box each agent keeps its own code until it expires, so choosing another agent and coming back shows the same message; Make a new code replaces the chosen agent's; the form arriving with no agent picked (a reconnecting page, or a submit before a choice) leaves the box as it is and never crashes the panel | `browser/pair_new_agent.spec.ts` "each agent keeps its own code…" and "the pairing form with nothing chosen…" (1280; the second watches the page's socket for a crash and fails on the old box with channel_crash) | 390 not walked for these two |
| Each agent on the Account page names its own wallet beside its name, the full address one press away with its copy icon; its window shows the wallet the same way, and its contact line says "Last check-in" | `regents_web/account_agents_live_test.exs` "an agent opens into its details…" (two agents, each row its own wallet); design-system `regent_ui/test/regent/account_test.exs` (a row without a wallet says "Address unavailable") | No browser walk of the rows: the browser suite pairs no agents |
| The side panel opens under the header's line at every width (beside the page on a wide screen, over it below that), and on a phone the menu and its backdrop open under that line too | `browser/layout.spec.ts` (panel at 2000, 1280, 800 and 390; menu at 390) | |
| Account credits and points pages | `regents_web/route_catalog_test.exs` (route exists only) | No check of what the pages show |
| Credits refunds and the credits admin page | `regents_web/route_catalog_test.exs` (route exists only), `regents/credits/credited_test.exs` | No page-level check |
| Articles and the articles admin page | `browser/page_policy.spec.ts`, `regents_web/router_gate_coverage_test.exs` | No check of reading or editing an article |
| Regent profile pages | `regents_web/regent_profile_live_test.exs` | |
| Product pages (Autolaunch, Techtree, Patchbay, Keyfleet) and Overview | `browser/regent_overview_token.spec.ts`, `regents_web/product_live_test.exs` | |
| Paper Pro Daily and Literature | `regents_web/paper_pro_daily_live_test.exs`, `regents_web/controllers/literature_controller_test.exs` | |
| Signed in, every shell page carries the whole side panel: the agents, the pairing box and the Credits button (Paper Pro Daily and AI & SCIFI included) | `browser/shell_walk.spec.ts` "a signed-in person sees the whole side panel on every shell page" (1280) | 390 not walked |
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
