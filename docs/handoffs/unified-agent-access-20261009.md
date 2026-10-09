# Regents signed-agent source adoption — 9 October 2026

Done for this source handoff means: adopt the published shared verifier and pairing authority; expose only the agreed private reads; enforce the current pairing and server-resolved owner; publish matching browser, HTTP and CLI descriptions; keep spending grants closed; verify representative flows; preserve the live paper and staking changes; publish source for the coordinator. Deployment and native signing acceptance remain separate gates.

## Source changes

- Shared libraries are pinned to published `elixir-utils` commit `a24d9bf5ce8dbca5852b081613e9e1674623512e`; the Agents dependency now comes from that shared release. Ash is locked to 3.34.6.
- Private account, claims, staking position, Credits balance/history/budget reads use a distinct signed agent actor. The shared verifier checks the request bytes and proof; the server resolves the active pairing and owner. Browser sessions cannot substitute for proof. Staking uses the owner's primary wallet, rather than the agent signer.
- Revocation and re-pairing invalidate actors from the old pairing episode. Ash authorization checks the current episode again. Existing human reads remain available.
- The browser adapter uses the shared signed-request transport. Public guides, `/capabilities`, OpenAPI, `cli/commands.json` and `cli/COMMANDS.md` describe the same routes. Claims/history are signed POST requests with optional `after` in the body. `agents whoami` is a GET read without a body and does not award Points.
- Spending grants remain default-closed through the shared action gate. The account UI explains the pause and permits disabling an existing grant. No grant gate was enabled; no spend or settlement behavior was changed.
- Normal release migration checks the shared pairing/grant prerequisites without modifying shared schemas, then runs only Regents-owned migrations. The coordinator must prepare the shared schemas first.

## Verification

- Strict compilation, scoped formatting, asset build, TypeScript checking and `git diff --check` passed.
- Representative actual-router and Ash checks passed with simulated SIWA verdicts: owner isolation, exact body bytes, pagination, malformed/query/duplicate-proof refusal, account/Credits/staking reads, revocation, re-pairing, stale-actor refusal and no browser-session fallback.
- Shared grant enablement refusal and disabling were checked. The paused component rendered successfully.
- Public guides, capabilities and OpenAPI answered through the router. YAML/JSON parsed, all references resolved, operation IDs were unique and the served YAML matched the canonical contract exactly.
- All nine CLI command descriptors validated against the owning CLI schema and matched their OpenAPI methods, paths and operation IDs.
- The browser adapter registered eleven tools and passed synthetic checks for request preparation, proof enforcement, tamper refusal, omitted browser credentials, redirect refusal and disposal/re-registration.
- Independent security review found no actionable source findings.

The local checks reused `regents_staking_refresh_06_dev` and rolled back transient owners, claims, pairings and grants. The preserved counts were zero users, zero pairings, zero grants and one saved staking reading. No production access, real signature, wallet action, Points activation or spending was performed for this adoption.

Temporary evidence is under `/tmp/regents-agent-*`, including `local-verify-final.log`, `adapter-verify.log`, `contract-verify-final.log`, `assets-final.log`, `typecheck-final.log`, `compile-final.log` and `format-check.log`. These fixtures and generated browser assets are not shipped as source.

## Published contract

Served YAML SHA-256: `82f703a91dedb7912194e909ad40afca3f30e13804c5f1406fba802baf027eab`.

Preserve the CLI platform `protocol`, base URL `https://regents.sh` and signing audience `regents`. Private commands are `agents whoami`, `account show`, `account claims`, `staking position`, `account balances`, `account credits-history` and `account budget`. The two existing pairing commands remain in the descriptor.

## Remaining gates

- The coordinator holds production database changes and deployment for credential handling and native signing acceptance. This handoff publishes source only.
- Native browser signing, real SIWA verification/replay and live cross-site acceptance have not passed in this lane. Synthetic proof headers are not evidence of those checks.
- The owning CLI still needs its coordinated import/release using this published source and contract digest.
- Regents has no agreed private nonfinancial agent write. Do not invent a write to satisfy a generic checklist; the coordinator has accepted this product gap pending Sean's decision.
- Keep spending grants closed and Points settings unchanged until the coordinator's release gate explicitly permits otherwise.

The source retains approved live ancestors `bc1a69a4` (paper folders), `14f694e1` (paper controls) and `2220e11943caf3c6e753fdcc23420a8be5325d7e` (incremental staking). Production remains on the latter with image `registry.fly.io/regents-sh-web@sha256:48fb2b1a23d5853c0632523bdbbbd25c5470331833a672832402addee76f8877`. Untracked paper folders and unrelated handoffs are preserved.
