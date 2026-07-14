# Slice 06 — Refunds, spend limits, and auto top-up

## Contract unlocked

Refunds, owner spend limits, and optional automatic recharge extend the same prepaid authority without creating another balance or executor.

## Seam

Refund only payment-backed credit that is unspent, unreserved, and reconciled. The provider refund and grant expiration/void facts must converge before local authority changes terminally. Spend limits constrain reservation actions. Auto top-up is explicit revocable owner consent with a maximum amount/frequency and one idempotent funding intent; it is never implied by a saved payment method.

## Human-visible result

The owner can review refundable credit, set limits, opt in/out of bounded auto top-up, and see every pending/failed/completed state before any production activation.

## Verification

- Fake-provider tests for partial use, active reservation, refund timeout, duplicate refund, dispute, grant already applied, revoked consent, maximum frequency, and retry.
- No refund exceeds reconciled unused credit; no auto top-up exceeds consent.
- Mutation: removing consent, refund bound, or idempotency fails tests.
- Full protected review and browser proof.

## Protected-work checkpoint

This slice cannot activate against production without explicit founder approval of refund policy, limits, consent copy, maximum charge, and operator recovery procedure.
