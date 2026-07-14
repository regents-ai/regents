# Practical prepaid for Formation

This design defines the protected prepaid capability described by AP-102 in
`docs/ASH-PLATFORM-DIRECTIVES.md`. It is intentionally greenfield. Old tickets,
ledgers, APIs, and implementations are historical evidence, not contracts to
copy.

Beads epic: `regent-2mf0.24`.

## Outcome

A customer funds one USD prepaid authority through Stripe. Sprite runtime and
hosted AI both reserve against it before work starts. Near zero denies new work
and requires the Sprite to pause. Work already underway may consume only its
reservation. Any exceptional provider cost is visible, alerted, durably
evidenced, and reconciled.

## One owner, two responsibilities

Stripe owns external payment, refund, Billing Credit grant, credit transaction,
meter, and invoice facts. Ash owns the atomic real-time authorization ledger:
funding evidence, available and reserved cents, usage settlement, pause state,
and exceptional exposure.

These are not two spendable balances. Ash may create local credit only from a
verified paid Stripe top-up and matching Billing Credit grant. Provider lag or
failure can delay, reduce, or freeze local authorization; it can never invent
more credit. Stripe's credit summaries remain reconciliation evidence rather
than the admission check because meter events and invoice credit application
are asynchronous.

All monetary amounts are positive integer USD cents. No float, shadow balance,
generic ledger mutation, raw Repo caller, or compatibility layer is allowed.

## Slice graph

1. [`01-prepaid-kernel.md`](slices/01-prepaid-kernel.md) —
   `regent-2mf0.24.1`: provider-free atomic account, ledger, and reservations.
2. [`02-paid-stripe-top-up.md`](slices/02-paid-stripe-top-up.md) —
   `regent-2mf0.24.2`, after `.1`: contract-first Checkout, payment proof, and
   Billing Credit grant.
3. [`03-usage-settlement.md`](slices/03-usage-settlement.md) —
   `regent-2mf0.24.3`, after `.1` and `.2`: exact settlement and durable Stripe
   meter delivery.
4. [`04-runtime-and-ai-admission.md`](slices/04-runtime-and-ai-admission.md) —
   `regent-2mf0.24.5`, after `.1` and `.3`: reserve every Sprite and hosted-AI
   work entrypoint and pause near zero.
5. [`05-reconciliation-and-operations.md`](slices/05-reconciliation-and-operations.md) —
   `regent-2mf0.24.6`, after `.2`, `.3`, and `.5`: reconcile grants, meter
   delivery, transactions, invoices, and exposure.
6. [`06-refunds-limits-and-auto-top-up.md`](slices/06-refunds-limits-and-auto-top-up.md) —
   `regent-2mf0.24.4`, after `.2` and `.6`: bounded refunds, limits, and explicit
   auto-top-up consent through the same authority.

The first playable checkpoint is Slice 01: a deterministic local fixture can
fund, reserve, partially consume, release, expire, and summarize credit without
contacting Stripe or Sprites.

## Canonical interfaces

The eventual `AshPlatform.Billing` domain owns these names:

- `record_provider_funding`
- `credit_summary`
- `reserve_runtime_spend`
- `reserve_ai_spend`
- `consume_reserved_spend`
- `release_reservation`
- `record_exceptional_exposure`
- `reconcile_stripe_credit`
- `request_top_up`
- `refund_unused_credit`

Controllers, LiveViews, workers, runtime helpers, and provider clients consume
these interfaces. None owns a second balance or bypass start/resume path.

## Global invariants

- One Human Account has one billing account and one currency (`usd`).
- Local funding requires unique paid-payment and Stripe grant references.
- One operation key has at most one reservation; retries return it.
- Reservation creation atomically moves available credit to reserved credit.
- Consumption never exceeds the reservation and terminal records never reopen.
- A permanent local meter identifier is reused for every delivery retry.
- Duplicate or out-of-order webhooks cannot duplicate funding or usage.
- External calls occur outside database transactions and use stable provider
  idempotency keys so remote-success/local-failure converges.
- Jobs carry identifiers only and reload current state.
- Provider failure never authorizes work or silently erases exposure.
- Reconciliation never increases authority without new verified funding.

## Firewalls

- Preserve the four protected datasets; every new table is additive.
- Generate and manually inspect Ash migrations; never run them in production
  without explicit approval and recovery evidence.
- No automated live Stripe/Sprite call, production secret, refund, charge,
  deploy, or money movement.
- Any HTTP route starts in its owning OpenAPI YAML before producer/UI changes.
- Billing UI must not imply provider readiness before the corresponding slice
  is proven.
- Production refunds and auto top-up require separate explicit founder consent.

## Known decisions before later slices

Slice 01 has no external decision blocker. Before Slice 04, approve configured
unit rates, reservation window, renewal cadence, safety buffer, maximum
exceptional exposure, and the exact observable Sprite pause acknowledgement.
Before any Stripe sandbox probe, approve the exact API version, request,
customer, permitted amount, and maximum possible charge. These checkpoints do
not block the provider-free kernel.

## Primary external evidence

- [Stripe Billing Credits](https://docs.stripe.com/billing/subscriptions/usage-based/billing-credits)
- [Billing Credits implementation guide](https://docs.stripe.com/billing/subscriptions/usage-based/billing-credits/implementation-guide)
- [Recording Stripe meter usage](https://docs.stripe.com/billing/subscriptions/usage-based/recording-usage-api)
- [Stripe credit balance summary](https://docs.stripe.com/api/billing/credit-balance-summary)
- [Stripe webhook behavior](https://docs.stripe.com/webhooks)

Stripe documents Billing Credits as a preview feature and meter processing as
asynchronous. Production activation therefore remains an explicit protected
decision after sandbox proof.
