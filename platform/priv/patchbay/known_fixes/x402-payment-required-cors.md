---
title: x402 PAYMENT-REQUIRED header invisible in browser or malformed v2 schema
kind: fix
sites: regents.sh, coinbase.com, exa.ai
tools: x402 v2 HTTP 402 endpoints, /patchbay/validate
checked: 2026-11-24
---

## Applies when

- A browser agent or fetch client receives HTTP 402 from an x402 endpoint, but `response.headers.get("PAYMENT-REQUIRED")` returns `null` despite the header appearing in curl or network DevTools.
- `patchbay_validate_endpoint` reports a missing `Access-Control-Expose-Headers` entry or invalid `x402Version` / `accepts[]` fields.
- An x402 endpoint fails Bazaar / Agentic Market discovery indexing because the route uses a wildcard path (`/*`) or omits `extensions.bazaar.discoverable: true`.

## Does not apply when

- The HTTP 402 challenge is an MPP `WWW-Authenticate: Payment` header with no x402 terms. See `mpp-tempo-www-authenticate-and-session`.
- The 402 returned valid terms and signing succeeded, but settlement was rejected by the facilitator. See `x402-eip3009-nonce-and-facilitator`.

## Steps

1. Run `POST https://regents.sh/api/v1/patchbay/validate` (or open `/patchbay/validate`) against the failing URL and HTTP method to inspect the raw `PAYMENT-REQUIRED` header and CORS response headers.
2. On the resource server, include `Access-Control-Expose-Headers: PAYMENT-REQUIRED, PAYMENT-RESPONSE, X-PAYMENT-RESPONSE` on both `402` and `200` responses so browser agents can read the payment challenge and settlement receipt.
3. Confirm the decoded `PAYMENT-REQUIRED` JSON sets `x402Version: 2`, uses CAIP-2 network identifiers (`eip155:8453` for Base mainnet), specifies atomic string amounts (`maxAmountRequired`), and provides checksummed `payTo` and `asset` addresses.
4. For Bazaar / directory indexing, declare explicit parameterized routes (e.g. `GET /weather/:city`, not `GET /weather/*`), include `extensions.bazaar.discoverable: true` with `inputSchema` and `outputSchema`, and complete at least one real settled payment through the facilitator.

## Caveats

Never downgrade verification to skip signature or amount checks when debugging CORS; CORS headers only control browser header visibility, never payment authorization.

## Sources

https://regents.sh/patchbay/validate; https://docs.cdp.coinbase.com/x402/welcome; https://agentic.market/llms.txt
