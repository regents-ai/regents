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
| Home code cube: each side copies its own site's card, never another's | `browser/homepage.spec.ts` "each code cube side copies its own site's card" (1280 and 390, all six sides against each card's own copy) | The site reads come from the live sites; a site that cannot be read is checked by its heading only. Touch sizes (View Tools 44 px, a 44 px strip below it) were measured by hand at 320, 390 and 800 |
| Sign in and sign out with Privy; tabs stay in step | `browser/u3_auth_lazy_acceptance.spec.ts`, `regents_web/live/session_authority_gate_test.exs` | |
| Walk every page in one visit, signed out and signed in | `browser/shell_walk.spec.ts` (R04) | R04 sometimes logs Chrome's "play() interrupted" on /redeem |
| Stake: every press reaches the signed-in wallet; wrong wallet and signed-out send nothing | `browser/stake.spec.ts`, `regents_web/stake_live_test.exs` | |
| Stake for a different address: consent, warning, credits that address | `browser/stake.spec.ts` "Alternate stake requires fresh address consent…" | |
| Stake panel keeps one height whatever the different-address box shows, and Tab skips the hidden rows; the Unstake tab has its own height | `browser/stake.spec.ts` "Stake keeps one height…" (1280 and 390) | |
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
