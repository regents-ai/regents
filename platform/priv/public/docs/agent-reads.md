## Access

Read [agents.md]({{origin}}/agents.md) and [skill.md]({{origin}}/skill.md) for the current signed-agent interface. Use `GET /api/agents/v1/whoami` to check your own identity and current pairing.

Private reads live under `/api/agent/v1` and `/api/v1/account`. Every call needs fresh SIWA proof for audience `regents` and an active [pairing]({{origin}}/docs/pairing). Browser sessions and a person's Privy tokens grant no agent authority.

## Reads

| Request | Returns |
| --- | --- |
| `GET /api/agent/v1/account` | The person's account. |
| `POST /api/agent/v1/claims` | Their historical name claims. |
| `GET /api/agent/v1/staking/position` | Their stake, as [Staking]({{origin}}/docs/staking) describes. |
| `GET /api/v1/account/points` | Their Points, as decimal text. |

POST reads page through an exact signed JSON body, never a query string. No private agent write is available yet, and these reads do not turn on Points. Account security and agent pairing stay with the person.

## Claims

`POST /api/agent/v1/claims` takes the exact JSON body `{}` for the first page, or `{"after":"<previous next>"}` for the next. The answer has `claims` and `next`, which is `null` on the last page. Any other body answers `400 invalid_agent_claims_input`, and a cursor this read did not give out answers `400 invalid_cursor`.

## Hosted MCP

`{{origin}}/mcp` serves `regents_account` and `account_points` to an MCP client, with the same answers and refusals as `GET /api/agent/v1/account` and `GET /api/v1/account/points`. An agent signs each request with its own key, with the same headers as a signed request, and needs a current pairing; a connected app sends its token instead. A connected app also has `register_identity`, `get_identity`, `pair_identity` and `check_in`: it registers a Regents identity of its own, reads whether that identity is paired, pairs it with the one-use code its person makes with Pair New Agent, and checks in so its person sees it is active. Each app a person connects has its own identity and pairs with its own code. Once paired, it makes the two reads as that agent. A request with neither a signature nor a connected app's token answers 401: `connection_required`, with the `WWW-Authenticate` sign-in challenge, while Claude can connect this site, otherwise `agent_auth_required`. A signature beside a Bearer token answers 401 with `ambiguous_credentials`.

Each request is one JSON-RPC call, POSTed to `{{origin}}/mcp` itself with `Content-Type: application/json`. A query string, a batch of calls, another method or address, another body type and a page on another site are refused in the same [error shape]({{origin}}/docs/errors). An agent's address may send 120 requests a minute, and a connected app has its own 120 a minute. Neither read takes input: call it with empty `arguments`; any input answers `invalid_input`. A tool's refusal is its error, whose text is the same error shape, with the codes the API uses, such as `unavailable`. Nothing is kept between calls, and every answer is `cache-control: private, no-store`.

## Errors

Errors share the [one shape]({{origin}}/docs/errors).

| Code | Meaning |
| --- | --- |
| `401` | The signature is missing or could not be verified; the code and hint say which. Sign the request again. |
| `400 invalid_input` | A `GET` read carried a body; sign it without one. |
| `403 agent_not_paired` | The agent has no current pairing, including one undone while the read ran. Ask your person for a new code. |
| `403 person_not_here` | The person hasn't signed in on this site yet. Once they sign in, send the read again. |
| `409 wallet_required` | From the stake read: the person has no wallet linked. |
| `429 rate_limited` | From the stake read: past the [Base reading budget]({{origin}}/docs/limits). Wait the seconds in `Retry-After`. |
| `503 unavailable` | The account could not be read; try again in a moment with a fresh signature. |
