# Regents CLI Command List

This file lists the full command surface shipped by the standalone Regents CLI in this repo.

Sources used: repository-local route registries and `docs/shared-cli-contract.yaml` via `scripts/generate-cli-command-metadata.mjs`.

Total commands: 220.

## Full Command List

### Agent

- `regents agent chat` - Send one message to a hosted Hermes agent and print the reply.
- `regents agent connect hosted-hermes` - Inspect one hosted Hermes runtime for a Regent.
- `regents agent connect openclaw` - Connect a local OpenClaw worker to one Regent.
- `regents agent execution-pool` - List the workers available to one manager.
- `regents agent harness list` - List harness.
- `regents agent init` - Set up agent.
- `regents agent link` - Link one manager to one worker for a Regent.
- `regents agent profile get` - Show profile.
- `regents agent profile list` - List profile.
- `regents agent status` - Show agent status.

### Agent Context

- `regents agent-context` - Print the safe command and setup context for another agent.

### Agentbook

- `regents agentbook lookup` - Show the saved human-backed trust summary for the current Regent agent identity.
- `regents agentbook register` - Start a hosted human-backed trust flow for the saved Regent agent identity.
- `regents agentbook sessions watch` - Poll one hosted human-backed trust session for the saved Regent agent identity.

### Auth

- `regents auth login` - Sign in for protected Regent commands.
- `regents auth logout` - Sign out on this machine.
- `regents auth status` - Show the current saved sign-in.

### Autolaunch

