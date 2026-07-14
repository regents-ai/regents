# Autolaunch emergency operations

| Containment control | Stops | Remains available | Critical consequence |
| --- | --- | --- | --- |
| Pause Regent revenue staking | New stakes, claim-and-restake, direct USDC deposits, reward funding, and the gated treasury paths | Unstake, direct USDC claims, direct REGENT claims, and account sync | The staking revenue router cannot complete its downstream deposit, so router deposits and protocol revenue ingress stop too |
| Pause a future deployable revenue splitter | New stakes, direct deposits, ingress recognition, sync, and other functions guarded by the splitter pause | Unstake and accrued USDC claims | Revenue sent toward the paused splitter may remain upstream or fail until operators confirm the exact ingress path |
| Disable a launch pool fee hook in its registry | Every swap that uses that hook | Unhooked markets and non-swap contract reads | Hook validation reverts, so hooked swaps halt; this does more than stop fee collection |
| Pause the current staking revenue router | Nothing, because this control does not exist | Existing router behavior | The current router has no pause, buyback, or oracle function; staking pause stops its deposits only through the downstream staking call |

Status: **incident guide only. It authorizes no transaction.**

The active Ash chain manifest currently contains evidence only and admits no
Autolaunch prepared action. The contract behavior summarized here comes from the
quarantined `platform/contracts` source and remains evidence until reviewed code,
addresses, roles, and actions enter the active manifest.

Use [Autolaunch multisig operations](autolaunch-multisig-operations.md) for
expected work and
[Autolaunch Base deployment day](autolaunch-base-deployment-day.md) for release
gates. An emergency does not waive decoding, simulation, code-hash checks, Safe
state checks, signer thresholds, or evidence capture.

## Emergency authority required before deployment

The founder should approve a pause-only emergency role before deployment for
future deployable splitters and market-halt controls. The role may pause a
splitter or disable a registered market hook. Only the full owner may unpause or
re-enable it through a separate proposal.

This recommendation does not retrofit or change the permanent Regent staking
contract. The current historical contracts bundle pause and broader owner powers.
Adding a limited role requires reviewed contract work, a new deployment, and
manifest admission. This guide makes no Solidity change.

The pause-only role must exclude all power to:

- Unpause or re-enable a market.
- Transfer ownership, appoint another pauser, or change Safe configuration.
- Withdraw, sweep, rescue, approve, or redirect any token or native value.
- Change recipients, managers, operators, fees, economics, limits, schedules,
  allowlists, or subject state.
- Migrate an auction, recover a failed auction, or call arbitrary targets.

### Minimum authorization tests

- The approved emergency role can pause each future splitter and disable each
  admitted market hook.
- An unrelated address cannot pause, disable, unpause, or re-enable.
- The emergency role cannot unpause or re-enable; only the full owner can.
- The emergency role cannot grant or rotate its own authority.
- Ownership transfer and Safe module, guard, fallback, threshold, and owner
  changes remain outside the role.

### Minimum mutation tests

- A pause-only call changes only the expected pause flag and emits the expected
  event.
- Splitter pause blocks new stake and revenue recognition while preserving
  unstake and accrued claims.
- Hook disable makes hooked swaps revert in every supported swap direction and
  amount mode.
- Full-owner unpause or re-enable uses a separate call and restores only the
  reviewed path.
- Repeated pause calls and stale proposals have defined, tested outcomes without
  changing balances, recipients, allowances, or ownership.

### Minimum adversarial tests

- A compromised pauser cannot unpause, withdraw, rescue, migrate, change
  economics, redirect a recipient, or take ownership.
- Reentrancy and callback attempts during containment cannot widen authority.
- A stale nonce, wrong chain, wrong target, wrong code hash, or substituted
  calldata cannot produce the intended emergency proposal.
- A malicious Safe module, guard, or fallback handler cannot be mistaken for the
  approved pause-only authority.
- Role revocation removes the old pauser and does not leave a parallel path.

## Incident entry and evidence freeze

1. Open an incident record and name the incident lead, evidence recorder,
   proposer, independent reviewer, and available signers.
2. Stop routine proposals and product enablement. Preserve receipts, traces,
   alerts, pending transactions, and the last known-good manifest and packet.
3. Read the chain, full contract and Safe addresses, runtime code hashes, owners,
   threshold, nonce, modules, guard, fallback handler, recovery settings, pending
   transactions, roles, pause flags, balances, allowances, and liabilities.
4. Classify the affected path and choose the smallest existing control whose
   containment effect matches the table above.
5. Decode and simulate the exact proposal against current state. Record calls,
   events, token and native-value movement, approvals, balance changes, and the
   post-state before requesting signatures.

Stop if the action is absent from the active manifest, any address or code hash
differs, the Safe state is unexpected, the calldata cannot be decoded in full,
simulation differs, or containment would destroy assets or user rights.

## Containment procedures

### Staking incident

Pausing Regent revenue staking blocks new stakes, claim-and-restake, direct
revenue deposits, reward funding, and the functions guarded by the same pause.
The router's protocol-fee settlement calls staking's deposit path, so that router
revenue ingress also stops while staking remains paused. Users can still unstake
and make direct USDC or REGENT claims.

Confirm upstream splitters and ingress accounts before pausing. Do not assume a
successful upstream transfer means staking recognized the revenue. Reconcile all
funds held upstream or in transit after containment.

### Splitter incident

Pausing a historical V2 or live-stake splitter blocks new stake, direct deposits,
ingress recognition, sync, and its other pause-guarded paths. Unstake and accrued
USDC claims remain available. Check the exact deployed splitter version before
signing because the pause scope comes from that runtime code, not this summary.

