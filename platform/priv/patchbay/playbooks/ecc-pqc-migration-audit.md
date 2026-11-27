---
title: ECC & Post-Quantum Migration Verification
pillar: security
estimated_cost: $0.00 (Read-Only)
protocols: tls1.3, ml-kem, ml-dsa, cbom, siwa
services: Patchbay, SIWA, Cloak
summary: Inventory ECC dependencies in lockfiles (CycloneDX 1.6 CBOM), probe live TLS endpoints for real hybrid PQ key exchange vs. middlebox failures, and capture before/after verification digests.
---

## Objective

Separate real cryptographic migration from guesswork: map which dependencies rely on ECC or RSA (and which ones live outside your control on L1 chains or hardware roots), prove whether production TLS endpoints actually negotiate hybrid post-quantum key exchange (`X25519MLKEM768`) without breaking proxies, and record verifiable before-and-after receipts.

## Agent Prompt

```text
Run a Patchbay cryptographic readiness audit on our codebase and deployed endpoints:

1. Read our dependency lockfiles (`mix.lock`, `Cargo.lock`, `package-lock.json`, `uv.lock`, `go.mod`, or `composer.lock`) and call `patchbay_check_crypto` (or `POST https://regents.sh/api/v1/patchbay/security/check-crypto`) to inventory ECC/RSA dependencies and generate a CycloneDX 1.6 CBOM.
2. Separate `boundary: "app_owned"` items we can upgrade now (such as `rustls` on `ring` → `aws-lc-rs`, OpenSSL `< 3.5` → Debian Trixie, Python `cryptography < 50` → `>= 50.0.2`, or ECC-only auth tokens) from `external_chain` / `external_hardware` items that require operational limits or authority inventories.
3. For every public HTTPS endpoint we serve or call, run `patchbay_probe_crypto` (or `POST https://regents.sh/api/v1/patchbay/security/probe-crypto`) to verify:
   - Confidentiality: whether strict `X25519MLKEM768` / `SecP256r1MLKEM768` hybrid key exchange succeeds.
   - Compatibility: whether a hybrid PQ ClientHello causes a middlebox/proxy drop (`pq_client_hello_intolerant`).
   - Authentication: what key and signature algorithm the leaf certificate actually uses.
4. Save the `verification_digest` before and after each migration PR, then call `patchbay_diff_crypto` (`POST https://regents.sh/api/v1/patchbay/security/diff-crypto`) to emit a reproducible `receipt_digest` proving findings were resolved without regressions.
5. For any Safe treasury, proxy upgrade admin, or fleet contract, run `patchbay_check_authority` (`POST https://regents.sh/api/v1/patchbay/security/check-authority`) to separate mutable contract authority from immutable L1 `secp256k1` boundaries and verify unexposed rotation quorum.
```

## Included Checks

- `POST /api/v1/patchbay/security/probe-crypto` — Live SSRF-safe TLS handshake probe proving hybrid PQ KEM support, middlebox tolerance, forced TLS 1.2 downgrade resistance, and leaf certificate signature posture.
- `POST /api/v1/patchbay/security/check-crypto` — Multi-ecosystem lockfile cryptographic inventory and CycloneDX 1.6 CBOM generator.
- `POST /api/v1/patchbay/security/diff-crypto` — Before/after migration diff receipt for lockfile CBOM audits and live TLS probe reports.
- `POST /api/v1/patchbay/security/check-authority` — On-chain Safe/treasury authority exposure inventory ("embedded firmware" check).
- `POST /api/v1/patchbay/security/check-stack` — Join runtime stack checks with live `cve.now` active criticals and CISA KEV advisories.
- `GET /patchbay/validate?tab=crypto` — Interactive browser diagnostics with copyable CycloneDX 1.6 CBOM, Before/After Migration Diff, Authority Exposure Inventory, and prefilled Patchbay failure reporting.
