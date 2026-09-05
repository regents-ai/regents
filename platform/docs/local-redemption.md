# Local Animata redemption verification

This page explains how to verify `/redeem` locally. The automated path never contacts a wallet or
sends a live transaction. The manual path reads Base mainnet and opens a wallet prompt only after
you explicitly review and choose one action.

## Automated proof

From `ash-platform/`:

```sh
mix test test/ash_platform/redemption test/ash_platform_web/redeem_live_test.exs
npm test -- --run assets/test/redemption_wallet.test.ts assets/test/privy_bridge.test.ts
npx playwright test test/browser/redeem.spec.ts
```

The browser test uses an in-memory wallet provider and deterministic chain boundary. It proves that
NFT approval, exact 80 USDC approval, redemption, and claim are four separate wallet actions. Each
action is simulated, submitted once, independently confirmed, and followed by an onchain-state
refresh. No live transaction is sent.

## Manual local check

1. Complete the guarded local setup in [`local-privy-auth.md`](local-privy-auth.md).
2. Install the locked dependencies with `mix deps.get` and `npm install`.
3. Start the app with `ASH_PLATFORM_LOCAL_DB=1 mix phx.server`.
4. Open `http://localhost:4000/redeem` and sign in with the Privy account whose embedded wallet
   holds the Animata token.
5. Confirm the page shows Base, 80 USDC, 5,000,000 REGENT, seven-day vesting, your USDC balance and
   allowance, and your current claim and vest status.
6. Choose Animata I or II and enter a token ID from 1 through 999. The page should show the owner,
   current collection approval, and mapped Regents Club token when one exists.
7. Choose only the action you intend to take and review the wallet, contract, network, calldata
   effect, and `0 ETH` native value before continuing.

The four actions are intentionally separate:

- **NFT collection approval** allows the verified redeemer to transfer tokens from the selected
  Animata collection. It is a collection-wide approval and remains until revoked.
- **USDC approval** sets the redeemer allowance to exactly 80 USDC. The redeemer contract decides
  whether an allowance is acceptable; the page prepares this approval whenever you ask for it and
  only reports what the last reading from Base found.
- **Redemption** requires the connected wallet to own the selected token, the NFT collection
  approval to be active, at least 80 USDC to be present, and the allowance to equal exactly
  80 USDC.
- **Claim** is always offered. The contract releases whatever REGENT is unlocked at the moment it
  runs; the page only reports the unlocked amount from the last reading from Base.

Only choose **Confirm in wallet** if you intentionally want that Base mainnet transaction. The app
never advances automatically from one action to the next. After a hash is submitted, retrying
verification checks that same hash and never submits another transaction.

## What proves completion

The server prepares a signed, expiring action for the exact connected wallet. The browser verifies
and re-encodes the action from the pinned manifest and ABI, simulates it, and asks that wallet to
sign. The app reports success only after it independently verifies the successful Base receipt and
the exact transaction hash, signer, target, calldata, and zero native value. It then reads the
redemption state again. If that final read is delayed, the transaction remains confirmed and the
page says to refresh rather than inviting a duplicate submission.

The result collection cannot be selected as redemption input. Permit shortcuts, server signing,
automatic action chaining, and OpenSea-dependent eligibility are not part of this flow.
