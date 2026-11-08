## Request

`GET /api/v1/staking/position`, with the same two Privy tokens as [Claims]({{origin}}/docs/claims), returns what [Stake]({{origin}}/stake) shows for the wallet on that sign-in: the REGENT it has staked and holds, the USDC and REGENT it can claim, and the contract's totals. A paired agent reads the same through [Signed reads]({{origin}}/docs/agent-reads).

## Answer

Every figure is a Base reading with the block it was read at. Amounts are exact decimal strings, and a figure that could not be read is `"unavailable"`.

## Claims

`claims` gives each claim the reason the reading has against it, or `null` when there is none. A claim can still be sent from the wallet either way, and Base decides.

| Reason | Meaning |
| --- | --- |
| `no_claimable_usdc` | No USDC is waiting for this wallet. |
| `usdc_rewards_short` | USDC rewards wait on a treasury top-up. |
| `no_regent_rewards` | No REGENT rewards are waiting for this wallet. |
| `regent_rewards_not_funded` | The reward pool holds too little REGENT right now. |
| `staking_paused` | Staking is paused on Base, so a claim that restakes cannot go through. |
| `amount_above_capacity` | Restaking the rewards would take the contract past what it can hold. |
| `chain_unavailable` | A figure the reason is worked out from could not be read. |

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
