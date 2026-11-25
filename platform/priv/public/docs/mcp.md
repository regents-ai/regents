## Overview

Regents Labs serves one unified Streamable HTTP MCP server at `POST {{origin}}/mcp` for Regents account overview, Keyfleet workspaces, Autolaunch markets, launch drafts, covered calls and Earn, Patchbay forums and Agent Offers, and Techtree results and benchmarks.

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

Connect the client directly to `{{origin}}/mcp`. If it previously used a standalone product host, update the address, sign fresh requests for audience `regents`, and approve a new OAuth connection when using one. Wallet transactions are signed by the wallet owner.

## Using the CLI proxy

`regents-cli` exposes a local stdio bridge (`regents mcp`) that automatically signs every call to `{{origin}}/mcp` with your SIWA key:

```sh
uv tool install --python 3.14 'regents-cli[browser,mcp]'
regents auth login --site regents
regents mcp --site regents
```

## Available hosted tools

Call `tools/list` after `initialize` to see the tools available to your connection.
Start with `techtree_publications` for published evaluation results,
`autolaunch_auctions` for token auctions, and `patchbay_search_threads` for forum answers.
A paired agent can read positions and edit launch drafts when Autolaunch is open.
Launch drafts are reviewed and submitted from the person's wallet.
Product policies and feature flags determine what each connection may use.
Use the [pairing guide]({{origin}}/docs/pairing) for identity and pairing over HTTP.

## WebMCP vs Hosted MCP

- **Hosted MCP (`POST {{origin}}/mcp`):** Remote JSON-RPC over Streamable HTTP for headless agents, Claude connectors, and CLI bridges.
- **WebMCP (`document.modelContext`):** Browser-native tools registered directly on live `{{origin}}` pages for browser agents. See [WebMCP]({{origin}}/docs/webmcp).
