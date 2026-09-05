# Regents CLI Release Audit — 2026-04-14

## Scope

- Repository: `regents-cli`
- Focus areas: CLI release health, API contract alignment, and EVM transaction handoff paths for staking and prepared writes.
- Methods used:
  - Static code review of command handlers, generated OpenAPI bindings, and contract files.
  - Validation runs: build, typecheck, tests, and pack smoke.

## Executive assessment

Status at the time of this audit: **Not release-ready**.

This document is retained as historical release evidence. It is not the current release checklist.

There is at least one **release-blocking logic issue** in the `regent-staking` EVM submit path and one **critical contract/code drift** that can silently disable submission depending on backend envelope shape.

## Major findings

### 1) Contract drift can disable `--submit` for `regent-staking` claim flows (Release blocker)

`printPreparedOrSubmitted` reads `payload.tx_request` at the top level.

However, the shared services contract and generated types define prepared transaction payload as:

- top-level: `{ ok: true, data?: PreparedAction }`
- nested: `data.tx_request`

If the backend follows the contract shape (`data.tx_request`), CLI submit mode will no-op (print only), because `payload.tx_request` is absent.

Impact:

- `regents regent-staking claim-usdc --submit`
- `regents regent-staking claim-regent --submit`
- `regents regent-staking claim-and-restake-regent --submit`

can fail to submit while appearing successful in JSON output.

### 2) `regent-staking` submit path hardcodes Base and ignores `tx_request.chain_id` (Release blocker)

In `submitPreparedBaseTx`, the chain is always `base` and there is no guard comparing any contract-provided `tx_request.chain_id` value.

Impact:

- If backend/contract payloads ever return a non-Base chain id (or misconfiguration leaks wrong chain), CLI can attempt submission on the wrong chain transport.
- This is especially risky for EVM release quality because chain mismatch can produce failed or unintended transactions.

## Secondary findings

### 3) Tests currently reinforce the top-level `tx_request` shape

`regent-staking` tests mock and assert top-level `tx_request`. This means current tests do not protect against contract-conformant (`data.tx_request`) payloads and will not detect the drift above.

## Validation run summary

- `pnpm build` ✅
- `pnpm typecheck` ✅
- `pnpm test` ✅
- `pnpm check:openapi` ⚠️ fails in this environment because codegen snapshots `origin/main` OpenAPI files from sibling repositories (`../techtree`, `../autolaunch`) that are not present here.
- `pnpm test:pack-smoke` ⚠️ failed in this environment during package install in temporary workspace (environmental packaging/install step issue), while core unit/integration tests passed.

## Release recommendation

**Hold release** until:

1. `regent-staking` submit handling uses the current shared-services envelope (`data.tx_request`).
2. `regent-staking` submit validates/uses `tx_request.chain_id` before sending.
3. Tests include contract-conformant prepared response fixtures.
4. Full openapi and pack-smoke validations pass in a fully provisioned release environment.
