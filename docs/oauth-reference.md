# Connected apps and the MCP address

regents.sh takes its Claude connector and hosted MCP address from ash-template, the
golden baseline (`repos/ash-template/docs/oauth-reference.md`). This file records
what Regents sets differently. Branch `connector-mcp-1029` ships in the joint
connector window with the other four sites, and the switch stays off until then.

## The switch

`REGENTS_CLAUDE_CONNECTOR_ENABLED=true` turns on, read once at boot by
`platform/config/runtime.exs`:

- the sign-in under `/oauth` and `/.well-known/oauth-*` (`Regents.OAuth`,
  `RegentOAuth.enabled?/0`), with `RegentOAuth.Repo` supervised;
- a Bearer token at `/mcp` and the connector's identity tools;
- Claude in Pair New Agent (`config :regent_agents, hosted_pairing: [:claude]`);
- the guide at `/agents/claude`, its sitemap line, the connector paragraph in
  `/agents.md` and the connector sentence in `/llms.txt`'s hosted MCP line. While
  off, `/agents/claude` and the protocol addresses under `/oauth` are not found;
  the library's Connected apps page and its consent page refuse, and reach no data.

The switch governs tokens, not signatures: a signed paired agent keeps `/mcp` and its
five reads while the switch is off, on purpose, as in the hosted MCP rollout's go-live
check (`control/rollouts/2026-10-29-hosted-mcp.md`). The signed browser tools and the
hosted MCP hint name `regents mcp` and `regents browser`, so this branch ships only
with the regents-cli release that has both commands.

With the switch on, boot stops unless `SIWA_HOSTED_SIGNING_KEY` is the Regents
hosted signing key at the sign-in service (`SIWA_SERVER_URL`). The audience is
`regents`, which elixir-utils accepts from `466ca10f`. siwa-server does not yet
hold a key for `regents`; adding one is a protected step in the window.

## Permissions

- `regent.identity.manage`: the app keeps one Regents identity, pairs it with the
  account using a code the person gives it, and checks in.
- `regents.agent` (`Regents.OAuth.agent_scope/0`): once that identity is paired with
  the same account, the app works here as that paired agent, with its reads and
  nothing more. It can never spend, use the wallet, change the account or pair
  other agents.

## The MCP address

`forward "/mcp", AshAi.Mcp.Router` in `platform/lib/regents_web/router.ex`, behind the
`:mcp` pipeline: the launch gate, then `RegentsWeb.Plugs.McpAgent`. McpAgent refuses
a query string, any other address or method, a page from another site, a body that
is not JSON and a batch before it looks at a credential. Every request then carries
exactly one credential, an agent's signature or a connected app's token. McpAgent's
refusals and every tool answer are `cache-control: private, no-store`; the endpoint's
own 429 and 413, which carry no account data, keep Plug's default.

Tools are the `priv/capabilities.json` rows with `hosted_mcp: true`
(`RegentsWeb.Capabilities.hosted_tools/0`):

- for a connected app: `register_identity`, `get_identity`, `pair_identity`,
  `check_in` (`Regents.Agents.Connection`), and with `regents.agent` the five reads;
- for a signed paired agent, and a connected app with `regents.agent`:
  `regents_account`, `regents_credits_balance`, `regents_credits_budget`,
  `regents_credits_history` and `regents_points_summary` (`Regents.Agents.AccountReads`,
  the same actions the agent API calls).

Arguments are checked against the action before it runs
(`RegentsWeb.ToolErrors.check_input/3`): unknown input is `invalid_input`, a bad
`after` on Credits history is `invalid_cursor`, as over HTTP.

Budgets, all through `RegentAgentAccess.RateLimit` and `Regents.RateLimiter`: every
request whose token has not been checked counts 120 a minute against its address
(`mcp_address`, the API's figure), a request with no token in the endpoint before
its body is read (`RegentsWeb.Plugs.McpAgent.limit_address/1`), one with a token
that isn't this site's when McpAgent refuses it. Only a token `RegentOAuth.verify/3`
accepts counts against its address's ceiling of 600 a minute
(`mcp_connected_address`) instead, since Claude's connector calls from Anthropic's
shared servers and one address carries many accounts, and then against its connected
account's own 120 under its OAuth subject (`mcp`). Once an address has spent its 120,
its next request with a token is refused 429 in the endpoint, before the token is
looked up, so a stream of made-up tokens costs the sign-in store at most 120 lookups
a minute from one address. Every answer from `/mcp` says `cache-control: private,
no-store`, set as it leaves, over AshAi's own `no-cache` on a streamed answer.

A connected identity's signing address is kept in `Regents.Agents.HostedAddress`, a
Nebulex local cache: only a successful answer from the sign-in service is kept, so
the first call after an outage asks again.

## Issuer, resource and tokens

The issuer is the site's own address and the resource its `/mcp`: `https://PHX_HOST`
in production, the endpoint's address elsewhere. Codes and tokens carry both, and
one whose values differ from the running site's is refused. Tokens are stored only
as their SHA-256 hash.

## Migration

`platform/priv/repo/migrations/20261030002730_add_oauth_connector.exs` runs
`RegentOAuth.Migration.up()` then `RegentOAuth.Migration.V2.up()` in `regents_app`,
with `SET LOCAL lock_timeout = '5s'`. Regents has no OAuth tables before it, so it
only creates tables, and no client-scopes migration is needed: apps register with
both permissions from the start. It runs in the release step of the joint window,
never before.
