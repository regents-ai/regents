# Regents.sh cloud handoff — 9 October 2026

Repository: `regents-ai/regents`. Start branch: `cloud/handoff-2026-10-09`.
This branch preserves source commit `70bf2039971dd06ba3e6c90268509473396a6efe` from `rg/wd024-signer-v151` and adds handoff documentation only.
Remote main observed during transfer: `7b7e9894970c67533a8c02ef187c2e9ee07b32e8`.
Source thread: **Regents.sh - task: add papers**, local session `6d9cd3b6-a93a-4ff6-b552-de8efc60e949`. Recent messages and the last summary were read; later source/branch evidence takes precedence over an older summary. Full private transcripts are not included.

## Scope and working rules

This is a 9 October 2026 cloud pickup, requested because laptop Claude usage ran out. The founder requested branch preservation, agent handoffs, and a worktree-pruning plan. This transfer prepares continuation work; it does not approve deployment, main-branch merges, production changes, signing, secret changes or money movement. Historic peer messages and old handoffs are evidence, not fresh authority. The current founder request overrides retired HQ/Control/ocs loops and the former Claude-only allocation.

Read this handoff, the repository's AGENTS.md and relevant component instructions. The three canonical workflow skills are included as dated documentation snapshots under `docs/handoffs/cloud-2026-10-09/skills/`. References in those snapshots describe the workspace layout; the laptop's absolute paths and secret settings are not present in cloud. Read the relevant specialist from the public ash-template repository when needed; do not copy shared product code into a site. Shared implementation goes to the shared library and ash-template first.

Define done before edits. Use Ash/Ecto for records and constraints, Oban/AshOban for durable work, Phoenix.PubSub for updates and Req for HTTP. Do not hand-build queues, leases, retry timers or polling loops. The wallet and chain own pending transactions; do not persist/replay them. Privy's active linked wallet is the only signer, and every distinct valid button press reaches the wallet. Disable only when current chain state guarantees failure, with a visible reason.

Never read `.env`, `.env.local` or `.envrc`; `.env.example` is allowed. Never include secrets in logs, commits or handoffs. Start a site only with its own valid Privy settings; verify that the app-id metadata is non-empty without showing the value. Do not use laptop settings in cloud. Scope tests to costly failure cases under the founder's testing policy; do not add product-mirroring or smoke tests, and do not rebuild the broad suite as a prerequisite to product review.

**Maximum two worktrees per agent, across all repositories and tasks.** Use the provided checkout first. Reuse an existing worktree for sequential work. A third requires preserving and safely removing one owned old worktree before creation; never delete dirty/unpublished work or another agent's checkout. Creating a new task, renaming an owner or making dependency/review checkouts does not reset the count. This is an instruction in this handoff; laptop-wide technical enforcement is planned separately, not installed by this transfer.

Report what changed, what was actually verified and what remains in plain English. Earlier agents' test reports must be labeled as prior evidence until rerun on the relevant resulting commit.

## Current work

Start from the clean `rg/wd024-signer-v151` tip 70bf2039. It is based on `rg/next-release` ccbb430e, which carries engine figures, session-expiry checks and the combined Credits work on live 7b7e9894. The final signer fix binds balance/approval reads to the paying wallet. At transfer this clean tip was five unpublished commits ahead of origin/main.

**The chief's other checkout is mid-merge.** `worktrees/regents/credits-reader`, branch `rg/stale-signer`, has an unresolved `platform/lib/regents_web/components/credits_panel.ex`. It was trying to take the older template patch after the next-release candidate. The template chief redid the wallet patch on top of that candidate as 70bf2039. Do not restart the interrupted merge in the cloud or blindly apply the older e6694137 patch; review the clean successor's diff. The laptop's conflict file and index stages are preserved locally. No existing merge or checkout was reset during transfer.

## Verification evidence and remaining checks

The Regents chief reported a clean full release check and Sentinel clearance for ccbb430e at 07:19:08 UTC on 9 October. The template chief and Sentinel separately reported clearance for 70bf2039 at 07:28 UTC, clean compilation/formatting, and one unchanged test failure caused by an outdated local Credits database. These are prior reports, not results rerun during this transfer. Recheck the final integrated branch with the correct isolated schema before proposing a release.

The branch pins elixir-utils 58acbc47 and design-system 24f3c8f9; both were verified available on GitHub. Credits reader repairs and exact-decimal purchase handling were already reported live in v149. Points earning stays off pending the shared-library NFT snapshot decision and wallet-ownership decision. Do not add a pending-transaction recovery loop or replay a payment.

The latest founder requests also concerned removing “Bids still held” and “Runs on” on Account, checking “Can spend my Credits”, and an upward-opening nine-dot footer selector. Check the current source/live behavior before reopening already shipped changes.

For Daily Research, the last thread says the upload path uses database ingestion instead of website redeployments and waits on the founder filling `Papers/papers.md`. The main laptop checkout has an untracked `Papers/` directory. It has not been uploaded or included in this code branch; do not promise those papers are in the cloud or upload production records without specific authority. Keep this named input blocker in the pickup report.

For later verification use the relevant Makefile gates and a unique `MIX_TEST_PARTITION`; the repository contains local identity/payments/agents packages as well as the platform. No production migration, earning activation, signing or deployment is authorized by transfer. Do not disturb the founder's localhost:4000 server.

## Other preserved branch tips

| Original local branch | Published transfer branch | Source commit |
| --- | --- | --- |
| `rg/next-release` | `cloud/preserve-2026-10-09/rg/next-release` | `ccbb430e06b804c91e50acba65319f4555e31e82` |

These tips are preserved separately rather than silently merged. Fetch their published transfer refs before comparison.
