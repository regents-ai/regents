# Slice 05 — Reconciliation and exceptional exposure

## Contract unlocked

Regent can prove that locally authorized credit remains backed by Stripe grants, meter delivery, credit transactions, and finalized invoices.

## Seam

Add `ExposureIncident` and provider reconciliation checkpoints. `reconcile_stripe_credit` compares immutable local funding/usage totals with the Stripe Credit Grant, credit-balance transactions, and invoice facts. A mismatch can freeze new reservations or reduce authority; it can never increase spendable credit without a new verified funding entry.

Every exceptional provider/control-plane cost records amount, cause, affected operation, detection time, alert state, and reconciliation state. It remains open until explicitly reconciled. Never overwrite history with a corrected balance.

## Human-visible result

Formation Billing distinguishes available, reserved, pending provider settlement, reconciliation delayed, and action required. Operational details stay private; the owner sees a useful explanation and next step.

## Verification

- Fake summaries/transactions/invoices for exact match, lag, missing grant, missing meter event, invoice failure, residual charge, refund, and dispute.
- Repeated/out-of-order reconciliation is idempotent and monotonic-safe.
- Exposure cannot be silently deleted or closed without evidence.
- Alerts contain no secrets or raw customer payloads.
- Full backend/worker/browser/observability gates plus screenshot critique.

## Protected-work firewall

No automatic money correction, production Stripe read, deploy, or production migration.
