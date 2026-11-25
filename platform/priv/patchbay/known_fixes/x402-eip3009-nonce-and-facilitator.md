---
title: x402 EIP-3009 authorization rejected, nonce replayed, or settlement timed out
kind: fix
sites: regents.sh, coinbase.com, venice.ai
tools: x402 v2 payment settlement, execute_payment, /patchbay/bench/x402-test
checked: 2026-11-24
---

## Applies when

- An x402 retry carrying `PAYMENT-SIGNATURE` (or `X-PAYMENT`) is rejected with `402` or `409` citing invalid signature, expired `validBefore`, future `validAfter`, nonce replay, or insufficient USDC balance.
- A facilitator `settle` call timed out and the agent is unsure whether USDC moved on Base.

## Does not apply when

- The server did not return a valid `PAYMENT-REQUIRED` header in the first place. See `x402-payment-required-cors`.

## Steps

1. Stop immediately after any settlement timeout: NEVER sign a second EIP-3009 authorization with a new nonce before checking payment status (`get_payment_status` or onchain tx lookup for the original nonce).
2. Verify the signed EIP-712 domain matches the exact asset token contract and chain returned in the challenge (`name: "USD Coin"`, `version: "2"`, `chainId: 8453`, `verifyingContract: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` for Base mainnet USDC).
3. Check clock skew on the signing host: ensure `validAfter` is slightly in the past (e.g. `now - 60s`) and `validBefore` does not exceed the server's `maxTimeoutSeconds`.
4. Confirm the wallet holds enough USDC for the atomic amount on the challenge's exact network (Base ETH is not needed for gasless EIP-3009 facilitator settlement, but Base USDC balance must cover the full transfer).
5. To isolate client-side signing bugs from a third-party server bug, test with operator approval against `GET https://regents.sh/patchbay/bench/x402-test` ($0.01 USDC on Base).

## Caveats

Re-signing on a timeout can cause double-spend if the first facilitator broadcast lands onchain. Always treat a `409` uncertain settlement as an inquiry step, not a retry trigger.

## Sources

https://regents.sh/patchbay/validate; https://regents.sh/patchbay/agent-setup; platform/lib/regents_web/patchbay/plugs/x402_test.ex
