# API Contract Workflow

Regents CLI is validated as a standalone repository. Local checks never discover private coordination files or require another product checkout.

## Repository-local truth

- `shared-cli-contract.yaml` owns repository-local public commands, flags, arguments, auth modes, and help metadata.
- `regent-services-contract.openapiv3.yaml` owns the shared-services HTTP routes maintained here.
- `json-rpc-methods.yaml` owns local runtime JSON-RPC methods.
- `schemas/wallet-action.schema.yaml` owns the prepared wallet-action envelope.
- `../packages/regents-cli/src/contracts/api-ownership.ts` maps API-backed commands to product owners.
- `../packages/regents-cli/src/generated/` contains checked-in generated bindings and reviewed copies of product-owned API inputs.

The Platform, Techtree, and Autolaunch generated bindings are copied inputs. Their upstream synchronization happens in separately authorized work and is not performed or discovered by this repository's checks.

## Change order

For a repository-owned CLI command change:

1. Update `shared-cli-contract.yaml`.
2. Update the route handler and tests.
3. Run `pnpm generate:cli-command-metadata`.
4. Run the ordered checks below.

For a shared-services HTTP change:

1. Update `regent-services-contract.openapiv3.yaml`.
2. Run `pnpm generate:openapi`.
3. Update implementation and tests.
4. Run the ordered checks below.

For a product-owned API change, land the reviewed copied binding through its dedicated synchronization work before changing code that consumes it.

## Validation

```bash
pnpm check:workspace
pnpm check:openapi
pnpm check:cli-contract
pnpm build
pnpm typecheck
pnpm test
```

These gates verify only repository-local contracts, copied inputs, generated files, routes, documentation, and tests.