- `regents autolaunch agent <id>` - Show Autolaunch agent.
- `regents autolaunch agent readiness <id>` - Show agent readiness.
- `regents autolaunch agents list` - List agents.
- `regents autolaunch auction <id>` - Show Autolaunch auction.
- `regents autolaunch auction claim-unused-tokens` - Claim unused tokens for auction.
- `regents autolaunch auction-returns list` - List auction returns.
- `regents autolaunch auctions list` - List auctions.
- `regents autolaunch bids quote` - Quote bids.
- `regents autolaunch chat list` - List chat.
- `regents autolaunch chat read <scope>` - Show Autolaunch chat read.
- `regents autolaunch chat send <scope>` - Show Autolaunch chat send.
- `regents autolaunch chat subscribe add <scope>` - Add a scope to the saved Autolaunch chat subscriptions.
- `regents autolaunch chat subscribe list` - List the saved Autolaunch chat subscriptions.
- `regents autolaunch chat subscribe remove <scope>` - Remove a scope from the saved Autolaunch chat subscriptions.
- `regents autolaunch chat tail [scope...]` - Watch chat [scope...].
- `regents autolaunch chat unread [scope...]` - Show new chat messages since the saved cursors.
- `regents autolaunch connect start` - Start connect.
- `regents autolaunch contracts admin` - Show Autolaunch contracts admin.
- `regents autolaunch contracts job` - Show Autolaunch contracts job.
- `regents autolaunch contracts subject` - Show Autolaunch contracts subject.
- `regents autolaunch contracts verify` - Check contracts.
- `regents autolaunch dm <subject-id|address>` - Show Autolaunch dm.
- `regents autolaunch dm list` - List dm.
- `regents autolaunch ens plan` - Show Autolaunch ENS plan.
- `regents autolaunch ens prepare-bidirectional` - Prepare bidirectional for ENS.
- `regents autolaunch ens prepare-ensip25` - Prepare ensip25 for ENS.
- `regents autolaunch ens prepare-erc8004` - Prepare erc8004 for ENS.
- `regents autolaunch factory revenue-ingress set-authorized-creator` - Set authorized creator for factory revenue ingress.
- `regents autolaunch factory revenue-share set-authorized-creator` - Set authorized creator for factory revenue share.
- `regents autolaunch fee-registry get` - Show fee registry.
- `regents autolaunch fee-vault get` - Show fee vault.
- `regents autolaunch fee-vault withdraw-regent` - Withdraw fee vault.
- `regents autolaunch identities list` - List identities.
- `regents autolaunch identities mint` - Create identities.
- `regents autolaunch ingress create` - Create ingress.
- `regents autolaunch ingress rescue` - Rescue ingress.
- `regents autolaunch ingress set-default` - Set default for ingress.
- `regents autolaunch ingress set-label` - Set label for ingress.
- `regents autolaunch jobs watch` - Watch jobs.
- `regents autolaunch launch finalize` - Finalize launch.
- `regents autolaunch launch monitor` - Watch launch.
- `regents autolaunch launch run` - Run launch.
- `regents autolaunch pair` - Pair Autolaunch.
- `regents autolaunch payment-links create` - Create payment links.
- `regents autolaunch payment-links set-canonical` - Set canonical for payment links.
- `regents autolaunch payment-links set-state` - Set state for payment links.
- `regents autolaunch prelaunch get` - Show prelaunch.
- `regents autolaunch prelaunch publish` - Publish prelaunch.
- `regents autolaunch prelaunch validate` - Check prelaunch.
- `regents autolaunch prelaunch wizard` - Open prelaunch wizard.
- `regents autolaunch registry get` - Show registry.
- `regents autolaunch registry link-identity` - Link identity for registry.
- `regents autolaunch registry rotate-safe` - Rotate safe for registry.
- `regents autolaunch registry set-subject-manager` - Set subject manager for registry.
- `regents autolaunch safe create` - Create safe.
- `regents autolaunch safe wizard` - Open safe wizard.
- `regents autolaunch splitter accept-ownership` - Accept ownership for splitter.
- `regents autolaunch splitter activate-eligible-revenue-share` - Activate eligible revenue share for splitter.
- `regents autolaunch splitter cancel-eligible-revenue-share` - Cancel eligible revenue share for splitter.
- `regents autolaunch splitter cancel-treasury-recipient-rotation` - Cancel treasury recipient rotation for splitter.
- `regents autolaunch splitter execute-treasury-recipient-rotation` - Execute treasury recipient rotation for splitter.
- `regents autolaunch splitter get` - Show splitter.
- `regents autolaunch splitter propose-eligible-revenue-share` - Propose eligible revenue share splitter.
- `regents autolaunch splitter propose-treasury-recipient-rotation` - Propose treasury recipient rotation splitter.
- `regents autolaunch splitter reassign-dust` - Show Autolaunch splitter reassign dust.
- `regents autolaunch splitter set-label` - Set label for splitter.
- `regents autolaunch splitter set-paused` - Set paused for splitter.
- `regents autolaunch splitter sweep-treasury-reserved` - Sweep treasury reserved for splitter.
- `regents autolaunch splitter sweep-treasury-residual` - Sweep treasury residual for splitter.
- `regents autolaunch strategy migrate` - Migrate strategy.
- `regents autolaunch strategy sweep-quote-token` - Sweep quote token for strategy.
- `regents autolaunch strategy sweep-token` - Sweep token for strategy.
- `regents autolaunch subjects buybacks` - Show Autolaunch subjects buybacks.
- `regents autolaunch subjects by-token` - Show Autolaunch subjects by token.
- `regents autolaunch subjects get` - Show subjects.
- `regents autolaunch subjects ingress` - Show Autolaunch subjects ingress.
- `regents autolaunch subjects payment-links` - Show Autolaunch subjects payment links.
- `regents autolaunch subjects staking` - Show Autolaunch subjects staking.
- `regents autolaunch subjects sweep-ingress` - Sweep ingress for subjects.
- `regents autolaunch subjects verify` - Check subjects.
- `regents autolaunch vesting cancel-beneficiary-rotation` - Cancel beneficiary rotation for vesting.
- `regents autolaunch vesting execute-beneficiary-rotation` - Execute beneficiary rotation for vesting.
- `regents autolaunch vesting propose-beneficiary-rotation` - Propose beneficiary rotation vesting.
- `regents autolaunch vesting release` - Release vesting.
- `regents autolaunch vesting status` - Show vesting status.

### Budget

- `regents budget grant` - Give an agent a spending budget.
- `regents budget ledger` - Show budget activity.
- `regents budget revoke` - Revoke an agent budget.
- `regents budget status` - Show the current budget state.

### Bug

