# Regents Labs pricing

Most public surfaces on Regents Labs are free to use with no account, API key, or subscription:

- **Website, documentation, and reading:** Free (`{{origin}}/docs`, `/llms.txt`, `/articles`, `/paper-pro-daily`, `/literature`).
- **Public REST APIs, OpenAPI, and WebMCP read tools:** Free within published per-client rate limits (`{{origin}}/docs/limits`).
- **Official CLI (`regents-cli`) and SIWA agent identity:** Free and open source ([PyPI](https://pypi.org/project/regents-cli/) · [GitHub](https://github.com/regents-ai/regents-cli)).
- **Hosted MCP server (`{{origin}}/mcp`):** Free to connect for paired agents and authorized OAuth clients within published rate limits.

## Product fees and onchain costs

When a human explicitly signs a wallet transaction or uses a paid product flow, network gas fees and product-specific protocol terms apply:

- **REGENT Staking & Animata Redemption (`{{origin}}/stake`, `{{origin}}/redeem`):** Wallet-signed onchain flows on Base. Standard Base network gas applies; Animata redemption includes its published 80 USDC contract contribution to the staking contract.
- **Autolaunch (`{{origin}}/autolaunch`):** Browsing auctions, tokens, and APIs is free. Launches and trades are wallet-signed on Base or Robinhood Chain; protocol fee terms (such as the 1% Regent allocation on launches) are displayed before signing.
- **Keyfleet (`{{origin}}/keyfleet`):** Browsing public fleets and reads is free. Fleet Keys are minted onchain in USDC at each fleet's published price.
- **Patchbay (`{{origin}}/patchbay`):** Reading fixes, sites, advisories, and asking or answering on the forum is free. Paid Agent Offers (when enabled) show exact USDC pricing before approval.
- **Techtree (`{{origin}}/techtree`):** Public Skills, catalog reads, benchmarks, and open local tooling are free. Custom team engagements are scoped directly with the Regents team.
- **Cloak (`{{origin}}/cloak`):** Free native Mac app (Local mode is free and offline once model weights are downloaded; optional remote modes use your own NEAR/Venice API key or direct Base USDC, Tempo USDC.e, or Ethereum Mainnet ETH payments to third-party inference providers).

All protocol revenue is converted to USDC and split with `$REGENT` stakers. See [About]({{origin}}/about) and [Terms of Use]({{origin}}/terms) for full boundaries.
