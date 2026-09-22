# Chain / API Reconciliation Commands

Status: SHIPPED (2026-06-10). Two commands are live — `identity graph` and `regent-staking verify`. `regent-staking verify` gained its owning-contract entry (platform/cli-contract.yaml) and a full implementation with tests. Several `identity graph` checks render `UNVERIFIABLE` until the sibling-API gaps below are closed. The vendored read ABI is pinned to RegentRevenueStaking.sol; if that contract changes, update the ABI in the command file. The "Required sibling-repo entries" and API-gap lists below are retained as the record of what was added and what remains to file with owners.

The Regents CLI is the bridge that checks product workflow state against onchain truth.
These commands read public product APIs and chain RPC, then report where the two views
agree, disagree, or cannot be compared.

## Source-of-truth rules

- Onchain state wins for money, ownership, staking, and revenue.
- Product databases win for workflow state (queue position, draft status, labels).
- The CLI never reads a product database. It only uses contracted product HTTP APIs
  plus chain RPC reads.

## What the CLI can already reach (survey)

### Generated API bindings (`packages/regents-cli/src/generated/`)

| Binding | Contract file | Reconciliation-relevant operations |
| --- | --- | --- |
| `platform-openapi.ts` | `platform/api-contract.openapiv3.yaml` | `getAgentRegentStakingOverview`, `getAgentRegentStakingAccount` (both return `RegentStakingState` with `contract_address`, `chain_id`, totals, and per-wallet balances/claimables), `/api/platform/projection` (`AgentPlatformProjection` with companies, runtime, public profiles) |
| `regent-services-openapi.ts` | `docs/regent-services-contract.openapiv3.yaml` | Shared identity and SIWA routes. No reconciliation data. |

### Chain-read capability

- `viem` is a shipped dependency. `src/internal-runtime/base-contract-client.ts` already
  builds `createPublicClient` instances per chain and runs `call`, `estimateGas`, and
  `waitForTransactionReceipt`.
- RPC URLs come from the operator environment, never from product secrets:
  - Base mainnet: `BASE_MAINNET_RPC_URL` or `BASE_RPC_URL`
  - Base Sepolia: `BASE_SEPOLIA_RPC_URL`
  - Ethereum mainnet: `ETH_MAINNET_RPC_URL` or `ETHEREUM_RPC_URL`
  - Some command families also accept `--rpc-url`.
- Reconciliation reads use the same clients with `readContract` /
  `getTransactionReceipt` / `getBytecode`. When no RPC URL is configured, a chain check
  reports `UNVERIFIABLE` with the missing variable named; it never fails the command by
  itself.

### Auth rails

- Product `/api/<product>/v1/agent/*` routes use SIWA agent headers (`requestProductJson` with
  `requireAgentAuth`). The saved SIWA session carries one audience at a time, so one run
  can verify the products whose audience matches the saved sign-in; other products
  report `UNVERIFIABLE` with the exact `regents auth login --audience <product>`
  command as the reason.
- Platform app routes (`/api/platform/*`) use the saved Platform session
  (`loadResolvedPlatformSession`).

### Contract ownership (what `pnpm check:cli-contract` enforces)

`scripts/check-cli-contract.mjs` requires the shipped command registry to equal the
union of three CLI contracts, and the dispatcher routes to match that registry exactly:

| Command family | Owning CLI contract | Editable from this repo |
| --- | --- | --- |
| `techtree ...` | `techtree/docs/cli-contract.yaml` | no |
| `regent-staking ...` | `platform/cli-contract.yaml` (platform public command prefix) | no |
| `identity ...` | `docs/shared-cli-contract.yaml` | yes |

A route added without a matching contract entry fails
`CLI dispatcher contains route missing from shipped contracts`. Because sibling repos
must not be edited from this repo, the verify command below ships only after their
owning contract gains the entries listed in "Required sibling-repo entries". No stub or
degraded versions are shipped in the meantime.

## Shared output convention

Every reconciliation command renders one table row per check:

- `MATCH` — the API view and the chain view agree.
- `MISMATCH` — they disagree. The row carries a `Next:` line that applies the
  source-of-truth rule (chain wins for money/ownership/staking/revenue; the product API
  wins for workflow state) and names the command or owner that resolves it.
- `UNVERIFIABLE(reason)` — one side could not be read (no sign-in for that product, no
  RPC URL, API error, feature not exposed). The reason is printed verbatim.

Exit code is `0` only when no check is `MISMATCH`. `--json` prints the same payload as
a single JSON object:

```json
{
  "ok": true,
  "command": "<command name>",
  "status": "ready | mismatch | waiting",
  "checks": [
    { "item": "...", "status": "MATCH | MISMATCH | UNVERIFIABLE", "detail": "...", "reason": "...", "next": "..." }
  ]
}
```

`reason` is present only on `UNVERIFIABLE` rows, `next` only on `MISMATCH` rows.

---

## 1. `regents regent-staking verify` (shipped)

Verifies the staking position and claimables the Platform staking API reports for a
wallet against the staking contract.

- Data sources (API): `getAgentRegentStakingOverview` (`GET /api/shared/regent/staking`)
  and `getAgentRegentStakingAccount`
  (`GET /api/shared/regent/staking/account/{address}`). `RegentStakingState` already
  publishes everything needed: `chain_id`, `contract_address`, `stake_token_address`,
  `usdc_address`, `total_staked_raw`, `wallet_stake_balance_raw`,
  `wallet_claimable_usdc_raw`, `wallet_claimable_regent_raw`, `paused`.
