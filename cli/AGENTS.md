# Regents CLI control bridge

This repository owns the standalone `regents` command and must remain independently buildable and testable. Product-owned API bindings arrive as reviewed, checked-in copies; builds and tests must not require another product checkout or upstream synchronization.

## Private control

- Before Regent work, load `/Users/sean/Documents/regent/control/.agents/skills/regent-workflow/SKILL.md`. Load a role skill only when a dispatch work order explicitly assigns that role.
- `/Users/sean/Documents/regent/control/repos/regents-cli.yaml` is the authority for repository mechanics and proof.
- Do ticket work only in its assigned isolated worktree. The original checkout is sterile and integration-only: never install, build, generate, serve, or run acceptance there.
- Workers never read or mutate Beads.

## Repository contracts

- Change the owning contract before code: `docs/shared-cli-contract.yaml` owns CLI behavior, `docs/regent-services-contract.openapiv3.yaml` owns shared HTTP behavior, and `docs/json-rpc-methods.yaml` owns runtime methods.
- Generated artifacts, including `packages/regents-cli/src/generated/` and `docs/json-rpc-methods.md`, are regenerated and never hand-edited. `packages/regents-cli/src/contracts/api-ownership.ts` maps API-backed commands to the checked-in bindings.
- Route registries under `packages/regents-cli/src/routes/` define the shipped command set.
- JSON output shapes are a public contract and may change only additively within a major version.
- Use a hard cut: do not add compatibility aliases, fallback paths, or dual sources unless explicitly requested.
- Live transport flows are daemon-owned; do not add direct CLI-to-server socket paths.

## Protected actions

- Never push, deploy, publish, sign, read secrets, or move value without explicit founder authority.
- Never read `.env`, `.env.local`, or `.envrc`; `.env.example` is allowed.

## Required validation

```bash
pnpm check:workspace
pnpm check:openapi
pnpm check:cli-contract
pnpm build
pnpm typecheck
pnpm test
```
