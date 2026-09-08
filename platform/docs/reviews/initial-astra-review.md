# Regents — initial Astra review

## Scope and checkout

Repository: `/Users/sean/Documents/regent/repos/regents`, branch `main`, reviewed base `699850b`.

This is a local engineering review and workflow-migration closeout, not a release approval or exhaustive security audit. The initial uncommitted changes were eight documentation/metadata files, not product implementation. Historical prunable worktree registrations were inspected but not restored, pruned or treated as current assignments.

Loaded the canonical workspace `regent-workflow` and the `ash-stack` family, including security and Privy reconciliation guidance. No `regents-ash` skill was found. Claude CLI authenticated through the existing Max account; an explicit model probe and both delegated sessions resolved to `claude-fable-5-1`, rather than the configured Opus default.

## Completed changes

Preserved the initial edits and finished the active workflow migration in:

- `platform/AGENTS.md`: workspace workflow and assignment acceptance replace Control/ticket instructions.
- `platform/docs/showcase.md`: ordinary isolated worktree setup, explicit test environment and independently selected port replace retired wrapper commands and a stale ticket/port assignment.
- `cli/docs/agent-wallets.md`: corrected the workspace policy link to `../../../../agent-docs/webmcp-cli-standard.md`. The policy still exists; the delegated proposal to remove its link was rejected during integration review.

`git diff --check`, active-workflow reference scanning and the relevant Markdown link-target checks passed. No application behavior, public commands, API contracts, dependency locks or historical evidence was changed. Nothing was staged, committed, pushed, deployed or signed.

## Architecture map

- `platform/`: Phoenix/LiveView shell and public HTTP surface; Ash domains own account/session authority, staking/redemption reads, retained Formation/Autolaunch behavior and historical claims.
- `cli/`: independently built TypeScript CLI with local copied bindings, route registries, runtime integrations and wallet adapters.
- `identity/`: shared Ash profile domain and schema. Verified Privy evidence supplies the actor; product sessions and payment authority remain distinct.
- `contracts/`: Solidity and retained staking/redemption evidence. This pass traced relevant recipient restrictions but did not run the Solidity gate or perform a full contract audit.
- Shared Privy and UI implementations live in sibling repositories. No sibling implementation was edited.

## Findings and priorities

### 1. High — shipped CLI staking routes do not exist in this platform

`cli/packages/regents-cli/src/commands/regent-staking.ts:100` and `:124` request `/api/shared/regent/staking` and `/api/shared/regent/staking/stake`. The group is marked `status: "current"` in `cli/packages/regents-cli/src/contracts/api-ownership.ts:374`. The default platform origin is `https://regents.sh` (`cli/packages/regents-cli/src/internal-runtime/config.ts:291`).

The compiled Phoenix router returned `:error` for both method/path pairs. An actual GET against the locally running application returned HTTP 404. No production request was needed.

The CLI's own contract checks all pass, so they do not establish parity with the owning server. Decide which retained commands remain supported, then align the owning contract, route inventory, generated bindings and capability claims together. Do not silently retire public commands or invent a replacement endpoint.

### 2. Medium — canonical HTTP inventory omits implemented private surfaces

`platform/lib/ash_platform_web/router.ex:63` mounts `/api/v1/claims` and forwards `/api/v1/profile` to `RegentIdentity.HTTP`. Both were confirmed in the compiled router. Neither appears in the canonical path list asserted by `platform/test/ash_platform_web/api_contract_test.exs:10`.

This is a contract/discovery gap, not evidence of an authorization bypass. Review the independently maintained profile schema and response codes while bringing these routes into the owning API inventory.

### 3. Medium — the platform's full gate is red

- Credo reports 14 existing findings: six warnings, six refactoring findings and two readability findings. They concern showcase code, claim-snapshot validation and legal-document loading.
- ExUnit has one failing assertion at `platform/test/ash_platform_web/home_live_test.exs:23`. A rendered-homepage probe returned local links `/`, `/stake`, `/llms.txt`; the assertion only permits the first two and fragments. The unexpected link is the public agent guide, not a broken legal route.
- Sobelow reports `Traversal.SendFile` at `platform/lib/ash_platform_web/showcase/catalog.ex:122`. Inspection shows a fixed `Application.app_dir(:ash_platform, "priv/showcase.css")` path, with no request parameter interpolation. This appears to be a scanner false positive; the failing gate still needs an explicit, justified resolution.

Restore the real gate without suppressing genuine policy or data-preservation checks. No lint cleanup or test weakening was performed in this review.

### 4. Medium — browser wallet fixtures are tied to one origin

Playwright accepts a configurable port, but `platform/assets/js/wallet_actions/connected_wallet.ts:149` only admits its fake wallet on `http://127.0.0.1:4002`.

