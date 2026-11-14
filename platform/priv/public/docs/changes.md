## 2026-11-14

Saving your name on [Account]({{origin}}/account) now uses your sign-in on this site, so it no longer fails when your browser cannot reach Privy. An agent you paired can read your shared profile with a signed `GET /api/v1/profile` and set your public name with a signed `PATCH /api/v1/profile`, as [agents.md]({{origin}}/agents.md) shows. The profile API no longer takes Privy sign-in tokens, and `POST /api/v1/profile/sync` is gone: your profile is made when you sign in.

## 2026-11-13

Points runs in three seasons of 30 days, one after another from its start, and stops by itself after the last. From then nothing earns, and [Points]({{origin}}/account/points) and `GET /api/v1/account/points` list no action to do; your total, your place and the leaderboard stay. Points has no start date yet. Your place on the leaderboard, when you sit below the top ten, now moves when your own Points change or you open the page.

A name you save on [Account]({{origin}}/account) now stays after a reload. It shows on Account, in your account menu, on the [Points]({{origin}}/account/points) board and in your agent's read of your account, and a message your agent leaves the Regents team is signed with it. It is the same name every Regent site shows for you. A name with hidden characters in it is refused when you save it.

The [Cloak]({{origin}}/cloak) page offers one way to set it up, the Mac app, whose download stays off until its first signed release. The setup guide at `/cloak/guide` is removed, and `regents_about` no longer takes `cloak`.

## 2026-11-12

The [Cloak]({{origin}}/cloak) page shows four Highlights cards under its heading: Rewriting, Tor circuits, Cover traffic and Sandbox, each with a moving picture. Each card opens the page's Protections.

The [Autolaunch]({{origin}}/autolaunch) page gives today's terms for new launches: Memestock runs on Base and Robinhood Chain, with an auction of about 2 hours on Base or about 24 hours on Robinhood Chain, 49.75% sold, 49.75% locked as liquidity and 0.5% to the creator; Revstake runs on Base, with an auction of about 5 hours, 20% sold, up to 10% locked as liquidity and 70% to the treasury over one year. Its trading fees are 3% for Revstake and 4.3% for Memestock, and covered calls are listed among who it is for. The [Keyfleet]({{origin}}/keyfleet) page says Classic #1 sells its 1,024 Keys in USDC, from 10 USDC for the first to 100 USDC for the last, its three features read Available now, and its second button opens Classic #1. [About]({{origin}}/about) says the Regents Club and Classic #1 are open in place of "opening soon". `GET /api/v1/products/{slug}` gives the same words, and the [OpenAPI JSON specification]({{origin}}/openapi.json) is now version 6.0.3.

The [Patchbay]({{origin}}/patchbay), [Autolaunch]({{origin}}/autolaunch), [Techtree]({{origin}}/techtree) and [Keyfleet]({{origin}}/keyfleet) pages each show six Highlights cards, the ones the product's own site shows, each with a moving picture in the product's colours. Each card opens its page on the product's site in a new tab. The Autolaunch page now leads with onchain stock offerings: launch a memecoin paired with a tokenized stock on Base, sell calls on your stock, or raise early backing for an agent that earns, with Memestock before Revstake. `GET /api/v1/products/{slug}` and the `regents_product` browser tool give each page's six cards, and the [OpenAPI JSON specification]({{origin}}/openapi.json) is now version 6.0.2.

On the [homepage]({{origin}}/), the white crown in the top-left corner opens and closes the menu, from a press, Enter or Space. The agent prompt sits on one line: Copy copies all of it, and View opens the whole prompt in its own window, which Escape, its X or a press beside it closes. The product names are larger, under a Products badge.

The homepage, the [Overview]({{origin}}/app), the sidebar, `GET /api/v1/products` and the `regents_products` browser tool now list the products in one order: Keyfleet, Autolaunch, Protocol, Patchbay, Techtree and Cloak, each with the ones it carries. The [OpenAPI JSON specification]({{origin}}/openapi.json) says so and is now version 6.0.1.

Credits are gone. The balance and Buy Credits leave the header and the account menu, the Credits tab leaves [Account]({{origin}}/account), and the Credits pages, the refund rules and the Credits admin page are gone; their addresses answer not found. `GET /api/v1/account/balances`, `POST /api/v1/account/credits/history`, the browser tools `account_balances` and `account_credits_history`, and the commands `regents protocol account balances` and `account credits-history` are gone with them. Your agent still reads your Points at `GET /api/v1/account/points`, and the Dots, Grok Bot and Muse guides now name that address. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 6.0.0.

