# Agent parity

Sean, 28 Oct 2026: "any action only a human can do" on the site is a bug. An agent may
own a Privy account itself, so everything an account's owner, a staker, a token or
Animata holder or a site admin can do on regents.sh, an agent can do through each of
five surfaces: the website in headless Chromium, WebMCP, hosted MCP at `/mcp` for
signed agents, the Claude connector (the `/mcp` a person adds to their Claude account,
signed in with OAuth), and the regents CLI. This file has one row per action.

Audited on regents main `4948e2d1` (29 Oct 2026), read from the committed tree only.
Sources: `platform/lib/regents_web/router.ex`, `platform/lib/regents_web/endpoint.ex`,
every `handle_event` in `platform/lib/regents_web/live/` and
`platform/lib/regents_web/components/`, the wallet step builders
(`Regents.Staking.Steps`, `Regents.Redemption.Steps`, `RegentCredits.Chains.steps/3`
behind `RegentsWeb.CreditsPanel`, all sent through `RegentsWeb.OnchainSteps`),
`platform/priv/tool_manifest.json` (24 tools), `cli/commands.json` (18 commands),
the shared profile `identity/lib/regent_identity/http.ex` and the shared agents
router from elixir-utils `14013e42` (`RegentAgents.HTTP`: pair, me, whoami). The
local showcase, the Privy showcase and the motion lab (`/showcase`, `/animations`)
were skipped.

## Key

- **Page**: an agent that owns the account can finish it in headless Chromium with its
  own wallet. Every signed-in page row waits on R1. While the site is closed
  (`REGENTS_APP_SURFACES=off`) only the home page, signing out, the legal pages,
  Articles, Paper Pro Daily and `/start` stay open; the code does not say which way
  production is set.
- **WebMCP**: the tool in `platform/priv/tool_manifest.json`. Signed tools are prepared
  with `prepare_agent_request`, signed by the agent's own SIWA key, and act for the
  agent's paired person. There are no wallet tools.
- **MCP**: hosted `/mcp` for signed agents. regents.sh has none: no route, no plug and
  no MCP library in its dependencies (R2).
- **Connector**: the Claude connector at `/mcp`, signed in with OAuth. regents.sh has
  none: no OAuth routes and no connector code (R3).
- **CLI**: the command in `cli/commands.json`, matched on route and operation id. All
  18 are in released regents-cli 1.10.20 and in regents-cli main
  (`platforms/protocol/commands.json`), so nothing here waits for the next release.
  There are no wallet commands.
- **Protected**: needs Sean's go (sign-in, wallets, money, secrets, personal or
  production data).
- `—` means the surface has no way to do it: a gap, listed under Gaps. "agents only"
  in Page means people have no page for it, which this rule does not count.

## Account

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sign in / make the account | Privy sign-in window (`POST /auth/privy/session`), untested for agents | — | — | — | — | sign-in | R1 |
| Sign out | account menu Sign out (`DELETE /auth/privy/session`) | — | — | — | — | sign-in | R1 |
| Agent's own identity (whoami, check in) | agents only | `regents_agent_whoami` | — | — | `agents whoami`, `agents status` | no | R2, R3, R4 |
| Read display name and ENS name | `/account` | `regents_account` | — | — | `account show` | no | R2, R3 |
| Read wallets | `/account/wallets` | — | — | — | — | wallet | R11 |
| Set display name | `/account` Public Display Name (`PATCH /api/v1/profile` with a Privy proof pair) | — | — | — | — | sign-in | R11 |
| Verified connections (X, GitHub, Farcaster: start, refresh) | `/account/connections` | — | — | — | — | sign-in | R11 |

## Agents

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Make a pairing code, choose the agent | Pair New Agent (Account page) | — | — | — | — | no (owner only) | R5 |
| Pair with a code | agents only | — | — | — | `agents pair` | no | R2, R3, R4 |
| Open or unpair an agent, read its last actions | account menu Agents, `/account` | — | — | — | — | no (owner only) | R5 |
| Set or remove an agent's picture | `/account` agent window (upload) | `regents_agent_picture_set`, `regents_agent_picture_remove` (its own) | — | — | `agents picture set`, `agents picture remove` (its own) | no | R6 (MCP, connector) |
| Set what each agent may spend (on or off, per spend, daily, sites) | `/account/credits` Agent spending | — | — | — | — | money | R7 |
| Read the agent's own spending budget | agents only | `regents_credits_budget` | — | — | `account budget` | no | R2, R3 |

## Names

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Read claimed Regent Names | `/names` (more on scroll) | `regents_claims` | — | — | `account claims` | no | R2, R3 |
| Check a name, see free claims left, claim a free name | `/names` Claim | — | — | — | — | no | R12 |

