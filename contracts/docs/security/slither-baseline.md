# Slither baseline

This document records the accepted U1/C0 Slither baseline at
`5badbf34e61907f443185b8a5b470d71ab9a5fdd`. It is an inventory of
location-specific triage decisions, not a detector-wide exclusion policy.

## Entry evidence

- Control commit: `94ab6ad1b4625fbbcaa8d09ccab09b91cc84cf3a`
- Base tree: `810145e27769fe7d5056490cc43cd70996fee878`
- Literal `bin/gate.sh`: exit 0; 38 suites; 371 passed; 0 failed; 0 skipped.
- Literal `slither .`: exit 255; 102 contracts; 101 detectors; 96 results.
- Result classes: 7 `reentrancy-balance`, 21 `incorrect-equality`, 6
  `reentrancy-no-eth`, 2 `unused-return`, 7 `reentrancy-benign`, 14
  `reentrancy-events`, 32 `timestamp`, 1 `assembly`, 1 `pragma`, 3
  `low-level-calls`, and 2 `missing-inheritance`.

## Bounded dispositions and causal chains

Each code below is a retained, location-specific disposition. The
`slither.db.json` entry stores the exact Slither ID and full finding
description. A source change would alter the result ID or produce a new,
unsuppressed result, so future findings still fail literal `slither .`.

- **RB — guarded balance-delta accounting.** The detector sees a token or
  canonical-auction call between balance reads. The reachable public operation
  is non-reentrant, and the post-call exact-delta or monotonic-balance check
  rejects fee-on-transfer, rebasing, short-transfer, or balance-loss behavior.
  The stale-read warning is therefore the invariant being enforced.
- **EQ — deliberate equality invariant.** These comparisons enforce exact token
  movement, exact minted supply, empty residual balance, the deterministic pool
  tick, exact protocol routing, or explicit zero/rounding branches. Replacing
  equality with a range check would weaken accounting or product behavior.
- **RN — reserved or locked external-call flow.** Launch deployment is protected
  by the deployment lock; splitter creation is protected by its creation lock
  and reserves both identifiers before deployment; stake paths use their
  non-reentrancy guards. The reported post-call writes cannot be reached through
  an unguarded cross-function reentry.
- **UR — interface-existence probe.** The return value of
  `isReceiverActive()` is intentionally ignored: registered ingress may sweep
  already-held USDC after deactivation so funds are not stranded. Successful
  decoding proves the interface; reversion rejects the address.
- **RG — guarded or accounting-benign callback.** The containing public flow is
  non-reentrant, and the reported write is bookkeeping performed after an
  exact-transfer or fixed-destination call. Reentry cannot observe a
  security-sensitive intermediate state.
- **RE — event ordering only.** The detector reports an event emitted after an
  external call. Authorization and state transitions are already enforced, or
  the rescue helper has no mutable post-call state. Reordering the event would
  not change authority, balances, or lifecycle state.
- **TS — intentional time/accounting comparison.** Vesting, beneficiary
  rotation, cooldowns, and emissions deliberately use timestamps. The remaining
  items are arithmetic balance, cap, inventory, or zero comparisons that Slither
  transitively associates with timestamp-derived accounting; none uses a
  timestamp as randomness or grants timestamp-dependent authority.
- **AS — bounds-checked decode.** The loop first requires a non-empty byte array
  whose length is a multiple of eight, advances in eight-byte steps, and uses
  memory-safe assembly only to read the current packed step. It then proves the
  exact aggregate MPS and duration.
- **PR — fixed multi-compiler graph.** Product contracts intentionally use
  Solidity 0.8.26, the techtree contract pins 0.8.28, and committed dependencies
  carry their own compatible pragmas. The literal gate compiles all three
  resolved compiler groups successfully.
- **LL — checked compatibility wrapper.** The low-level calls implement native
  transfer and ERC-20 compatibility. Every path checks contract code where
  applicable, call success, and either empty return data or decoded `true`;
  force-approve also validates the reset and retry.
- **MI — intentional structural typing.** The suggested interfaces are local
  call-site shapes, not ownership of the implementations. Adding inheritance
  would couple unrelated contracts without changing the ABI or safety
  properties.

## Exact result inventory

