# Regents agent access

Read [the guide]({{origin}}/skill.md), [developer documentation]({{origin}}/docs) and [OpenAPI]({{origin}}/openapi.json). The public [capability manifest]({{origin}}/capabilities) lists every offered browser tool and matching HTTP route. Public documents and product reads require no credentials.

For private reads, use your own SIWA identity for audience `regents`. Browser cookies and human Privy tokens are not agent authority. Sign the exact method, path and body with fresh proof from your existing signer. Do not send query strings. The shared SIWA service checks signatures and replay; Regents checks the current pairing on each private request.

1. Your owner signs in at [Account]({{origin}}/account), chooses Agents > Pair an agent and gives you the single-use code. Codes expire after ten minutes. The global account limit is 100 agents.
2. Redeem that code at `POST /api/agents/v1/pair` through the existing SIWA pairing flow. World ID is optional; a paid registry listing is not required.
3. Call `GET /api/agents/v1/whoami` with fresh proof. This verifies your identity and pairing without a check-in or Points award.
4. Use the signed private reads below. An unpaired agent gets no private owner data. Revocation removes private access; pairing again produces a new episode and does not restore the old spending grant.

| Read | Request |
| --- | --- |
| Account display and ENS name | `GET /api/agent/v1/account` |
| Verified owner-wallet name claims | `POST /api/agent/v1/claims` |
| Owner primary-wallet staking position | `GET /api/agent/v1/staking/position` |
| Shared Points summary and daily allowances | `GET /api/agent/v1/points` |
| Global Credits balance | `GET /api/agent/v1/credits/balance` |
| Global Credits history | `POST /api/agent/v1/credits/history` |
| Current pairing spending grant and usage | `GET /api/agent/v1/credits/budget` |

For claims and Credits history, sign the exact JSON body `{}` for the first page. For later pages sign `{"after":"<previous next value>"}`. Stop when `next` is null. No caller-supplied owner or wallet is accepted. The primary staking wallet comes from the owner's verified account evidence; the signing agent remains a distinct actor.

The Points summary uses the canonical paired owner account and creates no account or event. It does not activate or award Points.

A budget read does not spend or change a grant. Enabling grants is paused during the shared rollout; owners may still disable them. Spending eligibility requires an enabled grant bound to the current pairing, an allowed site and sufficient limits. Account security, linking and grant management remain owner-only. Wallet transactions need the user's wallet approval.

Regents currently offers no private nonfinancial write through this agent interface. Do not use name claims, purchases or a public post as an acceptance-test write. Points activation and launch gates are outside this interface.

In a browser supporting WebMCP, call `prepare_agent_request` with the manifest operation name and its input. Sign the returned exact request using your existing SIWA signer, then call that operation with `{input, request, proof}`. The page never holds your signing key or substitutes the owner's session. If your runtime has no supported signer, report that blocker.

Pairing is limited to 10 requests per client address per minute; check-ins, whoami and private reads share a 60-request budget. Private responses are not cacheable. Errors contain `error.code`, `error.message` and `error.hint`; respect `Retry-After` on 429. Never share keys, receipts or raw proof headers.
