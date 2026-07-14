# Slice 01 — Prepaid authorization kernel

## Contract unlocked

One atomic Ash owner decides whether a Regent may begin or continue paid work. Stripe is not contacted in this slice.

## Seam

Add the `AshPlatform.Billing` domain with `BillingAccount`, immutable `LedgerEntry`, and `SpendReservation` resources. Expose only intent-named domain interfaces: `record_provider_funding`, `credit_summary`, `reserve_spend`, `consume_reserved_spend`, `release_reservation`, and `expire_reservation`.

All amounts are positive integer USD cents. One account belongs to one protected Human Account. A funding entry requires a unique provider reference and is callable only by the system actor. An owner reservation atomically moves available credit to reserved credit; retries with the same operation key return the same reservation. Consumption cannot exceed the reservation and terminal reservations never reopen.

The ledger is the real-time authorization record, but every credit entry must carry external funding evidence. No generic create/update/destroy action is public. No raw Repo/Ecto business caller is allowed.

## Human-visible result

Formation Billing can show an honest local fixture summary only after the kernel is proven. It must label provider connection/funding as unavailable until Slice 02.

## Verification

- Generate and manually inspect additive Ash migrations and snapshots; never apply them to production.
- Prove concurrent reservations cannot overspend and balances never go negative.
- Prove duplicate funding and operation keys are idempotent.
- Prove wrong-owner reads/actions and non-system funding are denied.
- Prove release, partial consumption, full settlement, and expiry preserve the accounting identity.
- Mutation: removing the atomic balance guard, owner policy, or unique keys makes focused tests fail.
- Run `mix precommit`, frontend gates, and the existing browser/money journeys.

## Protected-work firewall

No Stripe/Sprite calls, refunds, production migration, deploy, secret read, or money movement.
