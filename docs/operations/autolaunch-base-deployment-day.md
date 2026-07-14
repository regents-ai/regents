# Autolaunch Base deployment day

Status: **NO-GO. Do not broadcast or sign an Autolaunch deployment today.**

This is the protected deployment-day gate for Autolaunch. It is intentionally a
gated template, not an executable production command. The exact broadcast packet
is added only after the current source, security findings, external addresses,
Safe roles, rehearsal output, and Ash chain manifest have all been independently
reviewed.

## Why deployment is blocked

The canonical Ash contract source is
`/Users/sean/Documents/regent/ash-platform/contracts/chain-contracts.yaml`. It
currently admits staking and redemption evidence only. It admits no Autolaunch
contract and `admitted_prepared_actions` is empty.

The Autolaunch Solidity workspace under
`/Users/sean/Documents/regent/platform/contracts` is quarantined historical
evidence. Its scripts and tests are useful inputs, but that repository is not the
active product authority and must not be deployed directly from its current
working tree.

These closure tickets are mandatory before a production packet can exist:

- `regent-ctzr`: remove stale oracle and buyback deployment instructions.
- `regent-8ici`: disposition every current Solidity security finding.
- `regent-qccf`: reproduce the current source in a clean deployment rehearsal.
- `regent-ygdg`: attest every external Base address and its bytecode.
- `regent-ekpv`: approve and prove the Safe ownership model and acceptances.
- `regent-gnaq`: admit the reviewed contracts and actions to the canonical Ash
  chain manifest.

Local evidence reproduced by the orchestrator on 2026-07-14:

- `forge fmt --check src test scripts` passed.
- Offline build passed with the configured Solidity versions.
- `forge test --offline` passed: **314 passed, 0 failed, 0 skipped**, including
  fuzz and invariant runs.
- Coverage completed with many source-anchor warnings. Totals were **77.84% lines,
  78.04% statements, 11.29% branches, and 74.97% functions**. The warnings and
  low branch coverage remain an acceptance gate.
- `slither . --exclude-dependencies` completed with **24 raw detector results**.
  They are untriaged. No severity summary or security approval exists for this
  run. Every result needs an independent disposition before deployment.

Green tests do not override the missing manifest authority or unresolved security
review.

## Network target and evidence boundary

