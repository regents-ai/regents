---
title: Techtree Formal & Cryptographic Conformance Verification
pillar: security
estimated_cost: $0.00 (Read-Only Spec & Playbook)
protocols: lean4, tls1.3, ml-kem, ml-dsa, conformance
services: Techtree, Patchbay
summary: Verify AI-assisted cryptographic claims and protocol migrations inside sealed, deterministic harnesses—checking Lean 4 proof terms against pinned axioms and running reproducible TLS downgrade conformance suites.
---

## Objective

When AI systems produce new complexity-theoretic claims, cryptographic optimizations, or protocol refactors, prose explanations and screenshots are never sufficient evidence. Use Techtree's sealed verifier model together with Patchbay's deterministic probes to separate machine-checked proof and live wire behavior from unverified claims.

## Agent Prompt

```text
Prepare a formal and conformance verification bundle for a cryptographic change or mathematical claim:

1. Classify the claim first:
   - Mathematical / proof claim (e.g., asymptotic bound or reduction): require a machine-checkable Lean 4 package (`lakefile.toml` + `lean-toolchain`) with explicit `#print axioms` audit so conditional assumptions (such as ETH refutation hypotheses) cannot hide as unstated axioms.
   - Protocol / implementation change (e.g., TLS hybrid PQ rollout or SIWA v3 verifier): require a deterministic conformance suite checking positive negotiation, PQ ClientHello middlebox tolerance, forced TLS 1.2 classical downgrade rejection, and invalid-signature refusal.
2. Run Patchbay's before/after checks to capture reproducible evidence:
   - `patchbay_probe_crypto` before and after deployment, verifying `downgrade.status == "tls_1_3_enforced"` where policy requires TLS 1.3 minimum.
   - `patchbay_diff_crypto` on before/after lockfiles or probe reports to generate a signed `receipt_digest`.
   - `patchbay_check_authority` on any Safe or on-chain treasury touched by the release.
3. Package the sealed Techtree proof artifact (`schema_version: techtree.model-climb.proof.v1alpha1` pattern) so any independent verifier can replay the check offline and publish the result to Patchbay.
```

## Included Checks

- `POST /api/v1/patchbay/security/probe-crypto` — Live TLS 1.3 hybrid PQ, middlebox intolerance, and forced TLS 1.2 downgrade probe.
- `POST /api/v1/patchbay/security/diff-crypto` — Deterministic before/after migration diff receipt for lockfiles and probe reports.
- `POST /api/v1/patchbay/security/check-authority` — On-chain Safe/treasury "embedded firmware" exposure inventory.
- `docs/techtree-formal-conformance-lane.md` — Planned Techtree sealed verifier lane for Lean 4 proof terms and TLS downgrade conformance suites.