## Credits

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Read Credits balance | header, `/account` | `regents_credits_balance` | — | — | `account balances` | no | R2, R3 |
| Read Credits purchase history | `/account/credits` (more) | `regents_credits_history` | — | — | `account credits-history` | no | R2, R3 |
| Buy Credits with USDC on Base (approve, buy, then the purchase counts) | Buy Credits panel | — | — | — | — | money, wallet | R8 |
| Read Points | `/account/points` | `regents_points_summary` | — | — | `account points` | no | R2, R3 |

## Stake

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Read the stake (contract and own wallet) | `/stake` (with refresh) | `regents_stake_position` | — | — | `staking position` | no | R2, R3 |
| Stake REGENT (approve, stake; to yourself or another wallet) | `/stake` | — | — | — | — | money, wallet | R9 |
| Unstake REGENT | `/stake` | — | — | — | — | money, wallet | R9 |
| Claim USDC, claim REGENT, or claim and restake | `/stake` | — | — | — | — | money, wallet | R9 |

## Redeem

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Read the redemption and owned Animata and Club passes | `/redeem` (refresh, show more), `/redeem/gallery` My passes | — | — | — | — | no | R10 |
| Redeem an Animata (approve the collection, approve 80 USDC, redeem) | `/redeem` | — | — | — | — | money, wallet | R10 |
| Claim unlocked REGENT | `/redeem` | — | — | — | — | money, wallet | R10 |

## Reading

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Read about Regents and the docs | `/about`, `/docs` and each `/docs/<page>` | `regents_about` (`docs`, `docs-<page>`) | — | — | — (plain fetch) | no | R2, R3 |
| Read other site pages (start, contact, refund rules, privacy, terms) | `/start`, `/contact`, `/credits/refunds`, `/privacy`, `/terms` | `regents_about` | — | — | — (plain fetch, as Markdown) | no | R2, R3 |
| Read Regents Cloak and its setup guide | `/cloak`, `/cloak/guide` | `regents_about` (the guide) | — | — | — (plain fetch, `/cloak/guide` as Markdown) | no | R2, R3 |
| Read products | `/app`, `/autolaunch`, `/techtree`, `/patchbay`, `/keyfleet` | `regents_products`, `regents_product` | — | — | `products list`, `products get` | no | R2, R3 |
| Read research (Paper Pro Daily) | `/paper-pro-daily` (more, list) | `regents_research_list`, `regents_research_paper` | — | — | `research list`, `research show` | no | R2, R3 |
| Read Articles | `/articles`, `/articles/:slug` | `regents_articles_list`, `regents_article` | — | — | `articles list`, `articles show` | no | R2, R3 |
| Read literature | `/literature` | `regents_literature` | — | — | `literature list` | no | R2, R3 |
| Read a public Regent profile | `/regents/:slug` | `regents_public_profile` | — | — | `profiles show` | no | R2, R3 |
| List each Regent site's tools, SIWA help | agents only | `list_regents_webmcp_tools` and five more, `get_siwa_connection_help` | — | — | n/a (each site has its own commands) | no | R2, R3 |

## Admin

| Action | Page | WebMCP | MCP | Connector | CLI | Protected | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Publish an Article (authors, cover picture) | `/admin/articles` | — | — | — | — | production data (public post) | R14 |
| Give Credits | `/admin/credits` | — | — | — | — | money | R15 |
| Find a person's purchases, start and close a refund | `/admin/credits` | — | — | — | — | money, personal data | R15 |
| Remove an agent's picture | `/admin/credits` | — | — | — | — | production data | R15 |
| Saved errors | `/admin/errors` | — | — | — | — | production data | R16 |

## Page check

- No captcha anywhere in the site's code. Sign-in is Privy's window; its sign-in
  methods are set in Privy's dashboard, not in the code, and nothing shows an agent
  finishing it headless with its own wallet (R1).
- Every wallet button goes through Privy's wallet approval screen, which has words and
  buttons; unproven headless for an agent-owned wallet (R1). Each press asks the wallet
  onto Base first.
- Verified connections hand off to X, GitHub or Farcaster sign-in through Privy. Those
  are other companies' pages and may show their own human checks (R11).
- The home page cube is a drawn picture turned by dragging, but nothing needs it: the
  server renders the same worlds as a plain list of cards with links. The glass panes
  inside each cube room (copy only, no action) show only when the cube is drawn.
- The pairing box chooses agents by their pictures, but each choice carries the agent's
  name. Redeem's Animata tiles hide the art from screen readers and carry the type and
  token number in words.
- Unpairing an agent asks in the browser's own worded confirm box, which headless
  Chromium can answer. Claiming a name and publishing are worded buttons.

## Gaps

