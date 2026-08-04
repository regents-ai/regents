# Autolaunch migration inventory

Status: candidate migration evidence for regent-839.6; no deployment or promotion is authorized.

## Identity and interpretation

- Target base: `0845fa88d656e3927e65906e9c839d4282ecf907` on branch `regent-839.6`.
- Read-only source: `/Users/sean/Documents/regent/archive/repos/platform/contracts`.
- Source Git commit: `b760a45b7a9d97711d14ebe8d467dfcc168b5f1a` (clean archive checkout at inventory time).
- Migration rule: source files are byte-faithful except for mechanical local import-path changes required by the target layout. No behavior was changed.
- Taxonomy: **M** = migrated into this repository; **D** = the migrated source lineage is bound to a deployment; **P** = publicly exposed; **A** = exact currently admitted prepared-action IDs. These labels are independent. Admission is per action, never a contract-wide boolean. A historical broadcast whose constructor or artifact lineage disagrees with current source does not make the current source `D`.
- A historical RegentRevenueStaking artifact is deployed and publicly exposed on Base mainnet at `0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5`, but its metadata-stripped creation bytecode does not match the current migrated source. The current source is therefore `M` only, not `D/P`, and money-admitted is **false**: staking actions are reviewed-evidence only; zero admitted action ids.
- Source binding uses exact SHA-256 comparison of creation bytecode after removing constructor arguments and the Solidity CBOR metadata trailer. Constructor-shape compatibility alone grants no deployment label. Of the reconstructed entries, only `TestnetMintableERC20` matches current source; every other current-source label is false/unverified. Per-entry methods and digests are recorded in the deployment histories.
- Exact admission truth is mirrored from the read-only Ash Platform `contracts/chain-contracts.yaml` `admitted_prepared_actions` list. v0.1 LAUNCH admission is separately governed by the v0.1 money-action matrix; subject-owner action classes become unavailable at launch regardless of current admission.
- Compiler notation `26/30*` means source pragma `^0.8.26`, with Foundry auto-detect selecting Solc 0.8.26 for production lanes and 0.8.30 when the source is imported into exact-0.8.30 archived suites/scripts. Existing Techtree remains on 0.8.28. Pinned Uniswap v4 dependencies compile on 0.8.26 and UERC20 on 0.8.28.

## Test status key

All active entries below built successfully and were exercised by the combined Foundry run: **370 passed, 0 failed, 0 skipped across 37 suites** (314 migrated tests plus the untouched 56-test Techtree suite).

- `launch`: controller, fee registry/vault/hook, LBP strategy/factory, vesting, example deployment, hardening.
- `revenue`: subject registry, V2 splitter, ingress, payment, deferred/permissionless factories, live splitter and PoCs.
- `staking`: staking unit/invariant/rounding, router, emission vault, daily distributor and snapshot fixture.
- `indirect`: interface/library exercised through its consumers; no standalone suite expected.
- `build/script`: compiled and covered by deployment-script tests rather than a dedicated contract suite.
- `reference-only`: retained audit history outside default Foundry source/test paths; not an active migration suite.

## Complete migrated source set

