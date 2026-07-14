# Autolaunch multisig operations

Status: **routine operations guide. This document approves no Safe or transaction.**

This book covers expected governance and launch operations after deployment. Use
[Autolaunch Base deployment day](autolaunch-base-deployment-day.md) for release
and ownership handoff. Use
[Autolaunch emergency operations](autolaunch-emergency-operations.md) for
containment, compromise, pause, recovery, or destructive actions.

## Authority before use

The active source for admitted contracts and prepared actions is
`/Users/sean/Documents/regent/ash-platform/contracts/chain-contracts.yaml`. It
currently labels its pinned chain material `evidence_only` and admits no
Autolaunch prepared action. Addresses and roles found in the quarantined
`platform/contracts` workspace are evidence, not authorization.

Do not use this book until the founder has approved the Safe model, every address
and code hash has been attested, each action has been admitted to the active
manifest, and the deployment gates have passed.

## Expected Safe roles

### Protocol Governance Safe

The approved Governance Safe owns shared factories, the subject registry, the
staking revenue router, and long-lived launch administration. The release packet
must state its full address, chain, owners, threshold, modules, guard, fallback
handler, recovery settings, and starting nonce.

Use independent hardware-backed owners on distinct devices and recovery paths.
A 3-of-5 threshold is preferred when five independent owners exist. A 2-of-3
threshold is the practical smaller group. Founder approval decides the final
shape.

### Strategy Operations Safe

The approved Strategy Safe holds the immutable per-launch operator role. It
handles expected graduation migration and the post-migration sweeps to fixed
beneficiaries. A separate 2-of-3 Safe keeps time-sensitive launch work apart
from shared governance, subject to founder approval.

### Per-launch Agent Safe

The release packet states whether each Agent Safe is user-controlled or uses a
disclosed shared custody model. It receives the roles and assets assigned to it
by the reviewed launch design. Regent must not hold undisclosed custody.

### User wallet

Bids, exits, reclaims, and claims remain signed by the initiating user. A
protocol or Agent Safe does not sign for that user.

## Expected operation matrix

| Operation | Expected authority | Required control |
| --- | --- | --- |
| Grant or revoke a reviewed creator or registrar | Governance Safe | Separate decoded proposal, simulation, and post-state role read |
| Prepare or finalize an approved launch | Governance Safe or approved Launch Safe | Exact admitted action and release packet |
| Accept fee registry, vault, hook, and splitter ownership | Agent Safe | Complete the two-step handoff and prove final ownership |
| Migrate a graduated auction | Strategy Safe | Graduation proof, exact launch, simulation, and fixed recipient checks |
| Sweep post-migration launch or quote assets | Strategy Safe | Fixed beneficiary, exact amount, and balance proof |
| Rotate a subject manager or splitter treasury through an admitted path | Agent Safe | Delay and recipient checks, separate proposal, post-state proof |
| Withdraw an accrued treasury or fee share | Owning Safe | Exact token, amount, recipient, liabilities, and remaining balance |
| Sweep ingress or payment-link USDC to its fixed destination | Reviewed keeper or operator | Caller cannot redirect value; reconcile destination receipt |
| Bid, exit, reclaim, or claim | Initiating user wallet | User signature only |

## Standard Safe transaction procedure

### Prepare

Record these facts before a proposal exists:

- Base chain ID and the full Safe address.
- Full target, value, operation type, function signature, selector, decoded
  arguments, calldata hash, Safe nonce, and change window.
- Expected events, state changes, internal calls, approvals, token flows,
  beneficiaries, and gas ceiling.
- Current Safe owners, threshold, nonce, modules, guard, fallback handler,
  recovery settings, and pending transactions.
- Current contract owner, pending owner, role mappings, schedule, balances, and
  protected liabilities.
- Active manifest hash, ABI hash, runtime code hash, approved packet hash, and
  the evidence that admits the action.