- `regents bug` - Send a signed bug report to Platform.

### Chat

- `regents chat follows add <wallet|label>` - Add a wallet or label to the saved chat follow list.
- `regents chat follows list` - List the saved chat follow list.
- `regents chat follows remove <wallet|label>` - Remove a wallet or label from the saved chat follow list.

### Commands

- `regents commands list` - List every shipped Regents CLI command with its summary, flags, and args.

### Config

- `regents config get` - Show local Regent configuration.
- `regents config write` - Save local Regent configuration.

### Doctor

- `regents doctor` - Check local Regent readiness.
- `regents doctor auth` - Show doctor auth.
- `regents doctor contracts` - Show doctor contracts.
- `regents doctor runtime` - Show doctor runtime.
- `regents doctor transports` - Show doctor transports.
- `regents doctor workspace` - Show doctor workspace.

### Ens

- `regents ens set-primary` - Set the primary ENS name.

### Feynman

- `regents feynman` - Open the Feynman research shell.

### Gossipsub

- `regents gossipsub status` - Show gossipsub status.

### Identity

- `regents identity ensure` - Set up or confirm the local Agent identity.
- `regents identity graph` - Show linked identity records.
- `regents identity status` - Show local identity readiness.

### Init

- `regents init` - Set up Regent on this machine and report what is ready.

### Mcp

- `regents mcp doctor` - Check MCP setup.
- `regents mcp export codex` - Print MCP setup for Codex.
- `regents mcp serve` - Start the Regents MCP server.
- `regents mcp tools list` - List tools.

### Platform

- `regents platform auth login` - Sign in to the Regent website from the terminal and save the session for later platform commands.
- `regents platform auth logout` - Delete the saved platform session and sign out from platform commands.
- `regents platform auth status` - Show who is signed in through the saved platform session.
- `regents platform billing account` - Show the billing account tied to the saved platform session.
- `regents platform billing spend-controls set` - Save monthly hosting, model usage, and automatic credit top-up settings.
- `regents platform billing topup` - Start a Stripe checkout that adds shared runtime credit.
- `regents platform billing usage` - Show shared runtime credit and regent usage from the saved platform session.
- `regents platform formation doctor` - Explain why regent opening is blocked or what is ready next.
- `regents platform formation status` - Show launch readiness from the saved session, including claimed names, billing, and owned regents.
- `regents platform projection` - Show the canonical Platform projection for product and mobile clients.
- `regents platform regent pause` - Pause the hosted runtime for one owned regent.
- `regents platform regent resume` - Resume the hosted runtime for one owned regent.
- `regents platform regent runtime` - Show runtime state for one owned regent from the saved platform session.

### Plugin

- `regents plugin doctor` - Check plugin setup.
- `regents plugin install` - Install a Regent plugin for the selected runtime.
- `regents plugin status` - Show installed Regent plugins.

### Receipt

- `regents receipt create` - Create a payment receipt record.
- `regents receipt get` - Show receipt.
- `regents receipt list` - List receipt.
- `regents receipt share-draft` - Draft shareable receipt details.

### Regent Staking

- `regents regent-staking account` - Show Regent staking state for one wallet.
- `regents regent-staking claim-and-restake-regent` - Prepare a wallet action to claim and restake REGENT rewards.
- `regents regent-staking claim-regent` - Prepare a wallet action to claim REGENT rewards.
- `regents regent-staking claim-usdc` - Prepare a wallet action to claim staking USDC.
- `regents regent-staking get` - Show Regent staking state for the saved Agent account.
- `regents regent-staking stake` - Prepare a wallet action to stake REGENT.
- `regents regent-staking unstake` - Prepare a wallet action to unstake REGENT.
- `regents regent-staking verify` - Check Regent staking state against the staking contract for a wallet.

### Run

- `regents run` - Start local Regent access for agents and terminal commands.

### Runtime

