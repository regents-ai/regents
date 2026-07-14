# Slice 03 — Usage settlement and Stripe meter delivery

## Contract unlocked

Actual Sprite-runtime or hosted-AI cost settles exactly once against an existing reservation and is delivered durably to Stripe metering.

## Seam

Add immutable `UsageCharge` records tied to one `SpendReservation`. `settle_usage` atomically consumes actual cents, releases unused reserved cents, and writes a permanent meter identifier. A durable job reloads the charge by id and sends the Stripe meter event outside the database transaction. Use current stable Oban only after rechecking the registry and add it as one declared dependency; do not invent an in-memory retry loop.

Stripe processing is asynchronous. Delivery status is evidence (`queued`, `delivered`, `rejected`, `reconciled`), never permission to spend. A Stripe timeout cannot debit twice; a permanent rejection cannot disappear.

## Human-visible result

Formation Billing shows reserved, settled, pending-delivery, and provider-rejected usage without exposing raw traces or provider secrets.

## Verification

- Fake-provider delivery timeout, retry, duplicate, out-of-order acknowledgement, permanent rejection, and delayed processing.
- Concurrent/partial settlement cannot exceed reservation and releases unused credit once.
- Meter identifiers remain locally unique forever and are reused on retry.
- Jobs carry ids/idempotency keys only and reload current state.
- Mutation: removing reservation linkage, terminal-state guard, or meter id reuse fails tests.
- Full Oban worker, Ash, browser, and dependency-current gates.

## Protected-work firewall

No live meter event, invoice finalization, production queue, or production migration.
