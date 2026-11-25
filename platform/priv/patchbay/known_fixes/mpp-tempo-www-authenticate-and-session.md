---
title: MPP (Tempo) WWW-Authenticate Payment challenge, session voucher, or dual x402 mismatch
kind: fix
sites: regents.sh, tempo.xyz, stripe.com, boundless.sh
tools: MPP HTTP 402 endpoints, mppx, /patchbay/bench/mpp-test, /patchbay/validate
checked: 2026-11-24
---

## Applies when

- An agent calling an MPP endpoint receives `402 Payment Required` with `WWW-Authenticate: Payment ...` and fails to decode `request`, fails session voucher verification, or sends an incompatible `Authorization: Payment` token.
- A dual-protocol server advertises both `PAYMENT-REQUIRED` (x402) and `WWW-Authenticate: Payment` (MPP) and the client picks the wrong rail or hits a Tempo `USDC.e` vs `pathUSD` asset mismatch.

## Does not apply when

- The endpoint only supports x402 v2 and emits no `WWW-Authenticate: Payment` header. See `x402-payment-required-cors`.

## Steps

1. Probe the endpoint via `POST https://regents.sh/api/v1/patchbay/validate` (or `/patchbay/validate`) to decode the `WWW-Authenticate: Payment` attributes (`id`, `realm`, `method`, `intent`, `expires`, and base64url `request` JSON).
2. Confirm `Authorization: Payment <token>` uses standard unpadded base64url JSON encoding (not standard base64 with `+`/`/`/`=` characters) and echoes the exact challenge `id` and `method`.
3. For Tempo `intent="session"` channels: confirm the session deposit covers the cumulative voucher amount, ensure each successive off-chain voucher strictly increases the cumulative spend, and renew the channel before `expires` passes.
4. Verify the Tempo asset contract matches the challenge's `currency` (`USDC.e` vs `pathUSD`) and chain ID (`eip155:4217`).
5. Validate your client's header parser against Patchbay's live Tempo sandbox: `GET https://regents.sh/patchbay/bench/mpp-test` (`charge`) and `GET https://regents.sh/patchbay/bench/mpp-test?intent=session` (`session`).

## Caveats

MPP endpoints should return `Cache-Control: no-store` and `Vary: Authorization` so shared CDNs never cache a `402` challenge or leak paid responses across clients.

## Sources

https://mpp.dev; https://regents.sh/patchbay/validate; platform/lib/regents_web/patchbay/controllers/mpp_test_controller.ex
