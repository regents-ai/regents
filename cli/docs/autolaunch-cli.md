# Autolaunch CLI

Autolaunch is a command group inside `regents-cli`.

If you already have an agent, use `regents autolaunch ...`. If you do not have an agent yet, use [regents.sh](https://regents.sh) to make one.

The CLI consumes the reviewed Autolaunch API binding checked in at `packages/regents-cli/src/generated/autolaunch-openapi.ts`.

The `regent-staking` rail consumes the reviewed Platform API binding checked in at `packages/regents-cli/src/generated/platform-openapi.ts`.

Chain language for this command group:

- test and rehearsal launches use Base
- production launches use Base mainnet
- the `autolaunch` contract-linked path is Base only

The supported CLI surface is:

```bash
regents auth login --audience autolaunch
regents identity ensure
regents autolaunch ...
```

The separate company-token rewards rail is:

```bash
regents regent-staking ...
```

The product rules for this CLI surface are:

- recognized subject revenue is the configured Base USDC only
- that revenue only counts once it reaches the subject splitter
- launch operators should use the CLI-first flow
- launch participants should use the browser for auctions, claims, staking, and subject rewards
- Techtree evidence packets can support prelaunch readiness, but they do not decide launch eligibility in this version
- ingress is a receive-and-sweep wrapper, not a second accounting system
- the Regent-side fee lane is a treasury payout path, not part of the active launch rewards path
- subject output includes public revenue proof when available: source, chain, ingress account, revsplit contract, block number, amount, recipient lane, and whether the proof is fresh or stale

## Why Autolaunch exists

Use this framing when the question is strategic:

- an agent with real edge still dies if it cannot keep paying for compute, APIs, storage, retries, and distribution
- Autolaunch gives that agent a way to raise before those costs set the pace
- the sale builds operating runway, the treasury keeps funding room on hand, and the post-launch rewards path gives supporters a reason to stay
- the short version is: turn agent edge into runway

## Current product surface

The CLI pairs with the current Autolaunch site:

- command-first launch planning and monitoring
- market search, position search, and shareable filtered views
- live Regent staking status through `regents regent-staking ...`
- cleaner subject pages for staking, claims, revenue, ingress, and next actions
- a unified action panel pattern for wallet actions and prepared operator actions
- local Cachex hot reads for subject revenue and wallet position state

## Environment

- `AUTOLAUNCH_BASE_URL`
  Default: `http://127.0.0.1:4000`
- `AUTOLAUNCH_WALLET_ADDRESS`
  Optional website wallet address used by Safe setup commands.

Protected Autolaunch commands use the saved Autolaunch sign-in from `regents auth login --audience autolaunch` and the Agent account saved by `regents identity ensure`. An Agent account is a wallet, registry address, and token ID.

## Agent quick start

If you are operating Autolaunch as an agent, use the guided lifecycle through `regents autolaunch ...`.

From an installed package:

```bash
npm install -g @regentslabs/cli
regents auth login --audience autolaunch
regents identity ensure
regents autolaunch ...
```

From the source checkout:

```bash
pnpm --filter @regentslabs/cli exec regents autolaunch ...
```

Before a real launch, the Autolaunch launch node should pass:

```bash
mix autolaunch.doctor
AUTOLAUNCH_MOCK_DEPLOY=true mix autolaunch.smoke
```

After a real launch reaches `ready`, verify it with:

```bash
mix autolaunch.verify_deploy --job <job-id>
```

`mix autolaunch.doctor` is the stop sign for missing launch dependencies. In particular, it now catches a deploy binary that exists on disk but cannot actually run.

If Base-network congestion or node slowness makes a legitimate deploy run longer than expected, increase `AUTOLAUNCH_DEPLOY_TIMEOUT_MS` on the Autolaunch launch node. The default is `180000`.

The recommended agent order is:

```bash
regents autolaunch safe wizard --backup-signer-address <address>
regents autolaunch safe create --backup-signer-address <address> --website-wallet-address <address>
regents autolaunch prelaunch wizard --agent <agent-id> --name "Agent Coin Name" --symbol "AGENT" --agent-safe-address <safe-address> --connect-profile
regents autolaunch prelaunch validate --plan <id>
regents autolaunch prelaunch publish --plan <id>
regents autolaunch launch run --plan <id>
regents autolaunch launch monitor --job <job-id> --watch
regents autolaunch launch finalize --job <job-id> [--submit]
regents autolaunch vesting status --job <job-id>
```

Skip the Safe commands only when the agent Safe already exists and the launch plan already points to it.

For first-time walkthroughs and common-command guides, use the public Autolaunch guides at `/learn/autolaunch/` on regents.sh.

## Fixed economic rules

The launch shape is fixed:

- 10% of the 100 billion supply is sold in the auction
- 5% is reserved for LP migration
- 85% vests to the agent treasury over one year
- half of the auction $REGENT funds LP migration
- the other half of the auction $REGENT goes to the agent Safe for operating runway

The fee rules are fixed too:

- the official launch pool charges a fixed 2% fee
- that 2% split is fixed at 1% to Regent and 1% to the agent treasury
- recognized subject revenue records 1% for Regent staking
- 10% of the remaining 99% waits as pending buyback USDC for the agent treasury
- the remaining 89.1% is governed by the live eligible revenue share
- that live share decides how much stays in the staker-eligible lane and how much goes straight into the subject reserve lane

## Primary operator journey

The main Autolaunch product is a guided lifecycle.

Start here:

```bash
regents autolaunch prelaunch wizard
regents autolaunch connect start [--plan <id>] [--watch]
regents autolaunch prelaunch validate [--plan <id>]
regents autolaunch prelaunch publish [--plan <id>]
regents autolaunch launch run [--plan <id>]
regents autolaunch launch monitor --job <job-id> [--watch]
regents autolaunch launch finalize --job <job-id> [--submit]
regents autolaunch vesting status --job <job-id>
regents autolaunch vesting release --job <job-id> [--submit]
regents autolaunch vesting propose-beneficiary-rotation --job <job-id> --beneficiary <address> [--json]
regents autolaunch vesting cancel-beneficiary-rotation --job <job-id> [--json]
regents autolaunch vesting execute-beneficiary-rotation --job <job-id> [--json]
```

These commands assume the Phoenix backend is alive and act as the guided operator front door.

### Prelaunch

```bash
regents autolaunch prelaunch wizard \
  --agent <agent-id> \
  --name "Agent Coin Name" \
  --symbol "AGENT" \
  --agent-safe-address <safe-address> \
  [--title <text>] \
  [--subtitle <text>] \
  [--description <text>] \
  [--website-url <url>] \
  [--image-url <url>] \
  [--connect-profile]

regents autolaunch connect start [--plan <id>] [--label <text>] [--watch]
regents autolaunch prelaunch get [--plan <id>]
regents autolaunch prelaunch validate [--plan <id>]
regents autolaunch prelaunch publish [--plan <id>]
```

`prelaunch wizard` creates or updates the saved launch draft, uploads the hosted image if needed, validates the draft, and saves the canonical local copy under the CLI state directory.

Use `--connect-profile` when the human operator should confirm the agent from the browser during planning. The CLI prints a short code, a connection URL, the expiry time, and the agent identity summary. The connection is recommended before publish, but a missing profile connection warns rather than blocking v1 launch setup.

There are two profile connection directions:

- Web starts, CLI completes: `regents autolaunch pair --code <pairing-code>`.
- CLI starts, web confirms: `regents autolaunch connect start [--plan <id>] [--watch]`.

The credibility step belongs inside plan creation after name, ticker, image, and Safe, and before validate or publish. Agent sign-in and saved Agent identity are required before plan creation. Profile connection, ENS, World / AgentBook, and X are trust signals to review before publish when possible.

Prelaunch plans can carry a Techtree evidence packet reference. Readiness output should show that evidence as supporting context only; operators still decide whether the launch story is strong enough.

### Launch lifecycle

```bash
regents autolaunch launch run [--plan <id>] [--wallet-address <address>] [--watch] [--interval <seconds>]
regents autolaunch launch monitor --job <job-id> [--watch] [--interval <seconds>]
regents autolaunch launch finalize --job <job-id> [--submit]
regents autolaunch vesting status --job <job-id>
regents autolaunch vesting release --job <job-id> [--submit]
```

`launch run` loads the saved plan, revalidates it, obtains the SIWA signature bundle, queues the launch, and immediately reads back the job state.

`launch monitor` uses the lifecycle API to answer:

- whether migration is ready
- whether token sweep is ready
- whether currency sweep is ready
- whether vesting release is ready
- what action is recommended next

`launch finalize` is the preferred post-auction path. It either returns the prepared next transaction or, with `--submit`, sends it through the configured signer and registers the resulting transaction hash.

`vesting status` is the preferred read surface for the vesting wallet. `vesting release` is still available directly when the release path is ready.

## Advanced command groups

Everything below is advanced or later-lifecycle tooling. Treat the guided lifecycle as the main path for agents.

## REGENT staking rail

`regent-staking` is the separate Base-mainnet rewards rail for the existing `$REGENT` token. It is not the same thing as the per-agent subject splitter flow.

Use it when Regent income has already reached Base USDC:

```bash
regents regent-staking get
regents regent-staking account <wallet-address>
regents regent-staking stake --amount <regent-amount> [--receiver <0xaddress>]
regents regent-staking unstake --amount <regent-amount>
regents regent-staking claim-usdc
```

Operational rule for v1:

- non-Base Regent income still lands in Treasury A first
- Treasury A bridges that income manually to Base USDC
- treasury-side deposits and treasury withdrawals are done through the safe or the deployment script flow, not through the CLI
- the staking contract pays the configured staker share to `$REGENT` stakers and leaves the rest accruing for treasury withdrawal
- staked `$REGENT` participates in deposits made to this separate pool; it is not a guaranteed yield claim

### Agents

```bash
regents autolaunch agents list [--launchable] [--json]
regents autolaunch agent <agent-id> [--json]
regents autolaunch agent readiness <agent-id> [--json]
```

For read surfaces, trust data now lives under the nested `trust` object:

- auction list items use `item.trust.erc8004`, `item.trust.ens`, `item.trust.world`, and `item.trust.x`
- single auction detail uses `auction.trust.erc8004`, `auction.trust.ens`, `auction.trust.world`, and `auction.trust.x`
- agent detail and readiness responses include trust fields when available

### Low-level launches

```bash
regents autolaunch launch run \
  [--plan <id>] \
  [--wallet-address <address>] \
  [--watch] \
  [--interval <seconds>] \
  [--json]

regents autolaunch jobs watch <job-id> [--watch] [--interval <seconds>] [--json]
```

Autolaunch launch creation accepts only Base.

Successful launch output now includes the live V2 stack fields:

- `strategy_address`
- `vesting_wallet_address`
- `hook_address`
- `launch_fee_registry_address`
- `launch_fee_vault_address`
- `subject_registry_address`
- `subject_id`
- `revenue_share_splitter_address`
- `default_ingress_address`
- `pool_id`

Autolaunch still does not route the launch fee lane automatically into REGENT rewards. The Regent-side launch fee lane is still a direct treasury payout. The separate Base `regent-staking` rail can be funded manually after bridging and also receives the fixed subject-revenue skim.

`launch preview`, `launch create`, and `jobs watch` return a `reputation_prompt` object in the JSON payload. It is the CLI-safe version of the optional follow-up step shown in the web app:

- It explains that linking ENS and connecting a human World ID are optional trust improvements.
- It includes the warning that skipping those steps can leave the launch looking less trusted.
- It carries the current instructions and, when available, direct links for the ENS and World follow-up pages.

### Auctions

```bash
regents autolaunch auctions list \
  [--sort hottest|recently_launched|expired] \
  [--status active|expired] \
  [--chain <chain-id>] \
  [--mine-only] \
  [--json]

regents autolaunch auction <auction-id> [--json]
```

### Bids

```bash
regents autolaunch bids quote \
  --auction <auction-id> \
  --amount <regent-amount> \
  --max-price <regent-price> \
  [--json]
```

Placing, exiting, and claiming bids happens in the Autolaunch web app.

### Subjects

```bash
regents autolaunch subjects get <subject-id> [--json]
regents autolaunch subjects ingress <subject-id> [--json]
regents autolaunch subjects sweep-ingress <subject-id> --address <ingress-address> [--json]
```

Subject reads use the signed Autolaunch agent API. Subject staking and claims happen in the Autolaunch web app.

### Contract reads

```bash
regents autolaunch contracts admin [--json]
regents autolaunch contracts job --job <job-id> [--json]
regents autolaunch contracts subject --subject <subject-id> [--json]
```

These commands expose the same read model that powers the `/contracts` page in the Phoenix app.

### Prepare-only contract actions

```bash
regents autolaunch strategy migrate --job <job-id> [--json]
regents autolaunch auction claim-unused-tokens --job <job-id> [--json]
regents autolaunch strategy sweep-token --job <job-id> [--json]
regents autolaunch strategy sweep-quote-token --job <job-id> [--json]
regents autolaunch vesting release --job <job-id> [--json]

regents autolaunch fee-registry get --job <job-id> [--json]

regents autolaunch fee-vault get --job <job-id> [--json]
regents autolaunch fee-vault withdraw-regent --job <job-id> --currency <address> --amount <raw-units> --recipient <address> [--json]

regents autolaunch splitter get --subject <subject-id> [--json]
regents autolaunch splitter set-paused --subject <subject-id> --paused true|false [--json]
regents autolaunch splitter set-label --subject <subject-id> --label <text> [--json]
regents autolaunch splitter propose-treasury-recipient-rotation --subject <subject-id> --recipient <address> [--json]
regents autolaunch splitter cancel-treasury-recipient-rotation --subject <subject-id> [--json]
regents autolaunch splitter execute-treasury-recipient-rotation --subject <subject-id> [--json]
regents autolaunch splitter sweep-treasury-residual --subject <subject-id> --amount <raw-units> [--json]
regents autolaunch splitter reassign-dust --subject <subject-id> --amount <raw-units> [--json]

regents autolaunch ingress create --subject <subject-id> --label <text> [--make-default true|false] [--json]
regents autolaunch ingress set-default --subject <subject-id> --address <ingress-address> [--json]
regents autolaunch ingress set-label --subject <subject-id> --address <ingress-address> --label <text> [--json]
regents autolaunch ingress rescue --subject <subject-id> --address <ingress-address> --token <address> --amount <raw-units> --recipient <address> [--json]
regents autolaunch subjects buybacks <subject-id> [--json]
regents autolaunch subjects payment-links <subject-id> [--json]
regents autolaunch payment-links create --subject <subject-id> --label <text> --salt <bytes32> [--canonical] [--submit] [--json]
regents autolaunch payment-links set-canonical --subject <subject-id> --address <receiver> --canonical true|false [--submit] [--json]
regents autolaunch payment-links set-state --subject <subject-id> --address <receiver> --active true|false [--replacement <receiver>] [--submit] [--json]

regents autolaunch registry get --subject <subject-id> [--json]
regents autolaunch registry set-subject-manager --subject <subject-id> --account <address> --enabled true|false [--json]
regents autolaunch registry link-identity --subject <subject-id> --identity-chain-id <id> --identity-registry <address> --identity-agent-id <id> [--json]
regents autolaunch registry rotate-safe --subject <subject-id> --new-safe <address> [--json]

regents autolaunch factory revenue-share set-authorized-creator --account <address> --enabled true|false [--json]
regents autolaunch factory revenue-ingress set-authorized-creator --account <address> --enabled true|false [--json]
```

These commands do not sign or broadcast. They return prepared transaction payloads so operators can submit them through the right signer or multisig flow.

## JSON contract

The CLI is JSON-first. It forwards directly to the `autolaunch` Phoenix JSON API:

- `GET /api/autolaunch/v1/agent/agents`
- `GET /api/autolaunch/v1/agent/agents/{id}`
- `GET /api/autolaunch/v1/agent/agents/{id}/readiness`
- `GET /api/autolaunch/v1/agent/prelaunch/plans`
- `POST /api/autolaunch/v1/agent/prelaunch/plans`
- `GET /api/autolaunch/v1/agent/prelaunch/plans/{id}`
- `PATCH /api/autolaunch/v1/agent/prelaunch/plans/{id}`
- `POST /api/autolaunch/v1/agent/prelaunch/plans/{id}/validate`
- `POST /api/autolaunch/v1/agent/prelaunch/plans/{id}/publish`
- `POST /api/autolaunch/v1/agent/prelaunch/plans/{id}/launch`
- `POST /api/autolaunch/v1/agent/prelaunch/assets`
- `POST /api/autolaunch/v1/agent/prelaunch/plans/{id}/metadata`
- `GET /api/autolaunch/v1/agent/prelaunch/plans/{id}/metadata-preview`
- `POST /api/autolaunch/v1/agent/launch/jobs`
- `GET /api/autolaunch/v1/agent/launch/jobs/{id}`
- `GET /api/autolaunch/v1/agent/lifecycle/jobs/{id}`
- `POST /api/autolaunch/v1/agent/lifecycle/jobs/{id}/finalize/prepare`
- `POST /api/autolaunch/v1/agent/lifecycle/jobs/{id}/finalize/register`
- `GET /api/autolaunch/v1/agent/lifecycle/jobs/{id}/vesting`
- `GET /api/autolaunch/v1/agent/auctions`
- `GET /api/autolaunch/v1/agent/auction-returns`
- `GET /api/autolaunch/v1/agent/auctions/{id}`
- `POST /api/autolaunch/v1/agent/auctions/{id}/bid_quote`
- `GET /api/autolaunch/v1/agent/subjects/{id}`
- `GET /api/autolaunch/v1/agent/subjects/{id}/ingress`
- `GET /api/autolaunch/v1/app/contracts/admin`
- `GET /api/autolaunch/v1/agent/contracts/jobs/{id}`
- `GET /api/autolaunch/v1/agent/contracts/subjects/{id}`
- `POST /api/autolaunch/v1/agent/contracts/jobs/{id}/{resource}/{action}/prepare`
- `POST /api/autolaunch/v1/agent/contracts/subjects/{id}/{resource}/{action}/prepare`
- `POST /api/autolaunch/v1/agent/contracts/admin/{resource}/{action}/prepare`

Contract prepare commands return a prepared transaction payload and leave signing or submission to the caller. Contract admin reads use the signed-in app route.

Polling commands validate `--interval` and require a positive number.

Auction payloads also include the current trust fields used by listings:

- `ens_attached`
- `world_registered`
- `world_human_id`
- `world_launch_count`

## What has to be alive

The CLI is not a standalone contract client for Autolaunch. It depends on a live Phoenix backend.

That backend must have:

- Phoenix running
  The CLI uses it for session exchange, authenticated launch and subject flows, quote reads, contract-read aggregation, and prepared transaction generation.
- Postgres running
  Launch jobs, bids, and subject action registrations are persisted there.
- launch-chain RPC configured and reachable
  The backend needs it for launch-state reads, bid verification, and subject verification.
- the shared SIWA verification path reachable
  Launch creation depends on backend-side signature verification.
- the Foundry deploy binary and deploy workdir present on the backend node
  Without those, launch creation can queue but cannot actually execute.

Trust follow-up commands use the current trust-network configuration. Core launch, auction, subject, and contract-console flows use their own configured inputs.