| Archived source | Target | Test status | Solc | M | D | P | Admitted prepared-action IDs |
|---|---|---|---:|:---:|:---:|:---:|:---:|
| `src/AgentTokenVestingWallet.sol` | `src/autolaunch/AgentTokenVestingWallet.sol` | launch pass | 26/30* | Y | N (child init code unavailable) | N | none |
| `src/DeferredAutolaunchVestingWallet.sol` | `src/autolaunch/DeferredAutolaunchVestingWallet.sol` | revenue pass | 26/30* | Y | N | N | none |
| `src/LaunchDeploymentController.sol` | `src/autolaunch/LaunchDeploymentController.sol` | launch pass | 26/30* | Y | N (legacy broadcast ABI mismatch) | N | none |
| `src/LaunchFeeInfraDeployer.sol` | `src/autolaunch/LaunchFeeInfraDeployer.sol` | launch pass | 26/30* | Y | N (creation bytecode mismatch) | N | none |
| `src/LaunchFeeRegistry.sol` | `src/autolaunch/LaunchFeeRegistry.sol` | launch pass | 26/30* | Y | N (child init code unavailable) | N | none |
| `src/LaunchFeeVault.sol` | `src/autolaunch/LaunchFeeVault.sol` | launch pass | 26/30* | Y | N (child init code unavailable) | N | none |
| `src/LaunchPoolFeeHook.sol` | `src/autolaunch/LaunchPoolFeeHook.sol` | launch pass | 26/30* | Y | N (child init code unavailable) | N | none |
| `src/RegentLBPStrategy.sol` | `src/autolaunch/RegentLBPStrategy.sol` | launch pass | 26/30* | Y | N (legacy broadcast tuple mismatch) | N | none |
| `src/RegentLBPStrategyFactory.sol` | `src/autolaunch/RegentLBPStrategyFactory.sol` | launch pass | 26/30* | Y | N (creation bytecode mismatch) | N | none |
| `src/cca/interfaces/IContinuousClearingAuction.sol` | `src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol` | launch indirect pass | 26/30* | Y | N | N | `continuous_clearing_auction.submit_bid`, `continuous_clearing_auction.exit_bid`, `continuous_clearing_auction.return_quote_token`, `continuous_clearing_auction.claim_bid` |
| `src/cca/interfaces/IContinuousClearingAuctionFactory.sol` | `src/autolaunch/cca/interfaces/IContinuousClearingAuctionFactory.sol` | launch indirect pass | 26/30* | Y | N | N | none |
| `src/cca/interfaces/external/IDistributionContract.sol` | `src/autolaunch/cca/interfaces/external/IDistributionContract.sol` | launch indirect pass | 26/30* | Y | N | N | none |
| `src/cca/libraries/AuctionStepsBuilder.sol` | `src/autolaunch/cca/libraries/AuctionStepsBuilder.sol` | launch indirect pass | 26/30* | Y | N | N | none |
| `src/auth/Owned.sol` | `src/shared/auth/Owned.sol` | indirect pass | 26/30* | Y | N | N | none |
| `src/interfaces/IDistributionStrategy.sol` | `src/shared/interfaces/IDistributionStrategy.sol` | launch indirect pass | 26/30* | Y | N | N | none |
| `src/interfaces/IERC20Minimal.sol` | `src/shared/interfaces/IERC20Minimal.sol` | indirect pass | 26/30* | Y | N | N | none |
| `src/interfaces/ITokenFactory.sol` | `src/shared/interfaces/ITokenFactory.sol` | launch/revenue indirect pass | 26/30* | Y | N | N | none |
| `src/libraries/BaseMainnetChainConfig.sol` | `src/shared/libraries/BaseMainnetChainConfig.sol` | launch indirect pass | 26/30* | Y | N | N | none |
| `src/libraries/BaseRegent.sol` | `src/shared/libraries/BaseRegent.sol` | launch indirect pass | 26/30* | Y | N | N | none |
| `src/libraries/BaseUsdc.sol` | `src/shared/libraries/BaseUsdc.sol` | build/script pass | 26/30* | Y | N | N | none |
| `src/libraries/HookMiner.sol` | `src/shared/libraries/HookMiner.sol` | launch indirect pass | 26/30* | Y | N | N | none |
| `src/libraries/SafeTransferLib.sol` | `src/shared/libraries/SafeTransferLib.sol` | indirect pass | 26/30* | Y | N | N | none |
| `src/mocks/TestnetMintableERC20.sol` | `test/mocks/TestnetMintableERC20.sol` | build/script pass | 26/30* | Y | Y (Sepolia; bytecode verified) | N | none |
| `src/revenue/DeferredAutolaunchFactory.sol` | `src/autolaunch/revenue/DeferredAutolaunchFactory.sol` | revenue pass | 26/30* | Y | N | N | none |
| `src/revenue/LiveStakeFeePoolSplitter.sol` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol` | revenue pass | 26/30* | Y | N | N | none |
| `src/revenue/PaymentLinkFactory.sol` | `src/autolaunch/revenue/PaymentLinkFactory.sol` | revenue pass | 26/30* | Y | N | N | `payment_link_factory.create_payment_link`, `payment_link_factory.create_canonical_payment_link`, `payment_link_factory.set_payment_link_canonical`, `payment_link_factory.set_payment_link_receiver_state` |
| `src/revenue/PaymentLinkReceiver.sol` | `src/autolaunch/revenue/PaymentLinkReceiver.sol` | revenue pass | 26/30* | Y | N | N | none |
| `src/revenue/PermissionlessExistingTokenRevenueFactory.sol` | `src/autolaunch/revenue/PermissionlessExistingTokenRevenueFactory.sol` | revenue pass | 26/30* | Y | N | N | none |
| `src/revenue/RegentDailyDistributor.sol` | `src/autolaunch/revenue/RegentDailyDistributor.sol` | staking pass | 26/30* | Y | N | N | none |
| `src/revenue/RegentEmissionVault.sol` | `src/autolaunch/revenue/RegentEmissionVault.sol` | staking pass | 26/30* | Y | N | N | none |
| `src/revenue/RegentRevenueStaking.sol` | `src/staking/RegentRevenueStaking.sol` | staking pass | 26/30* | Y | N (historical Base artifact bytecode mismatch) | N | none — reviewed-evidence only; zero admitted action ids |
| `src/revenue/RegentStakingRevenueRouter.sol` | `src/autolaunch/revenue/RegentStakingRevenueRouter.sol` | staking/revenue pass | 26/30* | Y | N | N | `regent_staking_revenue_router.settle_treasury_buyback` (legacy prepared interface; current source has no buyback function) |
| `src/revenue/RevenueIngressAccount.sol` | `src/autolaunch/revenue/RevenueIngressAccount.sol` | revenue pass | 26/30* | Y | N (legacy constructor semantics mismatch) | N | `revenue_ingress_account.sweep_usdc` |
| `src/revenue/RevenueIngressFactory.sol` | `src/autolaunch/revenue/RevenueIngressFactory.sol` | revenue pass | 26/30* | Y | N (creation bytecode mismatch) | N | none |
| `src/revenue/RevenueShareFactory.sol` | `src/autolaunch/revenue/RevenueShareFactory.sol` | revenue/launch pass | 26/30* | Y | N (legacy 4-arg broadcast; current source is 5-arg) | N | none |
| `src/revenue/RevenueShareSplitterV2.sol` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol` | revenue pass | 26/30* | Y | N | N | `revenue_share_splitter_v2.stake`, `revenue_share_splitter_v2.unstake`, `revenue_share_splitter_v2.claim_usdc` |
| `src/revenue/RevenueShareSplitterV2Deployer.sol` | `src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/SubjectRegistry.sol` | `src/autolaunch/revenue/SubjectRegistry.sol` | revenue/launch pass | 26/30* | Y | N (creation bytecode mismatch) | N | none |
| `src/revenue/interfaces/IDeferredAutolaunchFactory.sol` | `src/autolaunch/revenue/interfaces/IDeferredAutolaunchFactory.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IERC20SupplyMinimal.sol` | `src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol` | indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/ILiveStakeFeePoolSplitter.sol` | `src/autolaunch/revenue/interfaces/ILiveStakeFeePoolSplitter.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IOwned.sol` | `src/autolaunch/revenue/interfaces/IOwned.sol` | indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IPermissionlessExistingTokenRevenueFactory.sol` | `src/autolaunch/revenue/interfaces/IPermissionlessExistingTokenRevenueFactory.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IRegentEmissionVault.sol` | `src/autolaunch/revenue/interfaces/IRegentEmissionVault.sol` | staking indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IRegentRevenueStakingMinimal.sol` | `src/autolaunch/revenue/interfaces/IRegentRevenueStakingMinimal.sol` | staking indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IRegentStakingRevenueRouter.sol` | `src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IRevenueIngressAccountMinimal.sol` | `src/autolaunch/revenue/interfaces/IRevenueIngressAccountMinimal.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IRevenueIngressFactoryMinimal.sol` | `src/autolaunch/revenue/interfaces/IRevenueIngressFactoryMinimal.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/IRevenueShareSplitter.sol` | `src/autolaunch/revenue/interfaces/IRevenueShareSplitter.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/ISubjectLifecycleSync.sol` | `src/autolaunch/revenue/interfaces/ISubjectLifecycleSync.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/ISubjectPaymentReceiver.sol` | `src/autolaunch/revenue/interfaces/ISubjectPaymentReceiver.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/interfaces/ISubjectRegistry.sol` | `src/autolaunch/revenue/interfaces/ISubjectRegistry.sol` | revenue indirect pass | 26/30* | Y | N | N | none |
| `src/revenue/libraries/InputBounds.sol` | `src/autolaunch/revenue/libraries/InputBounds.sol` | revenue indirect pass | 26/30* | Y | N | N | none |

