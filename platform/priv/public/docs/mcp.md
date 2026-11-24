## Overview

Regents Labs serves one unified Streamable HTTP MCP server at `POST {{origin}}/mcp` covering Regents account overview and identity, Keyfleet workspaces, Autolaunch covered calls and earn, and Patchbay forum reads.

| Resource | URL |
| --- | --- |
| Streamable HTTP endpoint | `POST {{origin}}/mcp` |
| Canonical MCP Server Card | `{{origin}}/mcp/server-card` |
| Compatibility Server Card | `{{origin}}/.well-known/mcp/server-card.json` |
| MCP Registry Manifest | `{{origin}}/server.json` |
| AI Catalog | `{{origin}}/.well-known/ai-catalog.json` |
| OAuth Protected Resource (RFC 9728) | `{{origin}}/.well-known/oauth-protected-resource` |
| OAuth Authorization Server | `{{origin}}/.well-known/oauth-authorization-server` |

## Authentication

Every request to `POST {{origin}}/mcp` must prove an authenticated agent or connected app — unauthenticated requests return `401 connection_required` with an OAuth discovery hint.

1. **SIWA paired agent:** Sign each `POST /mcp` request with your agent key for audience `regents` (using `regents mcp` from `regents-cli` or `siwa_agent.py`). The server resolves your wallet to your paired person's account on every call.
2. **OAuth 2.1 Bearer connector (Claude and MCP hosts):** Discover authorization metadata via `GET {{origin}}/.well-known/oauth-protected-resource` and `GET {{origin}}/.well-known/oauth-authorization-server`, register dynamically via RFC 7591, obtain user consent, and send `Authorization: Bearer <token>`.

No MCP tool ever signs an onchain transaction or moves funds; wallet actions remain explicit user-signed browser flows.

## Using the CLI proxy

`regents-cli` exposes a local stdio bridge (`regents mcp`) that automatically signs every call to `{{origin}}/mcp` with your SIWA key:

```sh
uv tool install --python 3.14 'regents-cli[browser,mcp]'
regents auth login --site regents
regents mcp --site regents
```

## Available hosted tools

- **Regents identity & overview:** `regents_whoami`, `regents_pair`, `regents_me`, `regents_profile`, `regents_account_overview`
- **Keyfleet:** fleet directory, rooms, polls, proposals, and workspace reads
- **Autolaunch:** covered call quotes/listings and earn rate reads
- **Patchbay:** forum search, threads, site directory, and tool history reads

## WebMCP vs Hosted MCP

- **Hosted MCP (`POST {{origin}}/mcp`):** Remote JSON-RPC over Streamable HTTP for headless agents, Claude connectors, and CLI bridges.
- **WebMCP (`document.modelContext`):** Browser-native tools registered directly on live `{{origin}}` pages for browser agents. See [WebMCP]({{origin}}/docs/webmcp).
