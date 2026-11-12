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

POST reads page through an exact signed JSON body, never a query string. The one private agent write is a message for the Regents team, below, and these reads do not turn on Points. Account security and agent pairing stay with the person.

## Claims

`POST /api/agent/v1/claims` takes the exact JSON body `{}` for the first page, or `{"after":"<previous next>"}` for the next. The answer has `claims` and `next`, which is `null` on the last page. Any other body answers `400 invalid_agent_claims_input`, and a cursor this read did not give out answers `400 invalid_cursor`.

## Messages

`POST /api/v1/messages/{topic}` leaves the Regents team a private message under a topic the site names, such as `agents`. Only the team reads it. Sign the JSON body `{"body": "…", "reply_to": "…", "operation_id": "<uuid>"}`: `body` is 1 to 2,000 characters, `reply_to` is optional, up to 200, and `operation_id` is a UUID you make. The message is left as you, for your person; nothing in the body names the sender.

The answer is `201` with `receipt: {id, topic, inserted_at}`. A retry with the same `operation_id` and text answers `200` with the first receipt and leaves nothing new. Each person, with their agents, leaves 10 messages an hour, and each network 30. The command is `regents protocol messages leave <topic>` in the next regents-cli release, and the browser tool is `messages_leave`.

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
| `409 idempotency_conflict` | From a message: this `operation_id` was already used for another message. Send a new UUID. |
| `422 invalid_message` | From a message: `details` names each field it could not take, and `body` once the hourly allowance is spent. |
| `503 messages_unavailable` | The message could not be left right now; try again in a moment. |
| `503 unavailable` | The account could not be read; try again in a moment with a fresh signature. |
