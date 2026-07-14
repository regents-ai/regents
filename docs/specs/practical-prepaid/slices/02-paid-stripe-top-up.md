# Slice 02 — Paid Stripe top-up

## Contract unlocked

A signed-in owner can request a Stripe-hosted USD top-up; local credit appears only after Stripe proves payment and a matching Billing Credit grant exists.

## Seam

Start with a new owning OpenAPI contract for the browser top-up and Stripe webhook endpoints. Then add `FundingIntent` and `ProviderEvent` resources, a narrow `StripeBillingProvider` behaviour, a Req implementation, a deterministic fake, controllers, and the Formation Billing UI.

The provider creates one-time Checkout, retrieves the completed Session and PaymentIntent, creates a Stripe Billing Credit grant with a stable idempotency key, and retrieves the resulting credit balance. Fulfilment requires a verified webhook plus authoritative retrieval proving: expected customer, `livemode`, USD currency, exact amount, paid Session, succeeded PaymentIntent, and the expected local funding intent. Duplicate/out-of-order events converge. Credit enters Slice 01 only after payment and grant both exist.

## Human-visible result

In Stripe sandbox configuration, the owner can choose an allowed amount, leave for hosted Checkout, return, and see `pending`, `funded`, or an honest retryable failure. No UI says funded from a redirect alone.

## Verification

- Contract-first source/mirror validation for every HTTP route and error shape.
- Fake-provider tests: unpaid, delayed, wrong owner/customer/currency/amount/mode, duplicate event, grant timeout, remote grant plus local crash, refund/dispute, and replay.
- Verify raw-body webhook signature and store only minimal event facts plus payload hash.
- Stable Stripe idempotency keys must make API-success/DB-failure converge on retry.
- Mutation: removing payment retrieval, grant proof, webhook dedupe, or owner binding fails tests.
- One explicitly approved TEST-sandbox probe may follow fake-provider convergence; never production.

## Protected-work checkpoint

Before any sandbox probe, surface the exact current Stripe API version, Checkout request, allowed amounts, test customer/grant destination, and maximum possible charge. Production enablement is a later explicit decision.
