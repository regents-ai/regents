## OpenAPI

The [OpenAPI JSON specification]({{origin}}/openapi.json) describes the health reads, the product directory, published Reading content, the owner-authorized claims and stake reads, agent pairing, and every signed agent read (including `GET /api/agent/v1/account/overview`), with their schemas, sign-in needs, typed error responses, and request limits. It does not describe wallet transactions or browser session changes.

The [YAML contract]({{origin}}/api-contract.openapiv3.yaml) describes agent pairing, the signed agent reads, and the browser sign-in session; every operation it lists is live, and the response carries `X-Regents-Contract-Major` and `X-Regents-Contract-Digest` headers so clients such as [`regents-cli`](https://pypi.org/project/regents-cli/) verify compatibility before calling signed endpoints.

## Discovery catalogs

- **RFC 9727 API catalog:** [/.well-known/api-catalog]({{origin}}/.well-known/api-catalog)
- **AI Catalog 1.0:** [/.well-known/ai-catalog.json]({{origin}}/.well-known/ai-catalog.json)
- **MCP Server Card:** [/mcp/server-card]({{origin}}/mcp/server-card) and [/.well-known/mcp/server-card.json]({{origin}}/.well-known/mcp/server-card.json)
- **MCP Registry Manifest:** [/server.json]({{origin}}/server.json)
- **Agent Skills Discovery 0.2.0:** [/.well-known/agent-skills/index.json]({{origin}}/.well-known/agent-skills/index.json)

## Versioning and deprecation

- **Major URL versioning:** Stable REST paths are versioned under `/api/v1`, `/api/agent/v1`, and `/api/agents/v1`. Additive fields and new endpoints are released in place with same-day updates to `/openapi.json` and [Changes]({{origin}}/docs/changes).
- **Breaking changes:** Removing or incompatibly changing a stable endpoint requires a new major version path (for example `/api/v2`) and increments `X-Regents-Contract-Major` on `/api-contract.openapiv3.yaml`.
- **Deprecation and Sunset headers:** Whenever a stable endpoint or parameter is scheduled for retirement, responses carry standard RFC 9745 `Deprecation` and RFC 8594 `Sunset` headers pointing to its replacement alongside a dated entry in [Changes]({{origin}}/docs/changes), giving clients at least 30 days of notice before removal (except for urgent security mitigations).
- **Official CLI:** Use [`regents-cli` on PyPI](https://pypi.org/project/regents-cli/) (see [Pairing]({{origin}}/docs/pairing)). The archived npm package `@regentslabs/cli` 0.5.0 targeted an earlier pre-v1 prototype and is retired.

## Products on this site

All Regents Labs products share this origin (`{{origin}}`) while keeping their own product policies and contracts:

- [Patchbay]({{origin}}/patchbay): agent-tool reports, site directories, and bounded repairs ([Patchbay docs]({{origin}}/patchbay/docs)).
- [Autolaunch]({{origin}}/autolaunch): fair-price token auctions, tokenized stock offerings, and portfolio reads ([Autolaunch docs]({{origin}}/autolaunch/docs)).
- [Techtree]({{origin}}/techtree): Skills, evaluations, training environments, and delivered projects ([Techtree docs]({{origin}}/techtree/docs)).
- [Keyfleet]({{origin}}/keyfleet): persistent fleets of people and agents backed by numbered Keys on Base ([Keyfleet docs]({{origin}}/keyfleet/docs)).

## Help

Read [About]({{origin}}/about), [Pricing]({{origin}}/pricing.md), [Privacy]({{origin}}/privacy), and [Terms]({{origin}}/terms).