A map of the products now opens the [Overview]({{origin}}/app): point at, tap or Tab to a line between two products to read how an agent uses them together, and open any product from its dot.

The [Overview]({{origin}}/app) has one card for each product: Patchbay, Autolaunch, Techtree, Keyfleet, staking and Cloak, each with a moving picture in its own colours. The four product sites open in a new tab. Enter App on the [homepage]({{origin}}/) now opens the Overview, where Stake is one card away.

Agent Message on [/agents]({{origin}}/agents) gives you a text to paste into your agent so it can leave the Regents team a private message, and lets you leave one yourself once signed in. Only the team reads them. A paired agent leaves one with `POST /api/v1/messages/{topic}`, the browser tool `messages_leave`, or `regents protocol messages leave <topic>` in the next regents-cli release; [Signed reads]({{origin}}/docs/agent-reads) describes it. The [OpenAPI JSON specification]({{origin}}/openapi.json) is now version 5.4.0 and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) 5.2.0.

`GET /api/v1/health` also answers `migrations_applied`: `true` when the database has every change the running release carries, `false` while it waits on one. The answer stays 200 either way, and `/healthz` is unchanged. The [OpenAPI JSON specification]({{origin}}/openapi.json) is now version 5.3.0.

[/capabilities.json]({{origin}}/capabilities.json) now gives `cli`: the `package` (`regents-cli`), the `release` the [agent guide]({{origin}}/agents.md) installs and the command `namespace` for this site (`protocol`). The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) describe it.

## 2026-11-11

The [homepage]({{origin}}/) is a field of moving panels you fly over by pointing towards an edge; panels open as they come into view. Press any panel to bring up the menu in the middle, with Enter App, Agent Tools and the products. A couple of seconds later, flying again shrinks it away until your next press. About, the developer docs, the agent guide, Privacy policy and Terms of use are in the footer of the other pages, and the copyright sits at the bottom right.

[Stake]({{origin}}/stake) is one card: a Stake and Unstake switch, the amount with 50% and Max, one button, then your position and rewards. Staking for someone else is the small "For a different address" choice under the amount.

Stake now says "USDC rewards wait on a treasury top-up." under the claim buttons if the staking contract holds too little USDC to pay your USDC rewards. The button still sends the claim from your wallet. `GET /api/v1/staking/position`, the agent's staking read and the `regents_stake_position` browser tool answer `claims` beside `position`: for each claim, the reason against it, such as `usdc_rewards_short`, or null; [Staking]({{origin}}/docs/staking) lists every reason. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 5.1.0.

regents-cli 1.10.24 is current; install it with `uv tool install regents-cli==1.10.24`. The agent guide, the pairing guide and the agent start page ask for it.

A Stake, Approve, claim or Redeem button you pressed keeps saying "Confirm in your wallet" until your wallet answers, even when you switch between Stake and Unstake or change the amount meanwhile. Pressing again still goes to your wallet. A claim that is not ready now says why in its own words, such as "waiting on a reward pool top-up" or "couldn’t read Base", where it used to say "nothing to claim".

## 2026-11-06

Your agent reads your Credits and Points at the same addresses as on the other Regents sites: `GET /api/v1/account/balances`, `POST /api/v1/account/credits/history` and `GET /api/v1/account/points`, with the browser tools `account_balances`, `account_credits_history` and `account_points`. Balances gives your Credits together with what your agent may spend, so the separate spending read and `regents protocol account budget` are gone. The `/api/agent/v1/credits/*` and `/api/agent/v1/points` reads are gone.

[Points]({{origin}}/account/points) shows your total, what you earned today and yesterday, your place, the actions still open and a leaderboard by name or wallet. `GET /api/v1/account/points` answers the same: `points`, `earned_today`, `earned_yesterday`, `rank`, `to_do` (`label`, `repeats`, `points`, `done`, `left`, `today`), `daily_limits` (`name`, `limit`, `remaining`) and `leaderboard` (`rank`, `name`, `wallet`, `ens_name`, `points`, `you`; `name` is null when the person shows by their wallet), beside `entries` and `period_bonuses`. Points are decimal text, such as "12.5", and whole Points have no trailing ".00". A `note` says when earning is off. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 5.0.0.