### Retained reference lineage

| Archived source | Target | Test status | Solc | M | D | P | Admitted prepared-action IDs |
|---|---|---|---:|:---:|:---:|:---:|:---:|
| `reference/revenue/RevenueShareSplitter.sol` | same path | reference-only; not in active suite | 26/30* | Y | N (unverified legacy artifact) | N | none |
| `reference/revenue/RevenueShareSplitterDeployer.sol` | same path | reference-only; not in active suite | 26/30* | Y | N (current reference source does not compile) | N | none |
| `reference/test/RevenueShareSplitter.t.sol` | same path | historical test evidence; current V2 interface mismatch documented below | 26/30* | Y | N | N | none |

The reference test is intentionally excluded from the default Foundry paths. When explicitly compiled in isolation, it fails because the retained legacy splitter test constructs the current V2 `IRevenueShareSplitter` structs with the older field count (8 versus 9 fields and 4 versus 5 fields). This is historical lineage drift, not an active-suite failure. It was not modified or promoted because doing so would be a behavioral/source-history change.

### Admitted external action classes

These action classes are currently admitted but their artifacts are external and are not part of this migration:

| Artifact class | Migration status | Exact admitted prepared-action IDs |
|---|---|---|
| Quote-token ERC-20 | external / not migrated | `quote_token_erc20.approve_exact` |
| Subject-token ERC-20 | external / not migrated | `subject_token_erc20.approve_exact` |

