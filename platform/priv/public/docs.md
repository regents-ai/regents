# Developer documentation

Regents Labs is the community-owned agentic product lab behind Autolaunch, Techtree and Patchbay. Use Regents to understand the products, find REGENT staking and redemption, and read historical name claims belonging to an authenticated account.

## Start without an account

Public documentation and health reads do not require an API key or wallet. Read this page, the [agent guide]({{origin}}/llms.txt), or the [OpenAPI JSON specification]({{origin}}/openapi.json).

```sh
curl --fail '{{origin}}/healthz'
curl --fail -H 'Accept: text/markdown' '{{origin}}/docs'
curl --fail '{{origin}}/openapi.json'
curl --fail '{{origin}}/api/v1/products'
curl --fail '{{origin}}/api/v1/products/techtree'
```

`GET /api/v1/products` lists Autolaunch, Techtree and Patchbay with each one's summary and links; `GET /api/v1/products/{slug}` returns everything that product's page on Regents shows. An unknown slug returns 404.

The health response is the plain text `ok`. A health response confirms the web service is responding, not that every wallet or external service is available.

The homepage, this documentation, About, Contact, Privacy and Terms support `Accept: text/markdown` at their ordinary URLs. Browsers receive HTML by default. Responses distinguish the representations with `Vary: Accept`. Unknown page URLs return 404 rather than a successful empty document.

## Read your historical name claims

`GET /api/v1/claims` returns only historical claims authorized for the verified account. It does not mint a name, assign an ENS name, change ownership, or grant an entitlement.

Authenticate using both a Privy access token in `Authorization: Bearer …` and a Privy identity token in `Privy-Id-Token`. These are identity credentials, not new Regents API keys. Keep them private; never paste tokens, private keys or recovery phrases into a chat, report or public issue.

The following command assumes the two token variables have already been supplied through your own secure credential handling:

```sh
curl --fail-with-body '{{origin}}/api/v1/claims' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer ${PRIVY_ACCESS_TOKEN}" \
  -H "Privy-Id-Token: ${PRIVY_IDENTITY_TOKEN}"
```

A successful response contains a `claims` array and a `next` cursor. Each claim contains its recorded name, wallet owner, status, transaction evidence and timestamps; absent historical fields may be null. Use the exact returned cursor as the sole `after` query parameter for the next page. Stop when `next` is null. Do not invent an owner filter or a page-size parameter.

Missing or invalid credentials return 401. An invalid query or cursor returns 400; forbidden reads return 403. A temporarily unavailable or unconfigured claims service returns 503. Claims responses are not cacheable. A selected name or wallet address is not authentication.

## Read your stake

`GET /api/v1/staking/position`, with the same two tokens, returns what [Stake]({{origin}}/stake) shows for the wallet on that sign-in: the REGENT it has staked and holds, the USDC and REGENT it can claim, and the contract's totals. Every figure is a Base reading with the block it was read at; amounts are exact decimal strings, and a figure that could not be read is `"unavailable"`. A sign-in with no wallet returns 409 `wallet_required`; before Base has answered once, 503 `staking_unavailable`.

## Pair an agent with a person's account

A person makes a one-time pairing code on their [Account]({{origin}}/account) page and gives it to their agent. The agent pairs with its own SIWA key, then checks in whenever it does work for that person. Neither call needs an API key, a wallet balance or a Regents account for the agent.