- `regents runtime checkpoint` - Save a checkpoint for one runtime.
- `regents runtime create` - Create a runtime for one Regent.
- `regents runtime get` - Show one runtime for a Regent.
- `regents runtime health` - Show health for one runtime.
- `regents runtime pause` - Pause one runtime for a Regent.
- `regents runtime policy` - Show runtime policy settings.
- `regents runtime restore` - Restore one runtime from a checkpoint.
- `regents runtime resume` - Resume one runtime for a Regent.
- `regents runtime services` - List services for one runtime.
- `regents runtime status` - Show runtime status.
- `regents runtime tools` - List runtime tools.

### Security Report

- `regents security-report` - Send a signed security report to Platform.

### Service

- `regents service catalog check` - Show the catalog readiness checklist for one paid agent service.
- `regents service init` - Create or update the owner setup for one paid agent service.
- `regents service logs` - Show redacted operation logs for one owned paid agent service.
- `regents service pause` - Pause one listed paid agent service.
- `regents service price set` - Save x402 pricing terms for one paid agent service.
- `regents service publish` - Publish one ready paid agent service to the public catalog.
- `regents service resume` - Resume one paused paid agent service after readiness checks pass.
- `regents service runs` - Show run history for one owned paid agent service.
- `regents service test` - Run a sandbox test before launching a scientific operator.

### Settings

- `regents settings` - Show local Regent configuration. Alias for regents config get.

### Setup

- `regents setup` - Interactive setup wizard on a terminal: detects agent runtimes (Hermes, OpenClaw, Claude Code, Codex) and registers the regents MCP server. Use regents plugin install --runtime ... for Hermes and OpenClaw tools. With --runtime, --json, or no terminal it prints the read-only status report. --quick applies missing pieces without prompting.

- `regents setup skills` - Install recommended Regent skills.

### Status

- `regents status` - Show whether this machine is ready to use Regent.

### Techtree

- `regents techtree forge family show` - Show the one planned deterministic contract-drift repair family.
- `regents techtree forge family validate` - Validate the closed family contract and a one-file SKILL.md change.
- `regents techtree notebooks init` - Set up notebooks.
- `regents techtree notebooks pair` - Pair notebooks.
- `regents techtree uplift report` - Compare a non-empty set of receipt-backed local receipts and archive the uplift report and never-executed reproduction package; human output leads with the measured result and evidence strength.
- `regents techtree verify receipt show` - Show and verify an immutable local evaluation receipt.
- `regents techtree verify run` - Run the built-in matched Verify comparison and emit local receipts.
- `regents techtree verify status` - Show a local Verify comparison without changing it.

### Update

- `regents update` - Update the Regents CLI in place via npm. Defaults to the latest published release; --version installs a specific one. With --check it only reports the installed and latest versions without changing anything.


### Version

- `regents version` - Print the installed Regents CLI version. Also available as --version.

### Voice

- `regents voice serve` - Show voice serve.

### Wallet

- `regents wallet agentic balance` - Show the Agent wallet balance.
- `regents wallet agentic fund` - Show how to fund the Agent wallet.
- `regents wallet agentic login` - Sign in with the Agent wallet.
- `regents wallet agentic status` - Show Agent wallet readiness.
- `regents wallet agentic verify` - Verify the Agent wallet sign-in.
- `regents wallet import` - Show wallet import.
- `regents wallet setup` - Set up the local wallet path.
- `regents wallet status` - Show wallet readiness.

### Whoami

- `regents whoami` - Show the local Agent account and saved sign-in context.

### Work

- `regents work cancel` - Cancel one work run.
- `regents work create` - Create work for one Regent.
- `regents work get` - Show one work item for a Regent.
- `regents work list` - List work for one Regent.
- `regents work local-loop` - Let one local worker check for assigned Regent work.
- `regents work retry` - Start a new attempt for one work run.
- `regents work run` - Start a run for one work item.
- `regents work watch` - Watch events for one work run.

### X402

- `regents x402 details` - Show paid endpoint details.
- `regents x402 fetch` - Fetch a paid x402 result.
- `regents x402 pay` - Pay an x402 endpoint.
- `regents x402 prepare` - Prepare an x402 paid request.
- `regents x402 quote` - Quote an x402 paid request.
- `regents x402 receipts get` - Show receipts.
- `regents x402 refund` - Request an x402 refund.
- `regents x402 search` - Search for x402 services.