Base mainnet is the intended production target. Its chain ID is `8453`, as
published in [Base network information](https://docs.base.org/base-chain/network-information/).

Locally pinned REGENT, USDC, staking, Safe, CCA, Uniswap, and factory addresses
are evidence only. None is an authorized deployment input until the address and
code evidence is attested, the Safe model is approved, and the exact values are
admitted to the active Ash chain manifest.

Base publishes connection details at
[Connecting to Base](https://docs.base.org/base-chain/quickstart/connecting-to-base).

## Historical deployment shape to reconcile

The historical scripts describe two separate operations.

### Shared infrastructure

`DeployAutolaunchInfra.s.sol` deploys, in order:

1. `SubjectRegistry`
2. `RegentStakingRevenueRouter`
3. `RevenueShareSplitterV2Deployer`
4. `RevenueShareFactory`
5. `RevenueIngressFactory`
6. `PermissionlessExistingTokenRevenueFactory`
7. `DeferredAutolaunchFactory`
8. `RegentLBPStrategyFactory`

It then grants required registrar and creator permissions. A separate
`PaymentLinkFactory` was documented historically but is not part of this script.
That difference must be resolved in the current source rehearsal.

### One launch

`ExampleCCADeploymentScript.s.sol` temporarily authorizes a launch controller,
creates the token, auction, vesting wallet, strategy, fee contracts, splitter,
ingress, pool identity, and subject identity, and then revokes the controller's
temporary permissions.

The current historical allocation is 10% public sale, 5% liquidity reserve, and
85% one-year vesting. These economics are not approved production values merely
because they appear in the old script.

## Release packet required before deployment day

One immutable packet must contain all of the following:

- Reviewed source commit and release tag from a clean checkout.
- Exact compiler, optimizer, Foundry, and dependency versions.
- Canonical Ash chain-manifest hash, evidence hash, ABI hashes, creation bytecode
  hashes, and runtime bytecode hashes.
- Full, checksummed addresses for every dependency and role.
- Constructor arguments, configuration values, deployment order, expected
  transaction count, expected nonce range, and expected gas ceiling.
- Decoded calldata for every non-constructor call.
- Exact expected events, state changes, token flows, permissions, owners, pending
  owners, beneficiaries, and balances.
- Local and exact-state fork simulation output.
- Fresh Foundry, invariant, Slither, and manual-review evidence.
- A reviewed coverage report with the source-anchor warnings resolved or accepted
  and branch coverage accepted against the release criteria.
- Independent security approval and independent deployment-packet approval.
- Founder approval for this exact packet, not a general approval to deploy.

The packet must not contain a private key, seed phrase, hardware-wallet recovery
material, or plaintext signing credential.

## Safe rehearsal commands with no signing or broadcast

Run these only in the clean rehearsal checkout named by `regent-qccf`. They do
not require an RPC URL or wallet:

```sh
cd /path/to/reviewed-autolaunch-contracts
forge fmt --check src test scripts
forge build --offline
forge test --offline
slither . --exclude-dependencies
```

Slither usage and detector guidance live in the
[official Slither documentation](https://github.com/crytic/slither/wiki/Usage).

The exact dry-run command is generated by `regent-qccf` after the clean source and
public inputs are frozen. It must omit `--broadcast`. Foundry runs local and
onchain simulation before optional broadcasting; see
[Foundry deployment and scripting](https://getfoundry.sh/forge/deploying/) and
[Foundry security best practices](https://getfoundry.sh/tutorials/best-practices/).

No `--broadcast`, `cast send`, Safe proposal, or wallet prompt belongs in this
document until the release packet passes all gates.

## Deployment-day procedure after all gates close

### 1. Open the change window

- Confirm all six closure tickets above are closed with immutable evidence.
- Confirm the canonical manifest and release packet hashes on two independent
  machines.
- Confirm Base chain `8453`, the exact expected deployment nonce, current base
  fee, deployer ETH balance, and no competing pending transaction.
- Confirm all Safes' full addresses, owners, thresholds, nonces, modules, guards,
  fallback handlers, and pending transactions.
- Establish a deployment operator, Safe proposer, independent reviewer, Safe
  signers, and evidence recorder. One person must not fill every role.

Stop if any value differs from the reviewed packet.

### 2. Re-run simulation

- Simulate from the exact intended block state and broadcaster.
- Compare transaction count, nonce sequence, created addresses, calldata, events,
  gas, permissions, owners, and balances against the packet.
- Run Safe simulation for every ownership-acceptance and governance transaction.
- Record the trace and state diff before requesting any signature.

Stop on any revert, unexpected call, `DELEGATECALL`, native value, approval,
recipient, permission, address, or balance change.

### 3. Founder go/no-go

Sean reviews the human-readable summary, exact hashes, full addresses, economics,
Safe configuration, simulations, maximum ETH cost, and irreversible effects. Approval
must name the exact release-packet hash.

### 4. Broadcast only the reviewed packet

The final runbook supplies one exact hardware-wallet or password-protected
keystore command. Do not use a plaintext private key or copy a command from the
quarantined Platform proposal. Do not use Foundry `--resume` without rechecking
nonce and state; Foundry documents that resume does not simulate the script again.

After every transaction, compare the receipt and resulting nonce to the packet.
Stop before the next transaction if they differ.

### 5. Complete two-step ownership

`transferOwnership(Safe)` only sets a pending owner. The old owner remains active
until the destination Safe separately executes `acceptOwnership()`.

For every owned contract:

1. Verify current `owner()` and zero `pendingOwner()`.
2. Execute the reviewed `transferOwnership` call from the current owner.
3. Verify `pendingOwner()` is the exact destination Safe.
4. Propose and simulate `acceptOwnership()` from that Safe.
5. Collect the required Safe threshold and execute.
6. Verify `owner()` is the Safe and `pendingOwner()` is zero.

The deployment is incomplete while any pending ownership remains.

### 6. Verify and close

- Verify every source and constructor input on an approved Base explorer.
- Compare runtime bytecode hashes with the reviewed packet.
- Verify all temporary creator/registrar permissions were revoked.
- Verify immutable operator, treasury, recipient, token, schedule, and factory
  values.
- Verify Safe nonces and signer confirmations.
- Wait for the approved Base finality stage before irreversible follow-up actions.
- Add deployed addresses and evidence to the canonical Ash manifest in a reviewed
  commit before enabling application behavior.

Use the approved Base explorer and preserve the verification evidence.
[Basescan](https://basescan.org/verifyContract) provides Base verification, and
[Etherscan documents Foundry verification](https://docs.etherscan.io/contract-verification/verify-with-foundry).

## Incident handoff

Stop the deployment procedure when an incident or unexpected state appears. Do
not improvise a recovery inside the deployment session. Follow
[Autolaunch emergency operations](autolaunch-emergency-operations.md) for
containment effects, compromise paths, recovery limits, and separate approvals.

## Absolute stop conditions

Do not sign or broadcast if any of these is true:

- An Autolaunch row or action is absent from the canonical Ash chain manifest.
- The source tree, release packet, manifest, ABI, or bytecode hashes disagree.
- A Slither finding lacks an explicit independent disposition.
- An external address, code hash, owner, role, token, recipient, or economic value
  is unverified.
- Safe owners, threshold, nonce, modules, guard, fallback handler, or pending
  transactions differ from the approved record.
- Any ownership acceptance remains unexplained or cannot be completed in the same
  operating session.
- Simulation differs from the proposed transaction or cannot decode it fully.
- Required signers or independent reviewer are unavailable.
- Someone requests a private key, seed phrase, blind signature, unexplained
  calldata, unexpected native value, unlimited approval, or `DELEGATECALL`.
- The requested action is outside the exact reviewed deployment packet.

Official references:

- [Safe owners, threshold, and transaction flow](https://docs.safe.global/advanced/smart-account-concepts)
- [Safe modules and their authority](https://docs.safe.global/advanced/smart-account-modules)
- [Base mainnet connection details](https://docs.base.org/base-chain/quickstart/connecting-to-base)
- [Base transaction finality](https://docs.base.org/base-chain/network-information/transaction-finality)
- [Foundry deployment and scripting](https://getfoundry.sh/forge/deploying/)
- [Foundry security best practices](https://getfoundry.sh/tutorials/best-practices/)
- [OpenZeppelin two-step ownership](https://docs.openzeppelin.com/contracts/5.x/api/access#Ownable2Step)
- [Slither usage](https://github.com/crytic/slither/wiki/Usage)
- [Basescan contract verification](https://basescan.org/verifyContract)