Pause the smallest affected splitter set. Record ingress balances and prevent
unreviewed retries until operators know whether each transfer reverted, remained
upstream, or reached the splitter without recognition.

### Hook or market incident

Disabling a pool's hook causes hook validation to revert. Swaps on that hooked
pool halt, including swaps that would otherwise pay no meaningful fee. Treat this
as a market halt and show that effect to operators and users.

Confirm the exact pool ID, hook, pool manager, launch token, quote token, and
registry code hash. Do not disable a neighboring pool or describe the action as a
fee-only change.

## Safe compromise paths

### Owner or signer compromise

Stop product proposals and inspect every pending Safe transaction and signature.
If the remaining owners still control the required threshold, use a dedicated,
decoded, and simulated Safe governance proposal to rotate the compromised owner.
Do not combine rotation with pause, withdrawal, rescue, or another product call.

If the attacker controls the threshold, treat the Safe as compromised. Use an
independent approved pause-only role if one remains trustworthy. Do not assume
the compromised Safe can secure itself, and do not improvise an ownership rescue.
Follow only a founder-approved recovery design whose address, delay, and powers
were recorded before the incident.

### Module compromise

A Safe module can execute transactions outside the normal signer flow. Halt
routine use, inspect every enabled module and its history, and assume the module
may bypass the threshold. Trusted core owners may remove it only through a
separate decoded and simulated Safe governance transaction. If the module can
block or race removal, use an independent pause-only control and escalate to the
approved Safe recovery plan.

### Guard compromise

A guard may block Safe transactions or approve behavior the owners did not
expect. Stop using the Safe for product work. Do not install an unknown module or
handler to bypass the guard. Use an independent pause-only control when available,
then follow the approved Safe recovery path with separate evidence and review.

### Fallback handler compromise

Treat message-signing and handler-routed behavior as untrusted. Stop signing
messages and inspect the handler, pending transactions, signatures, and Safe
version. Trusted core owners may replace the handler only through a dedicated
governance proposal that has been decoded and simulated against current state.

### Pause-only signer compromise

The full owner must revoke or rotate the role in a separate proposal. Keep the
system paused if the attacker used the role. Do not unpause until investigators
have proved the current role set, code, balances, and incident cause.

## Failed-auction recovery

`recoverFailedAuction()` is irreversible. The historical strategy pulls unsold
auction tokens, burns the strategy reserve and the agent's unvested allocation,
marks the subject dead, and permanently disables its revenue-share and ingress
path. Bidders reclaim through the auction's exit path. The recovery cannot restore
the launch, the subject, or burned supply.

Do not automate or treat this as a pause. Require a separate incident proposal
and independent proof that the auction did not graduate, the recovery block has
arrived, the selected launch and subject are exact, bidder exits remain available,
and no non-destructive path applies. Decode and simulate the full state change,
then obtain the separately approved Strategy Safe threshold and founder approval.

## Unpause and market re-enable gates

Unpause or re-enable through a separate full-owner proposal. Do not bundle it
with signer rotation, withdrawal, rescue, configuration, migration, or product
enablement.

The proposal requires:

- A closed root cause and proof that the vulnerable or misconfigured path is no
  longer reachable.
- Reconciled balances, liabilities, allowances, roles, ownership, Safe settings,
  ingress state, and pending transactions.
- Current runtime code hashes and active manifest entries for every target.
- Fresh decoded calldata and simulation against the intended Safe nonce and chain
  state.
- Independent security approval, incident-owner approval, and the full owner
  threshold.
- A post-execution watch plan and evidence record.

## Rollback limits

Contract creation and executed Safe transactions cannot be rolled back. The
historical Autolaunch contracts have no proxy upgrade path, and the strategy
operator and Agent Safe are immutable. Ownership transfer remains under the old
owner until the separate acceptance, but completed ownership acceptance has no
undo button.

Before product enablement, operators can contain an unexpected deployment by
stopping the sequence and leaving its addresses outside the active manifest and
application configuration. After enablement, operators may use only admitted
controls with reviewed effects. They must not invent an upgrade, rescue, state
rewrite, or replacement address during the incident.

## Oracle and buyback guidance

The current historical staking revenue router has no oracle, buyback, adapter,
or pause surface. Do not search for or invoke an old oracle or buyback action.

If a future admitted router introduces an oracle or buyback path, its emergency
controls need a contract-specific runbook, prepared actions, tests, and founder
approval before deployment. A price-source incident should halt the affected
path without accepting a manually substituted price, widening allowance, or
redirecting inventory. Reconcile balances, approvals, price evidence, and every
attempted settlement before any full-owner re-enable proposal.

## Emergency evidence record

Preserve the incident ticket, manifest and packet hashes, full addresses, code
hashes, Safe configuration, nonce, decoded calldata, simulation, independent
review, signer confirmations, transaction hashes, receipts, logs, internal calls,
balance and liability differences, finality stage, post-state reads, and all
explorer links. Record failed and cancelled proposals too.

Official references:

- [Safe owners, threshold, and transactions](https://docs.safe.global/advanced/smart-account-concepts)
- [Safe modules](https://docs.safe.global/advanced/smart-account-modules)
- [Safe guards](https://docs.safe.global/advanced/smart-account-guards)
- [OpenZeppelin access control](https://docs.openzeppelin.com/contracts/5.x/access-control)
- [Base network information](https://docs.base.org/base-chain/network-information/)
- [Base transaction finality](https://docs.base.org/base-chain/network-information/transaction-finality)
