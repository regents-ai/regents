## 2026-11-12

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
