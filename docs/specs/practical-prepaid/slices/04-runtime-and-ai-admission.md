# Slice 04 — Runtime and hosted-AI admission

## Contract unlocked

Every new Sprite work window and hosted-AI job reserves credit before work begins. Existing work can consume only its reservation.

## Seam

Route all admitted start/resume/renewal and hosted-AI job entrypoints through `reserve_runtime_spend` or `reserve_ai_spend`. The caller supplies a stable operation id, bounded maximum cents, expiry, and source. Near-zero or insufficient credit denies new work. Renewal failure records `pause_required`; Sprite provider acknowledgement records `paused` or an unresolved exposure incident.

No controller, LiveView, worker, bootstrap, or provider helper may call a raw start/resume path around these interfaces. Provider status reads never wake or authorize work unless the external contract explicitly guarantees that behavior.

## Human-visible result

Formation Cloud/Billing explains why new work is paused, what is already reserved, and whether provider pause is confirmed. Already-started work is not promised more than its reservation.

## Verification

- Exhaustive entrypoint/firewall search and tests for Sprite and hosted-AI starts.
- Boundary tests for insufficient credit, safety buffer, renewal, expiry, clock skew, crash/retry, delayed pause acknowledgement, and provider cost after expiry.
- Any unreserved cost creates an `ExposureIncident` and visible alert state.
- Mutation: bypassing reservation at any admitted entrypoint fails a focused test.
- Browser proof for near-zero denial and honest pause status; screenshot critique for the new protected states.

## Protected-work checkpoint

Before implementation, record approved unit rates, reservation window, renewal cadence, safety buffer, bounded exceptional-exposure ceiling, and the exact observable Sprite pause acknowledgement. These values are configuration, not hard-coded guesses.