Use `CALL`. An unexpected `DELEGATECALL` is a stop condition.

### Simulate and review

1. Simulate against the exact intended chain state and Safe nonce.
2. Compare decoded calldata, events, internal calls, approvals, balances, roles,
   and post-state with the approved packet.
3. Have a second person on a separate device compare every full address, code
   hash, calldata hash, and beneficiary with the active manifest.
4. Confirm the Safe transaction hash and that no owner, threshold, module, guard,
   fallback handler, or recovery change is bundled with the product operation.

Any state change after simulation requires a new simulation and review.

### Propose, confirm, and execute

1. Propose through the official Safe interface or reviewed tooling.
2. Each owner checks the full transaction before confirming.
3. Collect the approved threshold within the change window.
4. Execute only while the state and nonce still match the simulation.
5. Verify receipt status, logs, internal calls, token balances, roles, Safe nonce,
   and the approved Base finality stage before updating product state.

A published Safe signature may remain usable. Cancelling a queued transaction
requires a separate executed Safe transaction that consumes its nonce.

## Exact two-step ownership acceptance

`transferOwnership(destinationSafe)` sets a pending owner. The current owner
remains active until the destination Safe executes `acceptOwnership()` in a
separate transaction.

For each owned contract:

1. Read `owner()` and confirm `pendingOwner()` is zero.
2. Simulate and execute the reviewed `transferOwnership(destinationSafe)` call
   from the current owner.
3. Read both fields again and confirm the pending owner is the full approved Safe
   address.
4. Build a separate Safe proposal for `acceptOwnership()`.
5. Decode and simulate that proposal, confirm its Safe nonce, collect the full
   threshold, and execute it.
6. Confirm `owner()` equals the destination Safe and `pendingOwner()` is zero.

The handoff is incomplete until both final reads match. OpenZeppelin documents
the pattern in
[Ownable2Step](https://docs.openzeppelin.com/contracts/5.x/api/access#Ownable2Step).

## Evidence record

Preserve one record for every executed operation:

- Approved change ticket and packet hash.
- Chain, full Safe address, Safe version, owners, threshold, nonce, modules,
  guard, fallback handler, and recovery settings.
- Full target, decoded transaction, calldata hash, ABI hash, and runtime code
  hash.
- Simulation trace, state and balance differences, and independent reviewer.
- Signer confirmations, Safe transaction hash, execution transaction hash,
  receipt, block, logs, and internal calls.
- Post-state reads, beneficiary balances, finality stage, and explorer links.
- Owner and pending-owner proof for ownership operations.
- Product-state reconciliation and a timestamped operator note.

## Stop conditions

Do not confirm or execute if:

- The chain is not the approved Base mainnet chain `8453`.
- The action, target, ABI, address, or code hash is absent from the active
  manifest or differs from the approved packet.
- The Safe address, owners, threshold, nonce, modules, guard, fallback handler,
  recovery settings, or pending transactions differ from the approved record.
- The transaction cannot be decoded in full or simulation differs from it.
- Target, value, selector, recipient, amount, allowance, role, or argument differs.
- Native value or `DELEGATECALL` is unexpected.
- An ownership acceptance is unresolved.
- A required signer or independent reviewer is unavailable.
- A security finding or external-address attestation remains open.
- A Safe governance change is bundled with a product operation.
- Anyone requests a private key, seed phrase, blind signature, or unreviewed
  transaction.

Official references:

- [Safe Smart Account overview](https://docs.safe.global/advanced/smart-account-overview)
- [Safe owners, threshold, and transactions](https://docs.safe.global/advanced/smart-account-concepts)
- [Safe modules](https://docs.safe.global/advanced/smart-account-modules)
- [Safe guards](https://docs.safe.global/advanced/smart-account-guards)
- [Base network information](https://docs.base.org/base-chain/network-information/)
- [Base transaction finality](https://docs.base.org/base-chain/network-information/transaction-finality)