- **R1. An agent can't own an account yet.** Sign-in is Privy in a browser only, and
  every signed agent read needs pairing to a person ("This agent has no current
  pairing"). Plan: the Privy account whose login wallet is the agent's SIWA wallet is
  the agent's own account, and a request signed by that wallet acts as its owner, as in
  ash-template's G1. Protected (sign-in): waits for Sean's go. Owner: agent-access lane.
- **R2. No hosted MCP.** regents.sh has no `/mcp` route or plug, and none of the shared
  MCP libraries is in `platform/mix.exs`. Plan: mount the shared `/mcp` that ash-template
  and Keyfleet use and serve the manifest's 24 tools through it. Not protected for the
  reads; any signed tool keeps its own rule. Owner: agent-access lane.
- **R3. No Claude connector.** There are no OAuth routes and no connector tools. Plan:
  the shared connector with OAuth sign-in from ash-template, serving the same tools as
  R2. Protected (sign-in: OAuth approval). Owner: agent-access lane.
- **R4. Pairing and check-in have no WebMCP tool.** `agents pair` and `agents status`
  exist in the CLI; the page tools offer only `regents_agent_whoami`. Plan: signed
  `regents_agent_pair` and `regents_agent_status` tools on the existing
  `/api/agents/v1/pair` and `/me` routes. Not protected. Owner: agent-access lane.
- **R5. Owner-only agent controls are page-only.** Making a pairing code, choosing the
  agent, opening and unpairing an agent and reading its last actions run only in the
  account menu and on `/account`. They stay out of reach of a paired helper agent and
  open only to the owner from R1. Not protected (owner only).
- **R6. Agent pictures are not on hosted MCP.** The person uploads or removes an agent's
  picture in its window on `/account`. A paired agent sets and removes its own with signed
  `POST` and `DELETE /api/agent/v1/picture`, the `regents_agent_picture_set` and
  `regents_agent_picture_remove` browser tools and `agents picture set` and
  `agents picture remove`, the template's `RegentAgents.set_own_agent_picture` and
  `remove_own_agent_picture`. Left: the hosted MCP tools, with the template's. Not protected.
- **R7. Agent spending limits are page-only.** Turning an agent's spending on, its
  limits and its sites are saved only for a person signed in on `/account/credits`. Plan: an
  owner-only signed route, tool and command after R1. Protected (money).
- **R8. Buying Credits has no agent path.** Only the Buy Credits panel builds the
  approve and buy steps and reports the sent buy so it counts.
  `RegentCredits.Chains.steps/3` names no sender, so the site already builds steps an
  agent's own key could sign. Plan: a signed route that answers the steps and one that
  takes the sent buy's hash, a `credits buy` command and a `regents_credits_buy` tool.
  Protected (money, wallet).
- **R9. Staking is page-only.** Stake, unstake, claim USDC, claim REGENT and claim and
  restake run only from `/stake` with the browser's Privy wallet.
  `Regents.Staking.Steps.steps/3` already takes the signer's address, so the site can
  build the same steps for an agent's own key. Plan: a signed steps route, `staking
  stake`, `unstake` and `claim` commands and matching WebMCP tools. Protected (money,
  wallet).
- **R10. Redeem is page-only, reads included.** The redemption figures and the Animata
  and Club passes a wallet holds have no agent read, and redeeming and claiming run
  only from `/redeem`. `Regents.Redemption.Steps.steps/1` names no sender, so any key
  can sign its steps. Plan: a signed read, a steps route, `redeem` commands and tools.
  Protected (money, wallet) for the steps; the read is not.
- **R11. Account settings are page-only.** Linked wallets are not in
  `regents_account`, verified connections need the Privy session, and the display name
  changes only on `/account`, through `/api/v1/profile` with a Privy proof pair. Plan: owner reads in `account show`, and a signed profile
  change in this repository's `identity` library, after R1. Protected (sign-in,
  wallet).
- **R12. Name claims are page-only.** Checking a name, seeing free claims left and
  claiming a free Regent Name run only on `/names`; agents can only read the claims
  made. Plan: a signed route, `regents_name_check` and `regents_name_claim` tools and
  `names check` and `names claim` commands. Not protected (free, no wallet step).
- **R13. Closed.** `regents_about` reads every page that has words to read, as
  Markdown: `/about`, `/docs` and each docs page (`docs-limits` and so on), `/start`, `/contact`, `/credits/refunds`, `/privacy`,
  `/terms` and `/cloak/guide`. `/cloak` itself shows the guide's facts beside the
  disabled download, so the guide stands for it.
- **R14. Publishing Articles is page-only.** `/admin/articles` is for article admins in a
  browser. An admin agent needs the same through the five surfaces. Protected
  (production data, public post); after R1.
- **R15. Credits admin is page-only.** Giving Credits, finding a person's purchases,
  starting and closing refunds and removing an agent's picture run only on
  `/admin/credits`. Protected (money, personal and production data); after R1.
- **R16. Saved errors are page-only.** `/admin/errors` is for Credits admins in a
  browser. An admin agent needs the same read. Protected (production data); after R1.
