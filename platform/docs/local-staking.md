# Local REGENT staking verification

This page explains how to verify the admitted `/stake` capability locally. It does not require
or authorize a production deployment, database migration, or automated live transaction.

## Automated proof

From `repos/regents/platform/` in an isolated prepared worktree:

```sh
mix test test/regents/staking test/regents_web/stake_live_test.exs
npm test -- --run assets/test/stake_steps.test.ts assets/test/privy_bridge.test.ts
npx playwright test test/browser/stake.spec.ts
```

The browser test uses an in-memory wallet provider and a test-only chain boundary. It presses an
unlimited REGENT approval and stake, checks the wallet received exactly the steps the server built, and
reads their outcome back through the same stand-in chain. It never contacts a wallet or sends a live
transaction.

## Manual local check

1. Complete the local Privy setup in [`local-privy-auth.md`](local-privy-auth.md).
2. Install the locked dependencies with `mix deps.get` and `npm install`.
3. Start the app with `mix phx.server`. When `BASE_READ_RPC_URL` is set,
   local Stake and Redeem read that same Base endpoint production reads; startup names only its
   host, never the key-bearing address itself.
4. Open `http://localhost:4000/stake` and sign in with the Privy account whose embedded wallet you
   intend to use.
5. Confirm the page shows Base, the deployed staking contract, your REGENT balance, your current
   stake, and your available USDC and REGENT rewards.
6. Choose one action and review the exact amount, recipient, contract, network, and risk text.
7. Only if you intentionally want to make a Base mainnet transaction, press the action and review
   every wallet prompt. A stake may need a one-time, unlimited REGENT approval first: the button reads
   **Approve REGENT** until the approval is sent, then **Stake REGENT**.

The server builds every wallet step (the `regent_chain` package from `elixir-utils/chain`) and
pushes them to the page before anyone presses. Signed in, every figure and every step is for the
account's main wallet, the one the account menu shows, and the button only sends the step it names
from that wallet. When the browser has the main wallet connected it is made the active one, even if
the wallet app had another open. When it is not connected, or another wallet is open, a press sends
nothing, names the wallet to switch to and opens the connect window; no other linked wallet ever
takes its place. Signed out, the figures follow whichever wallet is open, and a press opens sign-in. The server then reads the transaction on Base at the latest
block every quarter second, checks it is exactly the step it built, and says whether it went through.
A confirmed step reads the wallet's position and the shared totals again.

## Supported actions

- Stake REGENT to the connected wallet or an explicitly acknowledged receiving address.
- Unstake REGENT back to that same wallet.
- Claim all available USDC rewards.
- Claim all available REGENT rewards.
- Manually claim and restake available REGENT rewards.

Ticking **For a different address** opens a window with a plain Ethereum address input. The warning must be checked for that exact address. Editing the address, switching modes, or changing the connected wallet clears that acknowledgment. The payer supplies REGENT and signs the approval and stake; the receiving address owns the stake and future rewards. Only transactions from that receiving address can withdraw its stake or claim its rewards. A contract wallet must be able to call those functions.

No automatic restaking, operator treasury action or ENS recipient resolution is included.

## Dependency and audit note

The implementation locks viem `2.55.0` and Req `0.6.2`, the latest stable releases observed on
2026-07-11. `mix hex.outdated` reports the Elixir dependencies current. The fixed WebSocket 8.21.0
override removes the prior high-severity transitive findings. Ten moderate `uuid` findings remain
under Privy’s MetaMask/Wagmi dependency path; npm’s forced remediation would downgrade Privy.