| Detector | Exact result ID | Exact primary location | Disposition |
|---|---|---|---|
| `reentrancy-balance` | `8c1dbd7fa06ce9e4e2d51587bc1467b4d7f9d06f1c43bc4b28f0a7db3feafffe` | `src/autolaunch/RegentLBPStrategy.sol#429-444` | RB |
| `reentrancy-balance` | `6f4c2b114056cae01f4e71b27719a13fbc3f2a3fe55b329e7072a2b98b69f0b3` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#617-626` | RB |
| `reentrancy-balance` | `5bdb5320520f82e0500d5413d5e999ab550ef80f0dcab4e6c01eab3ca9759699` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#785-794` | RB |
| `reentrancy-balance` | `932f1d2939d5e3b6ce6eb4ada1bad46c95b72839401752fbf122a64717b6f723` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#628-633` | RB |
| `reentrancy-balance` | `0390032efb4ac395865eaa3532be6ab73d2672333f6d73440437fec3878f9a56` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#796-801` | RB |
| `reentrancy-balance` | `16760b8fe036b29d666a8591bb2fdc64ca7306b0cce4c557023e18bde710c292` | `src/autolaunch/revenue/RegentDailyDistributor.sol#170-178` | RB |
| `reentrancy-balance` | `6c50b422b4a3b81041d1cf8400c9d6d3f7653347259ef30bb8bac5540eaa63fb` | `src/autolaunch/revenue/RegentEmissionVault.sol#47-55` | RB |
| `incorrect-equality` | `9d3304b4f933d2d8f0d2e930838f3a6f728c19045ae63d550ad1602922d4e37d` | `src/autolaunch/RegentLBPStrategy.sol#296-303` | EQ |
| `incorrect-equality` | `c319da4baa7405e6c9d797f1ae5da825af8960a37a494c93bbf0463c81f14cb2` | `src/autolaunch/revenue/DeferredAutolaunchFactory.sol#100-120` | EQ |
| `incorrect-equality` | `18914c6cf92822c67d32576f85a847941b43be1fef6de0f805e170c756337fe6` | `src/autolaunch/revenue/DeferredAutolaunchFactory.sol#122-135` | EQ |
| `incorrect-equality` | `95638b311c2d45d45e037f194b72f1f150b9bf01cd67cde276ceaa4ac31f1829` | `src/autolaunch/revenue/DeferredAutolaunchFactory.sol#122-135` | EQ |
| `incorrect-equality` | `0a9b9d7768aaea1ccb70795ba022aa808c4a607ba97423406ff189dbed736bc7` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#617-626` | EQ |
| `incorrect-equality` | `5aa86485431de37bd39db1dc5ef1f94b777e40fa489daa5e61814721ad2e62fd` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#628-633` | EQ |
| `incorrect-equality` | `5c04b6511c2b6465a3277fba3e28db117854eb86578f5e14de7f0ee995a9d85e` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#411-453` | EQ |
| `incorrect-equality` | `7731b72bdcc3ce50c32d783c7d23130c045c3d2ae59d372f4115dd7b66974bcf` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#411-453` | EQ |
| `incorrect-equality` | `6f74a2f48b2e15e28dc42ccebfecf5f77ca42b4ca1ff4a21dc369e44aece4b65` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#474-482` | EQ |
| `incorrect-equality` | `3557edac04fb316b710001e0710bcd5b4f91ff568d9e7d9fe446c6f0c3dacd1a` | `src/autolaunch/revenue/RegentDailyDistributor.sol#170-178` | EQ |
| `incorrect-equality` | `22f78c77efa62cd6cdb53fb0ab659c26c585a2d60b8e426c2645420b86a543d4` | `src/autolaunch/revenue/RegentEmissionVault.sol#47-55` | EQ |
| `incorrect-equality` | `eadeacc31299de9925993d965495dbef44fb3108cf91c73b3cb2cd300c82678b` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#785-794` | EQ |
| `incorrect-equality` | `fc08d7fac52ee686d30515832b33e1cbbf3cfd162d24a3e51bfc73a45540e5cf` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#796-801` | EQ |
| `incorrect-equality` | `90bd5cffd520936893682a382d73ca9760383fec28616b19f07e9b9a9315339a` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#636-645` | EQ |
| `incorrect-equality` | `5b24c9374793d9b67b67ba6a93d938a82059f91b5a9c794ec4848ceab2d8331c` | `src/staking/RegentRevenueStaking.sol#613-628` | EQ |
| `incorrect-equality` | `2e487d256b6e403553de0585af470e8cac5518d593c2d899b2927c57a3091921` | `src/staking/RegentRevenueStaking.sol#613-628` | EQ |
| `incorrect-equality` | `3ff1deba3309ca4c7bd416e5119d0f7f9d53bcb0076018b2fb22c5b3e158aea6` | `src/staking/RegentRevenueStaking.sol#656-665` | EQ |
| `incorrect-equality` | `979a873b3ea30f47d02f74ada6ef8c2861b641be9a8f27e89cc6148aecd334f2` | `src/staking/RegentRevenueStaking.sol#668-673` | EQ |
| `incorrect-equality` | `e2d1d51af6c0b8a6b819080445da951a30f3c85948cb39cbf9b50c15def615e3` | `src/staking/RegentRevenueStaking.sol#630-653` | EQ |
| `incorrect-equality` | `4f4dff04d0f97df56e3dc541f8cd50f7a41982d4a2138be65a9ec7de47a97529` | `src/staking/RegentRevenueStaking.sol#630-653` | EQ |
| `incorrect-equality` | `374a9b0b3f157ca53a2cb4948db04d67e6cfe3303d1eb7481d284f1fc98e7eac` | `src/staking/RegentRevenueStaking.sol#211-225` | EQ |
| `reentrancy-no-eth` | `bc063d1fbc0396b0a3e19d18ca6583472e5e88d4cafed3498cec7d08fc2528cf` | `src/autolaunch/LaunchDeploymentController.sol#203-233` | RN |
| `reentrancy-no-eth` | `4021650be335a6a1d8fb29471d9d08f8d0057b81895c3f6523767055e00ab96b` | `src/autolaunch/revenue/RevenueShareFactory.sol#130-160` | RN |
| `reentrancy-no-eth` | `79c711ad6c765262f2f8c6f9e9c21fd57afc1933935a5e6501e84b650bf36e65` | `src/autolaunch/LaunchDeploymentController.sol#179-190` | RN |
| `reentrancy-no-eth` | `9d1844498ecc89efd2904d4f2e2f9e295485da2b30cf767f0a3d4a0236a40a82` | `src/autolaunch/LaunchDeploymentController.sol#179-190` | RN |
| `reentrancy-no-eth` | `99769abe92f3b703d1be806143f1dc6ded725b821ce49c5cda7cc4d1dd79fbb0` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#181-198` | RN |
| `reentrancy-no-eth` | `888732826b36d231a5fb60792a577ec1600ad9f3adba347569d591c8d700bd8d` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#303-318` | RN |
| `unused-return` | `075ba042acc7dd6df51cd2c189d876dd5c516d17887c117f18d7b24939882955` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#528-568` | UR |
| `unused-return` | `539c3b5104e08e88f305433e31fbe667a8974c4f0c7df30cd182295c58965047` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#704-730` | UR |
| `reentrancy-benign` | `22aa4dcdff4120746d39b92ca64226c4b95def5d6ad7ff26fd479d10d72341b2` | `src/autolaunch/LaunchDeploymentController.sol#203-233` | RG |
| `reentrancy-benign` | `3c1b5661b6808fc9121eb2abd5d7760d3ef2a1b01842cc7679257fcf9f8ef82b` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#636-645` | RG |
| `reentrancy-benign` | `bfd9e379210ea2ae5f221969114db124566b756c943c27f53bbe4426fbfc496b` | `src/autolaunch/revenue/RegentDailyDistributor.sol#170-178` | RG |
| `reentrancy-benign` | `7e9d7d53ba17dfa296a70dc2bce308ced736ed6d128dee676ee7e191ec88ff81` | `src/autolaunch/revenue/RevenueIngressAccount.sol#112-137` | RG |
| `reentrancy-benign` | `4c91cc202bb8e8f1128450bb367f31beffe5d8ed313abdef69cb49f8cf68c627` | `src/autolaunch/RegentLBPStrategy.sol#240-262` | RG |
| `reentrancy-benign` | `61f1945f89f26180cbb4ad19330104239be73b7d6fb576ce4e2174e4bffebcc4` | `src/autolaunch/revenue/RegentStakingRevenueRouter.sol#67-93` | RG |
| `reentrancy-benign` | `a57fe6a3cb1a416ab190458031af6b8a7932569d0f3313081debfa36e1e65bbf` | `src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol#181-198` | RG |
| `reentrancy-events` | `8ce50cf0dfd1e8f15124bd057a577f30d8a99dcb293e7e02cd81084e4b8191a6` | `src/autolaunch/LaunchDeploymentController.sol#248-265` | RE |
| `reentrancy-events` | `1214a7b433d8d02c8693ec31fc7dec66dfa3055594a42d4a0077f29a1ae49335` | `src/autolaunch/LaunchDeploymentController.sol#280-346` | RE |
| `reentrancy-events` | `bd256f64652501adf169be0e0c612a3e21e2bb97a9ce0300818a3164993026ba` | `src/autolaunch/LaunchDeploymentController.sol#203-233` | RE |
| `reentrancy-events` | `1f2692e643d490236bbde6ec629365aef6fcad8b6200bdfd690ad6bc7ecfdda3` | `src/autolaunch/revenue/PermissionlessExistingTokenRevenueFactory.sol#70-129` | RE |
| `reentrancy-events` | `c0f67dc22958f8bd3275b13068fc8d2f9847df9bd7fae865c9e0f35c823ce4e8` | `src/autolaunch/revenue/RevenueShareFactory.sol#130-160` | RE |
| `reentrancy-events` | `fad6f2d98bef374d71c67e9681c504295b03cf399c78175ec05a9d18845dbf9b` | `src/autolaunch/LaunchDeploymentController.sol#179-190` | RE |
| `reentrancy-events` | `bb993edf5eb349d1c1a408e6292f0c8db86b200b9603791ec818a4178884f02d` | `src/autolaunch/LaunchDeploymentController.sol#179-190` | RE |
| `reentrancy-events` | `3debb0f96bca3d688dd9e08c75a5d6601e6162877ddeda59d89ca3105af92548` | `src/autolaunch/revenue/RegentEmissionVault.sol#61-73` | RE |
| `reentrancy-events` | `f24a8b2b1579b2cf7d8c6a65827076d6a96edf42d02cf1db7509ba13777d7580` | `src/autolaunch/revenue/SubjectRegistry.sol#197-212` | RE |
| `reentrancy-events` | `0d07bc51637cd4e3888d5cd30cfb84b3b5957609e113076ceed007b21dfe6963` | `src/shared/auth/Owned.sol#44-52` | RE |
| `reentrancy-events` | `f2777c518061a119e679c50ed135b5cdcb7ff7cc3eb54df6cea083d66101af3b` | `src/shared/auth/Owned.sol#54-65` | RE |
| `reentrancy-events` | `be24db3b77383dd8482e5b196ab1c28a2ac6ad29debf30160f041bf048c87522` | `src/autolaunch/revenue/RevenueIngressFactory.sol#136-149` | RE |
| `reentrancy-events` | `3e42216d53721bc805b92784db260a33d69fa46404dcfd24890bb51a58bf5736` | `src/autolaunch/revenue/PaymentLinkFactory.sol#103-116` | RE |
| `reentrancy-events` | `172d4ce3ecf41aec6d26a1860e3cd3e3c2166b1adc34777dba0a6c9587349f84` | `src/autolaunch/revenue/SubjectRegistry.sol#214-250` | RE |
| `timestamp` | `05e5bf2a3b8628ac1fcf94ded775a6cd9c0baf093c256c4b60a608dd04bb8575` | `src/autolaunch/AgentTokenVestingWallet.sol#121-132` | TS |
| `timestamp` | `c12b6ed8fb129a9c163a9376132e40b121a23680ae2484f4527bb79d2a0434f7` | `src/autolaunch/AgentTokenVestingWallet.sol#155-166` | TS |
| `timestamp` | `2337d5944209ab9a3664230bd03bcd672219cb3ce599400cbf47d8e163a4659b` | `src/autolaunch/AgentTokenVestingWallet.sol#197-217` | TS |
| `timestamp` | `02c852523374faaedf6cf7a2fc5b7ac9f84a6a276e6e05a4e8be56310ec17a94` | `src/autolaunch/DeferredAutolaunchVestingWallet.sol#67-75` | TS |
| `timestamp` | `896aead75febb4fec795dc9aa31e201509a6c901eabf3c8f68d74d19fc834fe6` | `src/autolaunch/DeferredAutolaunchVestingWallet.sol#95-105` | TS |
| `timestamp` | `e8bbf079bc511695ef7be5c7af2835dccd601e8f687bacab56dc5cecb9b0dd98` | `src/autolaunch/DeferredAutolaunchVestingWallet.sol#136-155` | TS |
| `timestamp` | `e55eefea7b89fbcfc3504bf341924e8397297465c9ef806e337020438b36816b` | `src/autolaunch/revenue/DeferredAutolaunchFactory.sol#122-135` | TS |
| `timestamp` | `58b91e63ecfd5ca2ebe4c8a67019a45fdf4907d4dcd4ca7e5ea9bbd68c95e65f` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#246-255` | TS |
| `timestamp` | `ae7b8a71fd1778d8849d56bd305b6fcb292595228a35f60e3a0501330c21b395` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#257-271` | TS |
| `timestamp` | `b22b3a65ef1e0900df3950023864c6b0edfbc1dd545fd675ad5d401e921f682a` | `src/autolaunch/revenue/RevenueShareSplitterV2.sol#282-295` | TS |
| `timestamp` | `022ad64d9aeb0ed8d76d7ed190a9b7f3e386a7ae9a95c41f021741384701c694` | `src/staking/RegentRevenueStaking.sol#171-184` | TS |
| `timestamp` | `6203008c10c0fa78f5ce41de8bdea44926be91f0d51a512049ca056e3c9ac79e` | `src/staking/RegentRevenueStaking.sol#211-225` | TS |
| `timestamp` | `ae0605dbeb6a6689e4360847cab3dd8f7966cd90fead11ed65c8a571269d67de` | `src/staking/RegentRevenueStaking.sol#227-241` | TS |
| `timestamp` | `ff4c62b7902a90b7488375dec3d71ed426818a3776ab75ac0e2d08df6abfbf0e` | `src/staking/RegentRevenueStaking.sol#243-247` | TS |
| `timestamp` | `1656be1945effab65e3e1876e37458b7ee8b760ad9fea6b311966fe832fc7270` | `src/staking/RegentRevenueStaking.sol#265-282` | TS |
| `timestamp` | `90839f10bb4740740eca2995a8e2b957a75641b590e2bd53a2ae3d4407b00987` | `src/staking/RegentRevenueStaking.sol#284-301` | TS |
| `timestamp` | `e0c82428786d1555a9cf810443c3e00502479cedcc6cc5189110ff5c310d436e` | `src/staking/RegentRevenueStaking.sol#337-355` | TS |
| `timestamp` | `a15249e4970805ad18c23c680c42c0bb17e0863bca540c2060c2b9c60ba00d23` | `src/staking/RegentRevenueStaking.sol#378-401` | TS |
| `timestamp` | `5f128817dad8e3697151f2e0bc54c944b10ebdaef808e4c531a27f572224aa8e` | `src/staking/RegentRevenueStaking.sol#403-417` | TS |
| `timestamp` | `d0a1cc897e070f2fce038161ef0f4f4566c5e2a0fce78af65ba7fd547c869dea` | `src/staking/RegentRevenueStaking.sol#424-433` | TS |
| `timestamp` | `5ab19ca6b7ce2735e36ef597ee5f80931ebdff052e2e22c4338e03e6f133fc92` | `src/staking/RegentRevenueStaking.sol#439-447` | TS |
| `timestamp` | `bf054d9b75539980e918c3ba498166d33afee03662ca077e8506af029def36e7` | `src/staking/RegentRevenueStaking.sol#449-457` | TS |
| `timestamp` | `dc807635de90c8716794955ecd835d3f69c48cfd8c96e63969bc6bed1e28125f` | `src/staking/RegentRevenueStaking.sol#459-468` | TS |
| `timestamp` | `11371b3b773c107e45a26afd98aa2b741768ac6abd3340bb8255758d5c20b44f` | `src/staking/RegentRevenueStaking.sol#470-479` | TS |
| `timestamp` | `5b0f5efa01cf79590227a42e77710976f131d9f11b10bf72545a06b7435a69f7` | `src/staking/RegentRevenueStaking.sol#485-515` | TS |
| `timestamp` | `f582572e87bcdd4fea3e8fe6853c77e4bccc5477230f6942f7a5917bdce72063` | `src/staking/RegentRevenueStaking.sol#517-576` | TS |
| `timestamp` | `88c1bf87fdb9f9c5f6d0c7aa731dbbaf8988bb1bd162b724905bbdccec94683d` | `src/staking/RegentRevenueStaking.sol#582-592` | TS |
| `timestamp` | `ec33bb3f28f8ab043aca30c333087619500e9abaef55fc0fc87b9f9c22dcf7ce` | `src/staking/RegentRevenueStaking.sol#594-601` | TS |
| `timestamp` | `e2fa09a67c5483dcb7629dd0c32703442a893463b8872786cb3d5b062aaf426c` | `src/staking/RegentRevenueStaking.sol#603-611` | TS |
| `timestamp` | `ee92c270637a57eef42b119f2d5e3eca8a2cc4b6f24e786646936fdc9b7abd17` | `src/staking/RegentRevenueStaking.sol#613-628` | TS |
| `timestamp` | `53cbb939713eba2c7dbc4cd5c7a22377a11a6b56c847b43d51ce16889a745f82` | `src/staking/RegentRevenueStaking.sol#630-653` | TS |
| `timestamp` | `6123c2256a09019988fe71e972b68437fb253d23a5fec83b8b137e6de75e72de` | `src/staking/RegentRevenueStaking.sol#668-673` | TS |
| `assembly` | `a365ec8ab6f8ae0ecfd51e3dfb7b5ad85a5d0e332c3826ffc0daa10a1d2ad9d7` | `src/autolaunch/LaunchDeploymentController.sol#700-723` | AS |
| `pragma` | `c2334ffa054fda88ce963ded5b108d132a6b0a3e23f44e936a12959819240617` | `lib/openzeppelin-contracts/contracts/utils/Panic.sol#4` | PR |
| `low-level-calls` | `22ebc1e53c636577ae6bb662eed24733ae330b2a4535ba50c3827e07b3b35b37` | `src/shared/libraries/SafeTransferLib.sol#7-18` | LL |
| `low-level-calls` | `c65d8dd1d861d62903782a534effccc13bef54bb27a1be2ced9be6e2cead4dcb` | `src/shared/libraries/SafeTransferLib.sol#20-26` | LL |
| `low-level-calls` | `ce736f2d0eec96fe28b4dd94a8309f30222e3be6a33fa95811242e357ddb3d72` | `src/shared/libraries/SafeTransferLib.sol#28-43` | LL |
| `missing-inheritance` | `10a6678f4d68c1765cb4f2d13ef4dd0950429359563970f190ac18ee099a5597` | `src/autolaunch/AgentTokenVestingWallet.sol#11-218` | MI |
| `missing-inheritance` | `4cd8720273ad399fef19ccab259171364da4ceafd2013973ea7bd456e1f87dbe` | `src/techtree/TechtreeGraphRegistryV1.sol#8-512` | MI |

### Stable fingerprint note

The 96 rows above are the literal entry inventory. Slither 0.11.5 can emit the
single `RegentLBPStrategy.migrate()` RG result with the same calls in either
order. The database retains the exact baseline ID
`4c91cc202bb8e8f1128450bb367f31beffe5d8ed313abdef69cb49f8cf68c627`
and stores the observed alternate ordering as that record's exact description.
Slither therefore matches the baseline form by ID and the regenerated form by
description. Both forms name the same
`src/autolaunch/RegentLBPStrategy.sol#240-262` location, calls, post-call
writes, and RG disposition. The database remains exactly 96 records for 96
logical baseline results; this is one bounded compatibility record, not an
additional finding or a detector exclusion.

## Candidate evidence

- U1/C0: complete; the literal Slither gate is restored without source,
  behavior, test, script, Foundry, submodule, or detector-scope changes.
- Literal `bin/gate.sh`: exit 0; 38 suites; 371 passed; 0 failed; 0 skipped.
- Literal `slither .`: exit 0; 102 contracts; 101 detectors; 0 untriaged
  results.
- The triage database contains exactly 96 baseline IDs and no absolute
  checkout path.
- `slither.config.json` remains the unchanged dependency-only configuration;
  no detector, severity, or product path is excluded.
