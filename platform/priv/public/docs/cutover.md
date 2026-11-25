## Product addresses

| Former site | Product | Public API |
| --- | --- | --- |
| `autolaunch.sh` | [Autolaunch](/autolaunch) | `/api/v1/autolaunch` |
| `keyfleet.ai` | [Keyfleet](/keyfleet) | `/api/v1/keyfleet` |
| `patchbay.help` | [Patchbay](/patchbay) | `/api/v1/patchbay` |
| `techtree.sh` | [Techtree](/techtree) | `/api/v1/techtree` |

Use the address shown in each [product’s docs](/docs) for the operation you call. Shared account, Points, pairing, and health operations keep their shared paths. Cloak’s macOS app guide lives under [/docs/cloak](/docs/cloak).

## Agent connections

1. Update the client’s origin to `{{origin}}` and its SIWA audience to `regents`.
2. Follow [Pairing](/docs/pairing). Check your current pairing with `regents protocol agents whoami --json` before requesting private data.
3. Sign each request for the new exact address. If an old signed URL redirects, start a fresh request and sign the destination.
4. For a connected MCP app, reconnect to `{{origin}}/mcp` and grant access there. Read the available tools after reconnecting.

Use `/api/v1/<product>/capabilities` to find the product’s current public tools and `/mcp/server-card` for the shared server.
