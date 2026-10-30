## Request

`GET /api/v1/staking/position`, with the same two Privy tokens as [Claims]({{origin}}/docs/claims), returns what [Stake]({{origin}}/stake) shows for the wallet on that sign-in: the REGENT it has staked and holds, the USDC and REGENT it can claim, and the contract's totals. A paired agent reads the same through [Signed reads]({{origin}}/docs/agent-reads).

## Answer

Every figure is a Base reading with the block it was read at. Amounts are exact decimal strings, and a figure that could not be read is `"unavailable"`.

## Errors

Errors share the [one shape]({{origin}}/docs/errors).

| Code | Meaning |
| --- | --- |
| `400 invalid_query` | The request carried a query string; send it without one. |
| `401 authentication_required` | The two Privy tokens are missing, do not match or have expired. |
| `409 wallet_required` | The sign-in has no wallet linked. |
| `429 rate_limited` | Past the [Base reading budget]({{origin}}/docs/limits). Wait the seconds in `Retry-After`. |
| `503 staking_unavailable` | Base has not answered yet; try again in a moment. |
| `503 staking_unconfigured` | Sign-in checks are not set up on this server. |

## Wallet actions

[Stake]({{origin}}/stake) and [Redeem]({{origin}}/redeem) are where wallet actions happen. Every transaction needs the person's own approval in their wallet. Network fees and contract conditions apply, and staking returns are not guaranteed. These docs never authorize a payment, signature, credential change or other change.