## Required versus optional migration

The v0.1-required set and constructor/authority matrix are recorded in `contracts/autolaunch-deployment-manifest.draft.yaml`. Deferred Autolaunch, permissionless existing-token revenue, live-stake splitter, payment links, daily distribution, emission vault, testnet mock, and the retained legacy reference family are migrated but are not in the required v0.1 deployment set. Deployment presence, public exposure, and per-action admission remain independent; for example, the payment-link action family is currently admitted even though its contracts are not required for the v0.1 deployment set.

## Historical deployment reconstruction

- `deployments/base-mainnet/autolaunch-history.yaml` reconstructs the permanent live RegentRevenueStaking artifact and its exact constructor arguments, while recording that its creation bytecode does not bind to current source.
- `deployments/base-sepolia/autolaunch-history.yaml` reconstructs three infrastructure broadcasts, one full launch broadcast, and the test-token broadcast. Every deployment entry records the artifact name, full constructor arguments, source lineage, bytecode-binding method, available digests, and an explicit current-source deployment result. Only `TestnetMintableERC20` is bytecode-verified against current source.
- The external UERC20 factory, external launch token, external CCA instance, and unresolved helper are explicitly external/not migrated. No blanket migration label applies to the Sepolia record.
- The archived `HANDOFF-contracts-tokenomics.md` named by `CONTRACTS.md` is absent from the archive checkout. Reconstruction therefore uses the binding inventory, archived broadcasts, and archived runbooks; no missing fact was invented.

## Dependency custody