Every agent request is signed through `https://siwa.regents.sh`; the [SIWA agent guide](https://siwa.regents.sh/skill.md) covers getting the client and choosing how the agent signs. With the `regents` command line (`uv tool install git+https://github.com/regents-ai/regents-cli`), sign in once, then pair and check in:

```sh
regents auth login --site regents
regents protocol agents pair --code <code> --name Sol --harness hermes
regents protocol agents me
```

With the SIWA client, once its key is set up:

```sh
uv run siwa_agent.py pair '{{origin}}' <code> --name Sol --harness hermes
uv run siwa_agent.py me '{{origin}}'
```

`POST /api/agents/v1/pair` answers `201` with the paired agent. `harness` is one of `hermes`, `grok_bot`, `muse`, `openclaw`, `nemoclaw`, `ironclaw`, `pi`, `claude_code`, `codex`, `cursor`, `gemini_cli`, `dots` or `other`; the person can correct it later. `GET /api/agents/v1/me` records the check-in as the agent's latest contact and answers `200` with the paired agent and the names of the account it is paired with, as the person sees them on their Account page; either name is `null` until the person has one. Both answers carry `registry_listing`: the agent's page in the agent registry, or `null` when it has no listing there; `human_backed`: whether a person verified with World ID stands behind the agent; and `same_person_agent_count`: how many agents, this one included, that same person stands behind, or `null` when no verified person does. To become human-backed, follow step 7 of https://siwa.regents.sh/skill.md. Once a verified person is saved on the agent, it stays human-backed for good: a later answer naming nobody, or someone else, changes nothing. The person sees all three beside the agent on their Account page. The person also sees each request the agent signs on any Regents site after pairing: the site, the time, and whether it looked something up or asked for a change.

The check-in answer looks like this:

```json
{"data": {"name": "Sol", "harness": "hermes", "wallet": "0x…", "paired_at": "2026-09-26T15:00:00Z", "last_contact_at": "2026-09-26T15:05:00Z", "registry_listing": "https://www.8004scan.io/agents/base/97609", "human_backed": false, "same_person_agent_count": null, "account": {"display_name": "Ada", "ens_name": "ada.eth"}}}
```

Errors share one shape, `{"error": {"code": "…", "message": "…", "hint": "…"}}`: the message says what happened and the hint says what to do next. `400 pairing_failed` means the code is used, expired or mistyped; a code works once and expires ten minutes after it was made. `400 harness_unknown` means `harness` is not one of the listed runtimes. `409 agent_limit` means the person's account already has 100 paired agents; once they unpair one, the same code works until it expires. `401 verification_failed` means the signature could not be verified; `401 duplicate_proof`, `401 unsupported_query` and `401 missing_signed_body` mean a signature header was sent twice, the request carried a query string, or its body could not be read whole, so sign it again as the guide describes; any other refusal of the signature comes from the sign-in service with its own status, code, message and hint, such as `409 request_replayed`; the hint is written for this site and the way the agent signs. `503 verification_unavailable` means the sign-in service could not be reached; try again in a minute. `404 not_paired` from a check-in means the person unpaired the agent.

## Request limits

Pairing allows 10 requests and check-ins 60 requests per client address per minute. Every agent answer says where the caller stands:

```http
RateLimit-Policy: "pair";q=10;w=60
RateLimit: "pair";r=9;t=42
```

`q` is the number of requests allowed in a window of `w` seconds, `r` is how many remain and `t` is the number of seconds until the window resets. Past the limit the answer is `429 rate_limited` with a `Retry-After` header in seconds; wait that long, then try again.

## Contracts and availability

The [OpenAPI JSON specification]({{origin}}/openapi.json) describes the health read, the product directory, the owner-authorized claims and stake reads and agent pairing above, including their schemas, authentication requirements and request limits. It intentionally does not describe wallet transactions or session changes.

We change the API in place and update these docs the same day; no old versions are kept.

2026-09-28: every error, including sign-in refusals, pages that aren't open yet and the product, claims, stake and agent reads, answers `{"error": {"code": "…", "message": "…", "hint": "…"}}`. The codes are unchanged. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 2.0.0.

The [existing YAML contract]({{origin}}/api-contract.openapiv3.yaml) also describes retained product interfaces; some listed operations may not be available yet. For new token-auction work use [Autolaunch](https://autolaunch.sh); for Skill evaluations use [Techtree](https://techtree.sh); for agent-tool reports and repairs use [Patchbay](https://patchbay.help). Each product owns its permissions and integration contract.

The published [@regentslabs/cli package](https://www.npmjs.com/package/@regentslabs/cli) version 0.5.0 was built against an earlier version of this service and is not supported for hosted operations in this release. Use the HTTP reads documented above instead.

## Wallet actions and browser agents

Visit [Stake]({{origin}}/stake) or [Redeem]({{origin}}/redeem) for the corresponding wallet flow. Every transaction requires the user's explicit wallet approval. Network fees and contract conditions apply; staking returns are not guaranteed. Public documentation does not authorize a payment, signature, credential change or other mutation.

## In the browser (WebMCP)

Every page offers these tools to browsers that support WebMCP. They make the same reads as the API above and never open a wallet or sign. The signed-in reads work once the person has signed in on Regents.

{{tools}}

Need help? Read [About]({{origin}}/about), [Contact]({{origin}}/contact), [Privacy]({{origin}}/privacy) and [Terms]({{origin}}/terms).
