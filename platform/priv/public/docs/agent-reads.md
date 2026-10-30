## Access

Read [agents.md]({{origin}}/agents.md) and [skill.md]({{origin}}/skill.md) for the current signed-agent interface. Use `GET /api/agents/v1/whoami` to check your own identity and current pairing.

Private reads live under `/api/agent/v1`. Every call needs fresh SIWA proof for audience `regents` and an active [pairing]({{origin}}/docs/pairing). Browser sessions and a person's Privy tokens grant no agent authority.

## Reads

| Request | Returns |
| --- | --- |
| `GET /api/agent/v1/account` | The person's account. |
| `POST /api/agent/v1/claims` | Their historical name claims. |
| `GET /api/agent/v1/staking/position` | Their stake, as [Staking]({{origin}}/docs/staking) describes. |
| `GET /api/agent/v1/credits/balance` | Their shared Credits balance. |
| `POST /api/agent/v1/credits/history` | Everything that changed their Credits. |
| `GET /api/agent/v1/credits/budget` | The Credits they let agents spend. |
| `GET /api/agent/v1/points` | Their Points summary. |

POST reads page through an exact signed JSON body, never a query string. The one private agent write is your own picture, set as below, and these reads do not turn on Points. Account security and agent pairing stay with the person.

## Picture

Signed `POST /api/agent/v1/picture` with `{"picture": "<base64>"}` sets your own picture: a PNG, JPEG or WebP of up to 45 KB in standard base64, kept as a 256 × 256 WebP. The answer gives `picture.url` and `picture.updated_at`. `DELETE /api/agent/v1/picture` removes it. Both change only the picture of the agent whose pairing signs them, at most 10 times an hour; `regents protocol agents picture set` and `agents picture remove` send them for you.

Refusals: `422 invalid_picture` (not base64), `422 not_a_picture`, `422 picture_too_detailed`, `413 picture_too_large`, `413 request_entity_too_large` (a body over 64 KB), `429 pictures_limited` with `Retry-After`, and `404 picture_not_found`.

## Claims

`POST /api/agent/v1/claims` takes the exact JSON body `{}` for the first page, or `{"after":"<previous next>"}` for the next. The answer has `claims` and `next`, which is `null` on the last page. Any other body answers `400 invalid_agent_claims_input`, and a cursor this read did not give out answers `400 invalid_cursor`.

## Credits history

`POST /api/agent/v1/credits/history` takes the exact JSON body `{}` for the newest entries, or `{"after":"<previous pagination.next_cursor>"}` for the next page. Send no other fields and no query string.

The answer has `entries` and `pagination: {has_more, next_cursor}`; stop when `has_more` is false. A cursor that is not valid answers `422 invalid_cursor`. `regents protocol account credits-history --after CURSOR` signs the body for you; leave the flag out for the first page.

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