The eight direct dependencies are pinned to the archive's recorded commits: forge-std `77041d2`, v4-core `59d3ecf`, v4-periphery `686f621`, permit2 `cc56ad0`, solmate `89365b8`, solady `90db92c`, OpenZeppelin `9cfdccd`, and UERC20 factory `09ae130`. Nested vendor submodules are not initialized because the archived remappings only require these top-level pins.

## Static-analysis triage

The completeness run is `FOUNDRY_OFFLINE=true slither . --show-ignored-findings`. It analyzed the default graph and reported 234 results; Slither exits 255 when findings exist. No new suppression was added by this migration, and `slither.config.json` is unchanged. The archived source does carry 13 inherited inline suppression directives: seven in active source and six in `reference/`. The reference family is outside Slither's default analysis graph, so its six directives are catalogued from source lineage rather than counted in the default-graph detector totals.

| Detector | Count | Severity / confidence | Migration triage |
|---|---:|---|---|
| `reentrancy-balance` | 9 | High / Medium | Open deployment blocker. The active-source truth is nine, including the two inherited inline-suppressed staking findings shown below; seven appear without `--show-ignored-findings`. |
| `incorrect-exp` | 2 | High / Medium | Open dependency blocker; both findings are in pinned OpenZeppelin/v4 code, not active migrated source. |
| `incorrect-shift` | 2 | High / High | Open dependency blocker; both findings are in pinned v4 code, not active migrated source. |
| `reentrancy-no-eth` | 7 | Medium / Medium | Open for review, including one inherited inline-suppressed staking finding. No source behavior was changed. |
| `divide-before-multiply` | 39 | Medium / Medium | Open arithmetic precision review. |
| `incorrect-equality` | 21 | Medium / High | Mostly deliberate exact-transfer, exact-accounting, and initialization invariants, plus zero-state branches. Still open for audit because migration scope does not authorize detector suppression or semantic changes. |
| `uninitialized-local` | 1 | Medium / Medium | Open initialization review. |
| `unused-return` | 8 | Medium / Medium | Open return-value review. |
| `reentrancy-benign` | 9 | Low / Medium | Open, including four inherited inline-suppressed findings across active and reference lineage. Existing tests are evidence, not a waiver. |
| `reentrancy-events` | 14 | Low / Medium | Open; events emitted after external calls can be reordered under callbacks. No event ordering was redesigned here. |
| `timestamp` | 32 | Low / Medium | Expected in vesting, cooldown, emission, and claim scheduling, but remains review evidence for schedule-boundary testing. |
| `incorrect-modifier` | 1 | Low / High | Open modifier-control-flow review. |
| `shadowing-local` | 1 | Low / High | Open naming/scope review. |
| `assembly` | 50 | Informational / High | Includes inherited and dependency assembly use; review remains required for active packed-data and transfer paths. |
| `cyclomatic-complexity` | 1 | Informational / High | Structural review finding. |
| `dead-code` | 7 | Informational / Medium | Inherited unreachable/unused implementation paths. |
| `low-level-calls` | 3 | Informational / High | Shared safe-transfer helpers intentionally support native/ERC-20 calls and nonstandard approval flows; hardened by codeless-token and exact-transfer tests. |
| `missing-inheritance` | 2 | Informational / High | Structural suggestions only; one crosses into untouched Techtree through a local interface name. No inheritance redesign is in scope. |
| `naming-convention` | 9 | Informational / High | Inherited naming findings. |
| `pragma` | 1 | Informational / High | Expected multi-compiler dependency graph: active source `^0.8.26`, Techtree/UERC20 0.8.28, and vendor constraints. |
| `solc-version` | 3 | Informational / High | Compiler-policy findings remain review evidence; this migration preserves the archived compiler lanes. |
| `too-many-digits` | 12 | Informational / Medium | Numeric readability findings, including one inherited inline-suppressed hook hash expression. |

### Inherited inline Slither suppressions

