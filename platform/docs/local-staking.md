# Local REGENT staking verification

This page explains how to verify the admitted `/stake` capability locally. It does not require
or authorize a production deployment, database migration, or automated live transaction.

## Automated proof

From `ash-platform/`:

```sh
mix test test/ash_platform/staking test/ash_platform_web/stake_live_test.exs
npm test -- --run assets/test/stake_wallet.test.ts assets/test/privy_bridge.test.ts
npx playwright test test/browser/stake.spec.ts
```

The browser test uses an in-memory wallet provider and test-only chain boundary. It simulates an
exact REGENT approval and stake, returns deterministic successful receipts, confirms through the
Ash staking boundary, and refreshes the position. It never contacts a wallet or sends a live
transaction.

## Manual local check

1. Complete the local Privy setup in [`local-privy-auth.md`](local-privy-auth.md).
2. Install the locked dependencies with `mix deps.get` and `npm install`.
3. Start the app with `ASH_PLATFORM_LOCAL_DB=1 mix phx.server`. When `BASE_READ_RPC_URL` is set,
   local Stake and Redeem read that same Base endpoint production reads; startup names only its
   host, never the key-bearing address itself.
4. Open `http://localhost:4000/stake` and sign in with the Privy account whose embedded wallet you
   intend to use.
5. Confirm the page shows Base, the deployed staking contract, your REGENT balance, your current
   stake, and your available USDC and REGENT rewards.
6. Choose one action and review the exact amount, recipient, contract, network, and risk text.
7. Only if you intentionally want to make a Base mainnet transaction, choose **Confirm in wallet**
   and review every wallet prompt. A stake may require one exact REGENT approval followed by the
   staking transaction.

The server only prepares and verifies actions. The connected wallet signs. The page reports
success only after a successful Base receipt is independently verified and the onchain position is
read again.

## Supported actions

- Stake REGENT to the connected wallet's own position.
- Unstake REGENT back to that same wallet.
- Claim all available USDC rewards.
- Claim all available REGENT rewards.
- Manually claim and restake available REGENT rewards.

There is no automatic restaking, stake-for-another flow, operator treasury action, or ENS recipient
resolution in this capability.

## Dependency and audit note

The implementation locks viem `2.55.0` and Req `0.6.2`, the latest stable releases observed on
2026-07-11. `mix hex.outdated` reports the Elixir dependencies current. The fixed WebSocket 8.21.0
override removes the prior high-severity transitive findings. Ten moderate `uuid` findings remain
under Privy’s MetaMask/Wagmi dependency path; npm’s forced remediation would downgrade Privy.
