# Regents CLI Handoff

Regents CLI is a standalone public repository. Its builds, tests, doctor reports, and contract checks use only files checked into this repository.

## Sources

- `docs/shared-cli-contract.yaml`: repository-owned CLI command contract
- `docs/regent-services-contract.openapiv3.yaml`: repository-owned shared-services HTTP contract
- `docs/json-rpc-methods.yaml`: local runtime contract
- `packages/regents-cli/src/contracts/api-ownership.ts`: command-to-API ownership map
- `packages/regents-cli/src/generated/`: checked-in generated bindings and copied product API inputs
- `packages/regents-cli/src/routes/`: shipped command handlers

Public command behavior is contract-first. Product-owned copied inputs are updated through their own reviewed synchronization work; local validation never discovers another checkout.

## Checks

```bash
pnpm check:workspace
pnpm check:openapi
pnpm check:cli-contract
pnpm build
pnpm typecheck
pnpm test
```

Do not publish, deploy, push, sign, access production, or move value without explicit authority.