| Location | Directive | Finding hidden without `--show-ignored-findings` | Default graph |
|---|---|---|:---:|
| `src/autolaunch/AgentTokenVestingWallet.sol:193` | `slither-disable-next-line timestamp` | `timestamp` on the block-time wrapper | Y |
| `src/autolaunch/LaunchFeeInfraDeployer.sol:32` | `slither-disable-next-line too-many-digits` | `too-many-digits` on the hook init-code hash expression | Y |
| `src/staking/RegentRevenueStaking.sol:147` | `slither-disable-next-line reentrancy-no-eth` | `reentrancy-no-eth` in `stake` | Y |
| `src/staking/RegentRevenueStaking.sol:290` | `slither-disable-next-line reentrancy-benign` | `reentrancy-benign` in `depositUSDC` | Y |
| `src/staking/RegentRevenueStaking.sol:307` | `slither-disable-next-line reentrancy-benign` | `reentrancy-benign` in `fundRegentRewards` | Y |
| `src/staking/RegentRevenueStaking.sol:632` | `slither-disable-next-line reentrancy-balance` | High `reentrancy-balance` in `_pullExactStakeToken` | Y |
| `src/staking/RegentRevenueStaking.sol:644` | `slither-disable-next-line reentrancy-balance` | High `reentrancy-balance` in `_pushExactStakeToken` | Y |
| `reference/revenue/RevenueShareSplitter.sol:331` | `slither-disable-next-line reentrancy-no-eth` | `reentrancy-no-eth` in `stake` | none |
| `reference/revenue/RevenueShareSplitter.sol:383` | `slither-disable-next-line reentrancy-benign` | `reentrancy-benign` in `depositUSDC` | none |
| `reference/revenue/RevenueShareSplitter.sol:412` | `slither-disable-next-line reentrancy-benign` | `reentrancy-benign` in `recordIngressSweep` | none |
| `reference/revenue/RevenueShareSplitter.sol:733` | `slither-disable-next-line reentrancy-benign` | `reentrancy-benign` in `fundStakeTokenRewards` | none |
| `reference/revenue/RevenueShareSplitter.sol:1058` | `slither-disable-next-line reentrancy-balance` | High `reentrancy-balance` in `_pullExactStakeToken` | none |
| `reference/revenue/RevenueShareSplitter.sol:1070` | `slither-disable-next-line reentrancy-balance` | High `reentrancy-balance` in `_pushExactStakeToken` | none |

The active migrated-source High count is nine `reentrancy-balance` findings, including the two suppressed staking findings. The complete default graph additionally reports two `incorrect-exp` and two `incorrect-shift` High findings in pinned dependencies, for 13 High results overall. Every listed finding and inherited suppression remains a deployment blocker. The results are review leads rather than 234 confirmed vulnerabilities, but none is silently waived.

## Candidate gate results

- `forge build`: pass; Solc lanes 0.8.26, 0.8.28, and 0.8.30 resolved under auto-detect.
- `FOUNDRY_OFFLINE=true forge test`: pass; 370 passed, 0 failed, 0 skipped across 37 suites.
- Focused auction/LBP `forge snapshot`: pass; 49 tests across controller, deployment-script, and LBP strategy suites; 48 snapshot entries. Representative gas: full launch 17,005,342; auction creation 1,090,549; v4 migration 2,077,644; 40/60 fuzz migration mean 5,301,018.
- `forge fmt --check`: pass after mechanical wrapping of lengthened import paths.
- `FOUNDRY_OFFLINE=true slither . --show-ignored-findings`: completed; default graph, 234 triaged results, including 9 active migrated-source High findings plus 4 dependency High findings; exit 255 because findings remain.
- `git diff --check`: pass.
- YAML parse check for both draft manifests and both historical records: pass.

## Territory and active-code checks

- No active TECH-token reference exists in migrated source, tests, scripts, or retained reference code.
- `src/techtree/**`, `test/techtree/**`, `script/techtree/**`, `README.md`, and `repo.yaml` are outside this migration and must remain unchanged.
- No archive content, deployment, key, secret, public exposure, or money-admission action is part of this work.
