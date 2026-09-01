# Autolaunch Base deployment day

Status: **NO-GO. Do not broadcast or sign an Autolaunch deployment today.**

This is the protected deployment-day gate for Autolaunch. It is intentionally a
gated template, not an executable production command. The exact broadcast packet
is added only after the current source, security findings, external addresses,
Safe roles, rehearsal output, and Ash chain manifest have all been independently
reviewed.

## Why deployment is blocked

The canonical Ash contract source is
`/Users/sean/Documents/regent/repos/ash-platform/contracts/chain-contracts.yaml`.
It admits staking, Animata redemption, and Regents Club actions only.
`admitted_prepared_actions` holds ten entries, and not one of them is an
Autolaunch action. The manifest's `autolaunch_consumer_freeze` block records
`admission: disabled` and `deployment_status: deployment_pending`, which is the
fact that blocks deployment day.

The active Autolaunch Solidity authority is
`/Users/sean/Documents/regent/repos/autolaunch-contracts`, whose own gates and
frozen deployment packet govern the ceremony. That packet's authorization state
is `not authorized`, so nothing in that repository may be signed or broadcast
from its working tree. The former `platform/contracts` workspace is retired and
no longer exists at that path; its scripts and tests are historical evidence
only.

These gates are mandatory before a production packet can exist:

- `regent-839.7`: prepare, audit, and founder-approve the Autolaunch Base
  deployment ceremony. It owns the frozen deployment packet, the offline, fork,
  and unsigned-rehearsal gates, the Slither dispositions, and the independent
  review. The closure ticket ids this document previously cited no longer exist
  in the tracker.
- Admission of the reviewed Autolaunch contracts and actions to the canonical Ash
  chain manifest, which flips `autolaunch_consumer_freeze.admission` from
  `disabled` and adds Autolaunch entries to `admitted_prepared_actions`. The
  manifest records that the freezes in `regent-alv1.6` and `regent-839.5.1`
  govern that admission. Until it lands, deployment day is blocked regardless of
  contract-side readiness.

Contract-side evidence now lives with the contracts, at `autolaunch-contracts`
commit `0fa0bc49429d43258d57836b478aa5943366942a`:

- The offline gate reports **240 test identities executed** and **215 recorded,
  active requirements** with none pending. 191 are due at that gate and 24 belong
  to another.
- Slither ran all **101 registered detectors** and produced **11 results, each
  carrying its own written disposition**.
- A read-only Base fork gate ran 27 checks across blocks `50541328` and
  `50541628` with zero failures and zero skips.
- An unsigned rehearsal simulated the exact deployment script against a read-only
  copy of Base with no signer and no broadcast flag, and sent nothing.

That evidence is recorded and reconciled in that repository and is not reproduced
here. Contract-side green does not override the missing manifest authority. Ash
still admits no Autolaunch contract or action, and that alone blocks deployment
day.

## Network target and evidence boundary

Base mainnet is the intended production target. Its chain ID is `8453`, as
published in [Base network information](https://docs.base.org/base-chain/network-information/).

Locally pinned REGENT, USDC, staking, Safe, CCA, Uniswap, and factory addresses
are evidence only. None is an authorized deployment input until the address and
code evidence is attested, the Safe model is approved, and the exact values are
admitted to the active Ash chain manifest.

Base publishes connection details at
[Connecting to Base](https://docs.base.org/base-chain/quickstart/connecting-to-base).

## Superseded deployment shape (historical only)

The approved ceremony is five zero-value contract creations from one disposable
account, with no permission grant, ownership handoff, governance transaction, or
example launch. The scripts below are the retired infrastructure ceremony,
recorded for history only. Nothing in this section is a deployment-day input.

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
- Confirmation that the ceremony contains no non-constructor call, as the
  approved five-creation shape requires.
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

Run these only in a clean rehearsal checkout of the reviewed source. They do
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

The exact dry-run command comes from the `autolaunch-contracts` deployment gate
after the clean source and public inputs are frozen. It must omit `--broadcast`.
Foundry runs local and onchain simulation before optional broadcasting; see
[Foundry deployment and scripting](https://getfoundry.sh/forge/deploying/) and
[Foundry security best practices](https://getfoundry.sh/tutorials/best-practices/).

No `--broadcast`, `cast send`, Safe proposal, or wallet prompt belongs in this
document until the release packet passes all gates.

## Deployment-day procedure after all gates close

### 1. Open the change window

- Confirm every gate above is closed with immutable evidence.
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
- Confirm the sequence contains no ownership-acceptance or governance
  transaction. The approved ceremony performs neither.
- Record the trace and state diff before requesting any signature.

Stop on any revert, unexpected call, `DELEGATECALL`, native value, approval,
recipient, permission, address, or balance change.

### 3. Founder go/no-go

Sean reviews the human-readable summary, exact identities, full addresses,
economics, Safe configuration, simulation output, a live funding estimate taken
at ceremony time, and the irreversible effects. Approval is a `GO_TO_DEPLOY`
naming the deployment packet's own digest: the value in the packet's
`digest.value` field, computed over the packet rendered with that field set to
null. It is neither the packet file's raw checksum nor the release manifest's
checksum, and naming any other value authorizes nothing. Approval also names the
signing method, which is never stored in any repository.

### 4. Broadcast only the reviewed packet

The final runbook supplies one exact hardware-wallet or password-protected
keystore command. Do not use a plaintext private key or copy a command from the
quarantined Platform proposal. Do not use Foundry `--resume` without rechecking
nonce and state; Foundry documents that resume does not simulate the script again.

After every transaction, compare the receipt and resulting nonce to the packet.
Stop before the next transaction if they differ.

### 5. Confirm no ownership handoff is pending

The approved ceremony performs no ownership transfer. The Governance and Regent
Safe is compiled into the factory as its sole mutable authority, so there is no
pending owner to accept and no two-step handoff to complete. Confirm that the
deployed factory reports the expected Safe as its authority, and treat any
pending ownership anywhere in the graph as an unexpected state and a stop.

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
- Any ownership handoff appears at all, which the approved ceremony does not
  perform.
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
- [Slither usage](https://github.com/crytic/slither/wiki/Usage)
- [Basescan contract verification](https://basescan.org/verifyContract)
