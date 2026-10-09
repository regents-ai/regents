# Regents signed-agent source adoption — 9 October 2026

Done for this source handoff means: adopt the published shared verifier and pairing authority; expose only the agreed private reads; enforce the current pairing and server-resolved owner; publish matching browser, HTTP and CLI descriptions; keep spending grants closed; verify representative flows; preserve the live paper and staking changes; publish source for the coordinator. Deployment and native signing acceptance remain separate gates.

## Source changes

- Shared libraries are pinned to final published `elixir-utils` commit `1564d79eb3b653f06ab11b6c422bd4d6283ea199`, matching template reference `4255fd4327882022424e4f600656532e2baecffe`. Agents and Payments come from that shared release. Ash is locked to 3.34.6.
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
- All ten CLI command descriptors validated against the owning CLI schema and matched their OpenAPI methods, paths and operation IDs.
- The browser adapter registered twelve tools and passed synthetic checks for request preparation, proof enforcement, tamper refusal, omitted browser credentials, redirect refusal and disposal/re-registration.
- Independent security review found no actionable source findings.

The local checks reused `regents_staking_refresh_06_dev` and rolled back transient owners, claims, pairings and grants. The preserved counts were zero users, zero pairings, zero grants and one saved staking reading. No production access, real signature, wallet action, Points activation or spending was performed for this adoption.

Temporary evidence is under `/tmp/regents-agent-*`, including `local-verify-final.log`, `adapter-verify.log`, `contract-verify-final.log`, `assets-final.log`, `typecheck-final.log`, `compile-final.log` and `format-check.log`. These fixtures and generated browser assets are not shipped as source.

## Published contract

Served YAML SHA-256: `45cb5021bfb2ba6a645487ed6849bdc8cd9afea9d292d71b6b9c5ddfdf5e524d`.

Preserve the CLI platform `protocol`, base URL `https://regents.sh` and signing audience `regents`. Private commands are `agents whoami`, `account show`, `account claims`, `staking position`, `account balances`, `account credits-history`, `account points` and `account budget`. The two existing pairing commands remain in the descriptor.

## Remaining gates

- The coordinator holds production database changes and deployment for credential handling and native signing acceptance. This handoff publishes source only.
- Native browser signing, real SIWA verification/replay and live cross-site acceptance have not passed in this lane. Synthetic proof headers are not evidence of those checks.
- The owning CLI's installed 1.9.0 candidate passed Regents command, private-input, dispatch, help and error-redaction checks. Official package publication and matching deployment remain coordinated release gates.
- Regents has no agreed private nonfinancial agent write. Do not invent a write to satisfy a generic checklist; the coordinator has accepted this product gap pending Sean's decision.
- Keep spending grants closed and Points settings unchanged until the coordinator's release gate explicitly permits otherwise.

The source retains approved live ancestors `bc1a69a4` (paper folders), `14f694e1` (paper controls) and `2220e11943caf3c6e753fdcc23420a8be5325d7e` (incremental staking). Production remains on the latter with image `registry.fly.io/regents-sh-web@sha256:48fb2b1a23d5853c0632523bdbbbd25c5470331833a672832402addee76f8877`. Untracked paper folders and unrelated handoffs are preserved.

## Points coverage follow-up

The coordinator's coverage review identified a missing shared Points read. `GET /api/agent/v1/points` now uses the same `RegentPoints.summary` as ShellLive with the distinct agent actor, canonical owner ID and shared current-pairing policy. The template-aligned response exposes balance/earned-today micro-Points, pending count, allowances, recent ledger entries and `more?`; private event evidence is excluded. Browser operation `regents_points_summary`, OpenAPI operation `agentPointsSummary` and CLI command `account points` match. No input or body is accepted.

Strict compilation, scoped format, asset build, typecheck, contract validation and all ten CLI descriptors passed. Representative router checks proved an absent Points account stays absent, different owners' nonzero fixture balances/entries stay isolated, the human and agent summaries agree, and all Points table counts stay unchanged by reads. Query/body/duplicate-proof refusal, revocation, stale-episode refusal, re-pairing and no cookie fallback passed. The synthetic browser adapter exercised the new GET with no body or body digest and twelve registered tools. Independent security review found no actionable findings.

Local Points schemas were prepared explicitly in the reused development database. Synthetic Points accounts, events and entries were rolled back; all six Points table counts returned to zero. No activation, real award, production migration, deployment or signature occurred. Follow-up evidence: `/tmp/regents-agent-points-{verify,adapter,contract,compile,assets,typecheck}.log`. The temporary adapter check initially assumed GET had an empty-string body and supplied a POST body digest; correcting those fixture assumptions confirmed the shared transport's GET refusal and successful body-free request.

## Final shared reference follow-up

Sol supplied the reviewed final shared and template references above. Payments now uses the shared Git sparse dependency; the historical local `payments/` source is unchanged. Regents has no Purchase, WalletPayment, MCP or Offer consumer, so this change introduces no payable action. Other shared implementations are unchanged relative to the earlier pin; payment migrations are byte-identical.

Strict integrated compilation, scoped formatting, assets, TypeScript and the final template required-fixes registry passed. Representative signed-router/Points checks passed again: owner isolation, exact request handling, pagination, revocation/re-pairing, no cookie fallback, no writes and the default-closed grant gate. Contracts still match the published digest. Independent compatibility/security review found no actionable issue. No payment, real signature, activation, schema change or product deployment occurred. Evidence is `/tmp/regents-agent-final-shared-*.log`.

Separately, Sean explicitly authorized shifting all 29 live paper posting dates three days earlier, allowing publication-date exceptions. They now run from 11 September through 9 October. Production readback preserved IDs and all content hashes; all cover URLs matched, and the browser shows October 9 first. Authoring folders and the truthful audit were synchronized; all 29 folders pass the existing checker. This data correction required no source deployment and must survive the signed-access release.
