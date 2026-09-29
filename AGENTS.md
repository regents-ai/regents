# Regents

Own regents.sh, its API and Regents contracts in this monorepo. The `regents` CLI lives in
the separate regents-cli repository.

- `platform/`: Phoenix/Ash application. Read its instructions for web changes.
- `contracts/`: Solidity, staking/distribution and retained historical evidence.
- `identity/`: shared Ash identity domain and `regent_identity` schema consumed by every
  product. Read its README before changing sync, actor or ownership rules.
- `payments/`: shared Ash payment records (`regent_payments` schema) and the x402 and
  wallet payment steps every site uses. Payment records only: no held balance, top-up,
  spend, withdrawal or refund. Read `RegentPayments`' module doc before changing it.
- `plugins/`: home for standalone runtime plugin packages; none exist yet. Hermes,
  OpenClaw, MCP and bundled-skill integrations are CLI code in regents-cli.
- Shared UI and Elixir libraries other than `identity/` and `payments/` come from GitHub, each pinned to
  one commit in `platform/mix.exs`.
- `make check` runs every component gate; `make check-platform`, `check-required-fixes`,
  `check-identity`, `check-payments` and `check-contracts` run one. `MIX_TEST_PARTITION` (an underscore and
  a short id, unique to your working tree) is required.
- Follow the workspace's `regent-workflow`; use one integrating owner for this repository.
  Scope verification to observable acceptance and preserve useful regression coverage.
- Preserve uncommitted work, public command/API shapes and protected source evidence.
  Every distinct wallet press reaches the wallet. No signing, production access,
  deployment or publishing without applicable founder authority. Never read `.env`,
  `.env.local` or `.envrc`.

For product orientation and related Regent products, see [README.md](README.md).
The public agent entry point is [platform/priv/public/llms.md](platform/priv/public/llms.md), served at `/llms.txt`;
keep its advertised commands consistent with the owning CLI and HTTP contracts.
