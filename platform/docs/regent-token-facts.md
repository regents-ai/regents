# $REGENT page facts

The public `/regent` page states facts from one place:
`lib/ash_platform_web/regent_token_content.ex`. Nothing on the page is fetched at
request time. Every figure was checked against the public sources below on the
date the module's `reviewed_at/0` names, and the page prints that date beside the
holder table and in the sources disclosure.

This file records where each fact came from so the next review can repeat the
check rather than trust the last one.

## Reviewed

2026-09-07 04:30:28 UTC, by the Regents chief of staff, from the public Base
sources listed under each heading. The reviewed record the module was copied
from lives outside this repository in the Regent workspace artifacts.

## Token

| Fact | Value | Source |
| --- | --- | --- |
| Contract | `0x6f89bcA4eA5931EdFCB09786267b251DeE752b07` on Base (chain id 8453), 18 decimals | Blockscout token page |
| Genesis supply | 100,000,000,000 REGENT, fixed | Launch transaction input |
| Launch | tx `0x5fb374b1cb93e6ca9d02f729cb58a9d5312f003050cbcdcbc8320070a4946ffa`, block 37,827,760, 2025-11-06 16:01:07 UTC | Blockscout transaction page and the Clanker launch record |

## Genesis allocation

What the launch transaction did, in launch order. This is not a statement of
current balances.

| Share | Tokens | Destination |
| --- | --- | --- |
| 20% | 20,000,000,000 | Uniswap v4 liquidity |
| 40% | 40,000,000,000 | Regents Labs, through the launch airdrop mechanism |
| 40% | 40,000,000,000 | Clanker vault contract |

The original policy Regents Labs published for these shares was four 10% Labs
buckets (Animata program; agent-coin fee rewards; protocol growth and agent API
support; ecosystem fund) and two 20% vault buckets (treasury; sovereign-agent
incentives). The page labels this as policy: no contract enforces the buckets,
no vault rule enforces a holder quorum, and the buckets do not describe the
Safe's current balance.

## Vault release

Read from the verified vault source and the decoded launch input.

| Boundary | Moment (UTC) | Cumulative eligible |
| --- | --- | --- |
| Funded | 2025-11-06 16:01:07 | 0 |
| Lock ends, linear vest starts | 2026-11-06 16:01:07 | 0 |
| Midway | 2027-11-06 16:01:07 | 20,000,000,000 |
| Fully vested | 2028-11-05 16:01:07 | 40,000,000,000 |

Lock 31,536,000 seconds; vest 63,072,000 seconds. Vault contract
`0x8E845EAd15737bF71904A30BdDD3aEE76d6ADF6C`. Anyone can trigger a claim; the
tokens go to the vault's allocation admin, which can change. Eligibility to
claim is not a claim, a sale or circulation, and the page says so.

## Treasury

Safe `0x9fa152B0EAdbFe9A7c5C0a8e1D11784f22669a3e` on Base, version 1.4.1+L2.
Owner-signing threshold was 2 of 3 when checked, with owners
`0x8C172cA4b5Dd9449217C636A953727eACD690e37`,
`0x978BDbECb54C54800D01055Df5A8f6af600BfaCe` and
`0x1d0dcABAeb941823E51935F795Be184aBeBf76dF`. Signers are shown as addresses,
never as named people. The Safe balance is separate from the time-locked vault
allocation; the page does not say treasury holdings are locked. Source: Safe
transaction service, via the Safe app link on the page.

## Holders

Blockscout indexed balances at the reviewed moment, stored as exact token
amounts (atomic balance over 10^18). Not a live reading and not pinned to one
RPC block. Percentages divide by the 100 billion genesis supply and are shown
to one decimal, never rounded up.

| Holder | Address | Tokens |
| --- | --- | --- |
| Clanker vault | `0x8E845EAd15737bF71904A30BdDD3aEE76d6ADF6C` | 40000000000 |
| Regents Labs Treasury | `0x9fa152B0EAdbFe9A7c5C0a8e1D11784f22669a3e` | 14796504503.504863237545574501 |
| REGENT staking contract | `0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5` | 12601015521.393597867938800072 |
| Uniswap v4 PoolManager | `0x498581fF718922c3f8e6A244956aF099B2652b2b` | 11370610519.952098010140379445 |
| Token launch administrator | `0x0cb27e883E207905AD2A94F9B6eF0C7A99223C37` | 7034023608.342838907856226374 |
| Animata redemption contract | `0x71065b775a590c43933F10c0055dc7d74AfAbb0e` | 2859857607.163533118952566772 |

Descriptions on the page keep three distinctions: the staking balance includes
customers' principal and funded reward inventory, so the whole is neither
treasury nor available rewards; the PoolManager is a shared contract for many
pools, not one wallet; the launch administrator is separate from the Treasury
Safe.

## Staking and redemption

Staking (`0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5`): USDC is shared only as
it is actually deposited; shares are worked out against the fixed 100 billion
supply with the unstaked residual going to the treasury; REGENT rewards come
from separately funded inventory at an owner-set rate capped at 20% a year. The
page claims no guaranteed return, no buyback, no first-year deadline and no
statement that all product revenue already reaches staking.

Redemption (`0x71065b775a590c43933F10c0055dc7d74AfAbb0e`): 5,000,000 REGENT for
80 USDC, vesting over 604,800 seconds (seven days). Separate from the vault.

## Updating

1. Re-check every value above against its public source and note the moment.
2. Change the values and `@reviewed_at` in `regent_token_content.ex`, then this
   file, in the same commit.
3. Run the focused page tests and the route handoff check. Balances, the
   treasury threshold and the allocation admin are the values most likely to
   have moved; the schedule boundaries and genesis split do not change.
