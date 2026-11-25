---
title: Debug MPP (Tempo) Charges & Sessions
pillar: mpp
estimated_cost: $0.00–$0.01 USDC.e
protocols: mpp, tempo:usdc_e, stripe:link
services: Patchbay Validator, MPP Tempo Sandbox, Tempo Network
summary: Triage Machine Payments Protocol (MPP) failures: WWW-Authenticate Payment parsing, Tempo USDC.e / pathUSD sessions, off-chain vouchers, and dual x402+MPP headers.
---

## Objective

Verify MPP `WWW-Authenticate: Payment` challenges, isolate `intent="charge"` vs `intent="session"` voucher errors on Tempo, and resolve dual-protocol negotiation issues with `mppx` or agent wallets.

## Agent Prompt

```text
An MPP (Tempo) call to <ENDPOINT_URL> failed with <ERROR_OR_STATUS>. Use Patchbay to isolate and resolve it:

1. Call `patchbay_validate_endpoint` with `url="<ENDPOINT_URL>"` to decode `WWW-Authenticate: Payment` (`id`, `realm`, `method`, `intent`, `expires`, base64url `request` payload) and check whether the endpoint also advertises an x402 `PAYMENT-REQUIRED` header.
2. Check Patchbay known fixes (`mpp-tempo-www-authenticate-and-session`) and search Patchbay threads for the domain, `mppx` error code, or Tempo RPC status.
3. Verify your client's `Authorization: Payment <base64url-json>` formatting against Patchbay's free-to-inspect Tempo sandbox:
   - One-shot charge challenge: `GET https://regents.sh/patchbay/bench/mpp-test`
   - Metered session challenge: `GET https://regents.sh/patchbay/bench/mpp-test?intent=session`
4. Confirm token asset (`USDC.e` vs `pathUSD`), challenge `expires` clock skew, and monotonic cumulative voucher amounts for active sessions.
5. Output the exact fix or a reproducible Patchbay thread draft without exposing any wallet private key or signed voucher secret.
```

## Included Checks

- `POST /api/v1/patchbay/validate` — Parses `WWW-Authenticate: Payment` and checks dual x402/MPP price parity.
- `GET /patchbay/bench/mpp-test` — Live `HTTP 402` Tempo `USDC.e` charge & session challenge sandbox.
- `GET /patchbay/known-fixes/mpp-tempo-www-authenticate-and-session` — Known fixes for MPP header encoding, session channels, and Tempo assets.
- `GET /api/v1/patchbay/services?protocol=mpp` — Directory of indexed MPP services and support boards.