- Data sources (chain): on `contract_address` — staked balance, claimable USDC,
  claimable REGENT, total staked, and `paused()` for the wallet; ERC-20
  `balanceOf(wallet)` on `stake_token_address`.
- Checks: `staking contract deployed`, `total staked`, `wallet staked balance`,
  `wallet claimable USDC`, `wallet claimable REGENT`, `wallet REGENT balance`,
  `paused flag`.
- Verdict logic: all rows are money/staking rows — chain wins. Any difference is
  `MISMATCH` with
  `Next: chain wins for staking. Trust the chain numbers; if the API stays stale, this is incident class staking_claims (owner: platform).`
- Output: per-wallet table (defaults to the saved identity wallet, `<address>`
  positional like `regent-staking account`); `--json` includes `api_view` and
  `chain_view` raw values side by side.
- Missing from sibling APIs / contracts:
  - None for data — the API already publishes the contract address and raw values.
  - The staking contract read ABI (function names for staked balance and claimables) is
    not published anywhere the CLI can reach. Either platform publishes the read ABI /
    method names in `RegentStakingState`, or the CLI vendors the staking read ABI once
    the contract source is pinned.

## 2. `regents identity graph` (shipped)

Renders the cross-product `agent_id` mapping anchored on
`/Users/sean/Documents/regent/docs/schemas/agent-identity-graph.schema.yaml`:
`agent_id` + `wallet_tuple` (wallet, chain, registry, token) with nested
`product_links` for platform, autolaunch, mobile, and the ERC-8004 record.

- Anchor (local): the saved identity receipt (`~/.regent/identity/receipt-v1.json`)
  provides `agent_id`, wallet, chain, registry, token id. Product links never come from
  local files; missing links are `null`, per the schema rules.
- Chain check: ERC-721 `ownerOf(token_id)` on the receipt's registry (Base or Base
  Sepolia per the receipt network, RPC from `BASE_MAINNET_RPC_URL`/`BASE_RPC_URL` or
  `BASE_SEPOLIA_RPC_URL`). Owner != receipt wallet → `MISMATCH`
  (`Next: chain wins for ownership. Run regents identity ensure ...`). No RPC URL →
  `UNVERIFIABLE`.
- Platform link: `GET /api/platform/projection` via the saved Platform session.
  Maps `public_profiles[]`/`companies[]` to `platform_agent_id`, `company_id`,
  `public_slug`, `claimed_name`, `hosted_runtime_id` (sprite service name), and
  `identity_links.techtree` to the Platform-owned Techtree identity-link bucket. A profile
  wallet that differs from the receipt wallet is `MISMATCH` (chain wins for ownership).
  No Platform session → `UNVERIFIABLE` with the sign-in command as the reason.
- Autolaunch link: `GET /api/autolaunch/v1/agent/agents` (SIWA, autolaunch audience). The agent card
  matching the receipt `agent_id` provides `auction_id` and the launched token address
  (`existing_token`); the token address resolves `subject_id` through
  `GET /api/autolaunch/v1/agent/subjects/by-token/{token}`. Card owner/registry/token that contradict
  the receipt are `MISMATCH`. No autolaunch-audience session → `UNVERIFIABLE`.
- Mobile link: always `null` with an `UNVERIFIABLE` check row until Platform publishes
  the mobile identity-link contract.
- Exit code: `1` while no receipt exists (status `waiting`, as before) or when any
  check is `MISMATCH`; otherwise `0`.
- Missing from sibling APIs (links stay null/empty until added):
  - Autolaunch: the agent card does not expose a distinct `launch_id`
    (only `existing_token.auction_id`); `autolaunch/docs/api-contract.openapiv3.yaml`
    should add `launch_id` to the agent card.
  - Autolaunch contract drift: `GET /api/autolaunch/v1/agent/agents` is typed as `LooseListEnvelope`
    with a `data` array, but the server returns the list under `items`
    (`agent_controller.ex`). The CLI reads `items ?? data` until the contract matches
    the server.
  - Platform Techtree links: no agent-scoped listing for authored `node_ids`, `bbh_run_ids`, or
    `review_ids`; Platform should add those to `identity_links.techtree`.
  - Platform: served through the Platform session only; an agent-SIWA equivalent of the
    projection would let one SIWA sign-in cover it.
  - One SIWA session carries one audience, so a single run cannot verify every product link
    at once. A multi-audience session store would remove that limit.

## Required sibling-repo entries (do not implement from this repo)

- `platform/cli-contract.yaml`: add `regents regent-staking verify`
  (positional `<address>` optional; flags: `--rpc-url`, `--json`) with
  `transport.operationIds: [getAgentRegentStakingOverview, getAgentRegentStakingAccount]`
  and availability `current` (it is a `regent-staking ` platform public command).
- API gaps to file with owners: staking read ABI (platform), agent activity summary
  (techtree), agent card `launch_id` (autolaunch), and the
  `LooseListEnvelope` drift on `GET /api/autolaunch/v1/agent/agents` — contract declares `data`,
  server returns `items` (autolaunch).

Once an owning contract gains its entry, the implementation follows the standard flow:
contract YAML → `pnpm generate:cli-command-metadata` → route in
`packages/regents-cli/src/routes/` → command file → presenter → vitest with stubbed
fetch/RPC → `pnpm check:cli-contract`, `pnpm check:openapi`, `pnpm typecheck`,
`pnpm test`.