Pair New Agent, in the account menu and on [Agents]({{origin}}/account/agents), opens a pairing window over the page you are on. A pairing link is now [/pair]({{origin}}/pair); `/pair?to=/stake` ends your agent's message with that page, so it starts there once paired. The start page and the agent guides link to `/pair`.

Escape closes the window on top first, such as Buy Credits or the pairing window, and leaves an open section behind it as it was. The products menu lists Patchbay, Autolaunch, Techtree, Keyfleet and $REGENT Staking, and the site's icons are redrawn to match the other Regents sites.

Every list of the products on the site now reads Patchbay, Autolaunch, Techtree and Keyfleet: the homepage, Overview, the sidebar, `GET /api/v1/products`, the `regents_products` browser tool and the list of every site's tools. The [OpenAPI JSON specification]({{origin}}/openapi.json) says so and is now version 4.0.3.

## 2026-11-05

[Agents]({{origin}}/agents) has a page for each agent, with its setup, common questions and where to get help. Each page's skill is at `/agents/<agent>/skill.md`. These changes are also at [Changelog]({{origin}}/changelog).

The documentation is also in JSON at `/api/v1/docs`, and `/.well-known/api-catalog` lists the API and its description. regents-cli 1.10.23 is current; install it with `uv tool install regents-cli==1.10.23`.

A new paper on [Paper Pro Daily]({{origin}}/paper-pro-daily) shows as soon as it is saved.

## 2026-11-04

All type on the site is now Geist Serif, with Geist Mono for code. The share pictures are redrawn to match, and the staking picture uses the new sentence.

Every paper on [Paper Pro Daily]({{origin}}/paper-pro-daily) has its own short address and a Share button that copies it. The address opens that paper, and a shared link shows only the paper's title and authors. The `url` of each paper in the [Reading]({{origin}}/docs/reading) read is this address.

The seven-day USDC figure on staking now covers exactly the last seven days by each block's own time, however fast Base makes blocks. `usdc_received_from_block` still names the first block it counts.

## 2026-11-02

Signed browser tools take only their input. Your agent's browser host signs each call's exact request with your own agent key, and the page sends those same bytes; `prepare_agent_request` and the `input`, `request` and `proof` arguments are gone. In a browser with no agent signer a signed tool sends nothing and answers `agent_auth_required`.

Every signed request now names the site it is for, as the sign-in service requires. regents-cli 1.10.22 does this; install it with `uv tool install regents-cli==1.10.22`.

Agents and pairing have their own page, [Agents]({{origin}}/account/agents), a tab beside Account. Pair New Agent, the account menu and the agent guides all lead there; a pairing link is now `/account/agents#account-pairing`. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) say so and are now version 4.0.2.

A signed browser tool that refuses a call before sending it now says why: it answers `invalid_request` with the reason in words and in `details.reason`, in place of `signed_request_failed`. A call the site could not be reached for answers `network_error`.

## 2026-10-30

The contact page is gone. Its help, privacy, legal and security addresses are in the Contact section of [About]({{origin}}/about), and the `regents_about` browser tool no longer takes `contact`.

The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) list the check-in refusal for an unpaired agent as `403 agent_not_paired`, as the site answers, and list `400 invalid_name` among the pairing refusals. They are now version 4.0.1.

The developer docs are one page per topic under `/docs`, and each answers `Accept: text/markdown` at its own address. The `regents_about` browser tool reads each docs page by its own name, such as `docs-pairing`; `docs` is the overview.

## 2026-10-28

The browser tool list moved from `/capabilities` to [/capabilities.json]({{origin}}/capabilities.json), and now also gives `build`: the `commit` and `release` this site runs, as on the other Regents sites. The check-in command is `regents protocol agents status`, formerly `agents me`. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 4.0.0.

## 2026-10-20

`GET /api/v1/health` answers the health check as JSON, `{"status": "ok"}`, as on the other Regents sites. The [OpenAPI JSON specification]({{origin}}/openapi.json) is now version 3.1.0.

One request limit covers `/healthz` and every `/api` address: 120 requests a minute for each client address, with pairing also held to 10 a minute. Past a limit the code is `too_many_requests` instead of `rate_limited`, and check-ins no longer have a separate budget of 60. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 3.0.0.

## 2026-09-28

Every error, including sign-in refusals, pages that aren't open yet and the product, claims, stake and agent reads, answers `{"error": {"code": "…", "message": "…", "hint": "…"}}`. The codes are unchanged. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 2.0.0.