On isolated port 41983, the three selected specs produced 9 passes and 14 wallet-fixture failures. After verifying that 4002 was free, the same specs and isolated database produced **23 passes** there. This does not establish a product wallet regression. Future isolated-browser tooling must either document the fixture origin restriction or deliberately redesign the test-only origin boundary without exposing it to production.

### 5. Dependency risk — pinned Ash version has a published advisory

Both components resolve Ash 3.32.3. Hex reported [CVE-2026-82752 / GHSA-cwjv-574p-59f6](https://osv.dev/vulnerability/EEF-CVE-2026-82752), concerning grapheme-count length constraints that do not independently bound bytes; the advisory identifies 3.33.0 as the fixed boundary.

This is a confirmed affected dependency version, not a demonstrated exploit in this application. The profile edit path already imposes a separate 320-byte display-name bound (`identity/lib/regent_identity/selected_wallet.ex:7`). Other resources use string length constraints and require an input/storage-bound review. Upgrade through the shared-consumer verification process rather than changing locks opportunistically.

### Follow-up risk — same-wallet provider refresh during a pending press

Fable identified a possible silent cancellation path: unknown wallet apps fail continuity matching in `platform/assets/js/privy_bridge.tsx:394`; wallet reset removes unhanded-off result slots in `platform/assets/js/hooks/stake_wallet.ts:412`; `DeadGeneration` returns without an immediate result in `platform/assets/js/wallet_actions/staking.ts:290`.

Those branches were inspected, but actual Privy/provider timing was not reproduced. Keep this as a targeted canary/reproduction task, not a confirmed production failure. The passing browser checks use deterministic wallet providers, not real extensions.

## Verification actually run

| Check | Result |
| --- | --- |
| CLI workspace, input, OpenAPI, public-copy, CLI and MCP contract checks | Passed |
| CLI build and typecheck | Passed |
| CLI Vitest | 539 passed across 82 files |
| Platform compile with warnings as errors, unused locks, format | Passed before Credo stopped precommit |
| Platform Credo strict | Failed: 14 findings |
| Platform asset build and TypeScript check | Passed |
| Platform Vitest | 502 passed across 23 files |
| Platform ExUnit with warnings as errors | 1,132 tests, 1 failure, 1 excluded |
| Platform Sobelow | Failed: fixed-path showcase finding described above |
| Platform compile-connected xref ceiling | Passed |
| Ash codegen check | Passed |
| Route handoff check | Passed |
| Identity `mix check` | Passed: 16 tests; clean rerun after concurrent connection pressure |
| Overview, Stake and Redeem Playwright specs on port 4002 | 23 passed |
| Workflow diff/reference/link checks | Passed |

Local verification used `MIX_TEST_PARTITION=_astra_831_review` and `_astra_831_browser`, and identity database `regent_identity_test_astra_831_review`. The browser database required `mix ash_platform.setup_local_auth` before the Playwright seed commands. Optional Sentry DSN must be unset, not set to an empty string. Concurrent runs briefly exhausted local PostgreSQL connections; the identity rerun was clean. No shared or production database was reset.

Shared revisions inspected:

- `elixir-utils`: `fbd492cf51dc5d385da86567d763f01318187bae`
- `design-system`: `b422b26c84acabfdc42107d4891c398b6f35add0`

The sibling checkouts contained pre-existing documentation/untracked palette work. This was not a pristine release-snapshot validation. Locked Node dependencies and generated platform assets were installed locally. The asset task also generated untracked files under `platform/priv/static/fonts/regent-ui/`; these are build output, not a proposed product change.

## Continuation references

Fable documentation session: `23bc63a6-9b56-4fa9-9077-bdb1e8bf60f7`.
Fable read-only review session: `50609e2d-6eb0-4788-8432-28933d60029e`.
Resume with the explicit session ID and the same repository directory; do not use an ambiguous latest-session resume.

Full local logs: `/tmp/regents-cli-check.log`, `/tmp/regents-platform-precommit.log`, `/tmp/regents-platform-exunit.log`, `/tmp/regents-platform-sobelow.log`, `/tmp/regents-platform-vitest.log`, `/tmp/regents-identity-check-rerun.log`, `/tmp/regents-browser-4002.log`. Raw delegated summaries are `/tmp/regents-workflow-fable.json` and `/tmp/regents-code-review-fable.json`; they are secondary evidence and include claims corrected by this report.

Recommended next scope: restore the platform gate, then reconcile the supported CLI/API surface. Shared identity rollout, historical-claim migration, real Privy/wallet canaries, contract gates and release-supply verification remain separate work. No production readiness is claimed.
