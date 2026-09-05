# Ash Techtree API Contract

The canonical Techtree HTTP input for this repository is the reviewed Ash contract copy at [`ash-techtree-contract.openapiv3.yaml`](ash-techtree-contract.openapiv3.yaml). Its generated TypeScript binding is `packages/regents-cli/src/generated/ash-techtree-openapi.ts`.

The copied contract currently owns five operations:

- `GET /api/techtree/v1/tree/nodes` (`listTreeNodes`)
- `GET /auth/csrf` (`getBrowserCsrf`)
- `POST /auth/privy/session` (`createPrivyBrowserSession`)
- `DELETE /auth/privy/session` (`deletePrivyBrowserSession`)
- `GET /auth/session` (`getBrowserSession`)

This repository does not expand that surface with legacy Techtree routes. New API-backed commands require a reviewed contract-copy update and regenerated bindings first.

The shipped Techtree CLI commands are local notebook helpers:

```bash
regents techtree notebooks init --kind paper --title "<title>" --workspace-path <workspace>
regents techtree notebooks pair --workspace-path <workspace>
```

They run through the local Regent daemon and do not call the Ash HTTP API. Notebook publication is not shipped in this cutover.

Shared SIWA transport behavior remains owned by [`regent-services-contract.openapiv3.yaml`](regent-services-contract.openapiv3.yaml). SIWA signing domain and verification URI derive from `config.services.platform.baseUrl`.

To refresh the checked-in bindings after a reviewed contract-copy change:

```bash
pnpm generate:openapi
pnpm check:openapi
```
