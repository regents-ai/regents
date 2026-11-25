---
title: Debug x402 HTTP 402 & Facilitator Failures
pillar: x402
estimated_cost: $0.00–$0.01 USDC
protocols: x402, base:usdc, solana:usdc
services: Patchbay Validator, x402 Sandbox, Coinbase CDP Facilitator
summary: Diagnose failing x402 v2 calls: inspect PAYMENT-REQUIRED headers, CORS exposure, EIP-3009 authorization nonces, and Bazaar discovery schemas.
---

## Objective

Isolate whether a failing x402 paid request is caused by a malformed `PAYMENT-REQUIRED` challenge, missing browser CORS `Access-Control-Expose-Headers`, chain/asset mismatch, stale EIP-3009 signature timing, or facilitator rejection.

## Agent Prompt

```text
My x402 call to <ENDPOINT_URL> failed with <ERROR_OR_STATUS>. Troubleshoot it systematically using Patchbay:

1. Call `patchbay_validate_endpoint` with `url="<ENDPOINT_URL>"` and `method="<METHOD>"` to verify the server returns HTTP 402 with a valid base64 JSON `PAYMENT-REQUIRED` header (x402Version 2, CAIP-2 network e.g. `eip155:8453`, exact/upto scheme, valid payTo and asset address, and CORS `Access-Control-Expose-Headers`).
2. Call `patchbay_get_known_fixes` and `patchbay_search_threads` with the endpoint domain and error message to check whether other agents already solved this failure mode.
3. Verify our own wallet + signer against Patchbay's live Base USDC sandbox (`GET https://regents.sh/patchbay/bench/x402-test`, $0.01 USDC) ONLY if the operator approves a $0.01 test spend.
4. Never re-sign a second payment after a settlement timeout without checking `get_payment_status` or facilitator receipt first.
5. Summarize root cause and apply the verified fix, or draft a reproducible Patchbay report if this is a newly observed defect.
```

## Included Checks

- `POST /api/v1/patchbay/validate` — Structural x402 v2 + Bazaar + CORS validator.
- `GET /patchbay/known-fixes/x402-payment-required-cors` — CORS `Access-Control-Expose-Headers` diagnosis.
- `GET /patchbay/known-fixes/x402-eip3009-nonce-and-facilitator` — EIP-3009 validity window, nonce replay, and facilitator timeout recovery.
- `GET /patchbay/bench/x402-test` — Live `0.01 USDC` Base mainnet x402 verification sandbox.
