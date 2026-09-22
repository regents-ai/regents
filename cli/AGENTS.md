# Regents CLI

This component owns the `regents` command. It builds and tests from this monorepo: the OpenAPI checks read the profile contract from `../identity/contracts/`, and other product-owned API bindings arrive as reviewed, checked-in copies. Builds and tests must not require a checkout of another repository or upstream synchronization.

## Workspace workflow

Follow `/Users/sean/Documents/regent/.agents/skills/regent-workflow/SKILL.md`.
Hermes/Astra coordinates Claude/Fable assignments. Use isolated worktrees for
concurrent writers and preserve unrelated work. Repository checks and contracts
below define verification; no central coordinator service is required.

## Repository contracts

- Change the owning contract before code: `docs/shared-cli-contract.yaml` owns CLI behavior, `docs/regent-services-contract.openapiv3.yaml` owns shared HTTP behavior, and `docs/json-rpc-methods.yaml` owns runtime methods.
- Generated artifacts, including `packages/regents-cli/src/generated/` and `docs/json-rpc-methods.md`, are regenerated and never hand-edited. `packages/regents-cli/src/contracts/api-ownership.ts` maps API-backed commands to the checked-in bindings.
- Route registries under `packages/regents-cli/src/routes/` define the shipped command set.
- Command names, flags and JSON output shapes are a public contract. They change only through a deliberate release whose notes name every changed shape; there is no additive-only promise and no compatibility window.
- Use a hard cut: do not add compatibility aliases, fallback paths, or dual sources unless explicitly requested.
- Live transport flows are daemon-owned; do not add direct CLI-to-server socket paths.

## Protected actions

- Never push, deploy, publish, sign, read secrets, or move value without explicit founder authority.
- Never read `.env`, `.env.local`, or `.envrc`; `.env.example` is allowed.

## Required validation

Run `make check-cli` from the repository root.
