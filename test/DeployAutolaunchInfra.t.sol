// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployAutolaunchInfraScript} from "script/DeployAutolaunchInfra.s.sol";
import {AutolaunchCreateSequencerV1} from "src/autolaunch/AutolaunchCreateSequencerV1.sol";
import {AutolaunchFactoryV1} from "src/autolaunch/AutolaunchFactoryV1.sol";
import {IAutolaunchFactoryV1} from "src/autolaunch/interfaces/IAutolaunchFactoryV1.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {InputBounds} from "src/autolaunch/revenue/libraries/InputBounds.sol";
import {
    IRegentRevenueStakingMinimal
} from "src/autolaunch/revenue/interfaces/IRegentRevenueStakingMinimal.sol";
import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes calldata initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

interface ISafe {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) external view returns (bytes32);

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures
    ) external payable returns (bool success);

    function nonce() external view returns (uint256);
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
}

/// @dev Fixed external Base dependency. Only the reader the router constructor uses is needed.
contract LiveStakingBindingMock {
    address public constant usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
}

/// @dev Reenters the sequencer from a child constructor and records the outcome. Never a reviewed
/// ceremony initcode; only a hostile payload a separate sequencer instance is made to commit to.
contract ReentrantChildProbe {
    bool public reentryRefused;
    bytes public reentryReturnData;

    constructor(address sequencer, bytes memory reentrantCall) {
        // slither-disable-next-line low-level-calls
        (bool ok, bytes memory ret) = sequencer.call(reentrantCall);
        reentryRefused = !ok;
        reentryReturnData = ret;
    }
}

/// @dev Stands in for a governance caller so a child constructor can attempt an authorized
/// reentry and meet the phase gate rather than the authority gate.
contract GovernanceForwarder {
    function forward(address target, bytes calldata data) external {
        // slither-disable-next-line low-level-calls
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}

/// @dev Returns zero-length runtime. Never a reviewed ceremony initcode.
contract EmptyRuntimeChildProbe {
    constructor() {
        assembly ("memory-safe") {
            return(0, 0)
        }
    }
}

contract DeployAutolaunchInfraScriptTest is Test {
    address internal constant CREATOR = 0x000000000000000000000000000000000000C4EA;
    address internal constant TOKEN_FACTORY = 0x1111111111111111111111111111111111111111;
    address internal constant OPERATIONS_SAFE = 0x2222222222222222222222222222222222222222;
    address internal constant GUARDIAN = 0x4444444444444444444444444444444444444444;
    address internal constant ATTACKER = 0x5555555555555555555555555555555555555555;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address internal constant LIVE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    uint64 internal constant CREATOR_NONCE = 0;
    uint256 internal constant EIP170_MAX_RUNTIME_BYTES = 24_576;
    uint256 internal constant EIP3860_MAX_INITCODE_BYTES = 49_152;
    uint256 internal constant MAX_CALLDATA_BYTES = 100_000;
    uint256 internal constant MAX_TOTAL_GAS = 20_000_000;
    // Version-qualified artifact identifiers. Most of these sources declare `^0.8.26`, so the
    // repository gate resolves each of them at several compilers and Forge keeps the unsuffixed
    // artifact path for whichever one it wrote first. Naming 0.8.28 explicitly is what makes these
    // reads the same evidence the draft manifest records.
    string internal constant FACTORY_ARTIFACT =
        "AutolaunchFactoryV1.sol:AutolaunchFactoryV1:0.8.28";
    string internal constant SEQUENCER_ARTIFACT =
        "AutolaunchCreateSequencerV1.sol:AutolaunchCreateSequencerV1:0.8.28";
    string internal constant SPLITTER_ARTIFACT =
        "RevenueShareSplitterV2.sol:RevenueShareSplitterV2:0.8.28";

    // Canonical Safe 1.4.1 Base mainnet deployment, pinned by
    // test/fixtures/safe-1.4.1-base-8453-deployment-evidence.json. Harness-only fixed external
    // fixture; it is never part of the sequencer deployability evidence.
    string internal constant SAFE_FIXTURE =
        "test/fixtures/safe-1.4.1-base-8453-deployment-evidence.json";
    address internal constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address internal constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address internal constant SAFE_FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;
    uint256 internal constant OWNER_ONE_KEY = 0xA11CE;
    uint256 internal constant OWNER_TWO_KEY = 0xB0B;
    uint256 internal constant OWNER_THREE_KEY = 0xCA11;
    uint256 internal constant SAFE_THRESHOLD = 2;

    bytes32 internal constant CONSTRUCTOR_TYPEHASH =
        0x6e1e8f7b1a5de15fa2aadd33503de85b47cdbc151c53c83df2df74862a6e0fba;
    bytes32 internal constant FIXED_TYPEHASH =
        0x32ba980f8a2e1edef01731a3c84113908d409e004d68bd4677bf33faad970eba;
    bytes32 internal constant LIVE_TYPEHASH = keccak256(
        "AutolaunchLiveReadbacksV1(address subjectRegistry,address subjectRegistryController,address revenueShareController,address revenueIngressController,address paymentLinkController,address revenueIngressSubjectRegistry,address paymentLinkSubjectRegistry,address stakingRouter,address splitterDeployer,address revenueShareUsdc,address revenueIngressUsdc,address paymentLinkUsdc,address stakingRouterUsdc,address stakingRouterSubjectRegistry,address stakingRouterRegentRevenueStaking,bool strategyFactoryAuthorized,address feeInfraAuthorizedController,address subjectRegistryGovernance,address subjectRegistryGuardian)"
    );
    bytes32 internal constant BINDING_TYPEHASH =
        0xece30424d68a49316340bac7da891d7930b005201ccaea7ba1bcf2ef915ea7e6;
    bytes32 internal constant ABI_SHA256 =
        0x1e0001e35eecd2ca7503566b38df824e400de455173d080c73d4d70b9cea92f1;

    DeployAutolaunchInfraScript internal script;
    address internal governanceSafe;

    function setUp() external {
        vm.chainId(8453);
        script = new DeployAutolaunchInfraScript();
        // Placeholder code only. It satisfies the preflight's code-presence rule and is never
        // evidence about the live Safe identity, owners, threshold, guard, modules, or handler.
        vm.etch(TOKEN_FACTORY, hex"00");
        vm.etch(OPERATIONS_SAFE, hex"00");
        vm.etch(IDENTITY_REGISTRY, hex"00");
        vm.etch(GUARDIAN, hex"00");
        vm.etch(USDC, hex"00");
        vm.etch(LIVE_STAKING, address(new LiveStakingBindingMock()).code);
        _installPinnedSafeFixture();
        governanceSafe = _createGovernanceSafe();
    }

    // ---------------------------------------------------------------------
    // DEPLOYABLE_SEQUENCER / REAL_DEPLOYABILITY_EVIDENCE
    // ---------------------------------------------------------------------

    /// @notice DEPLOYABLE_SEQUENCER: the sequencer clears EIP-170 and EIP-3860 and embeds no
    /// child creation bytecode, and REAL_DEPLOYABILITY_EVIDENCE: every ceremony-created child is
    /// measured from its own real creation, never from etched or manufactured account state.
    function testSequencerAndEveryCeremonyChildClearProtocolLimits() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        bytes memory sequencerRuntime = vm.getDeployedCode(SEQUENCER_ARTIFACT);

        assertLe(prepared.createSequencer.initcode.length, EIP3860_MAX_INITCODE_BYTES);
        assertLe(sequencerRuntime.length, EIP170_MAX_RUNTIME_BYTES);

        bytes[9] memory initcodes = script.childInitcodes(_config());
        for (uint256 i; i < 9; ++i) {
            assertLe(initcodes[i].length, EIP3860_MAX_INITCODE_BYTES);
            // The sequencer runtime is shorter than every reviewed child initcode, so it cannot
            // embed any of them.
            assertLt(sequencerRuntime.length, initcodes[i].length);
        }

        _runCeremony(prepared);
        assertEq(prepared.addresses.sequencer.code.length, sequencerRuntime.length);
        address[9] memory children = _children(prepared.addresses);
        for (uint256 i; i < 9; ++i) {
            assertGt(children[i].code.length, 0);
            assertLe(children[i].code.length, EIP170_MAX_RUNTIME_BYTES);
            emit log_named_uint("ceremony child runtime bytes", children[i].code.length);
            emit log_named_uint("ceremony child initcode bytes", initcodes[i].length);
        }

        // The strategy factory constructor creates its own fixed deployer during the ceremony.
        address strategyDeployer = vm.computeCreateAddress(prepared.addresses.strategyFactory, 1);
        assertGt(strategyDeployer.code.length, 0);
        assertLe(strategyDeployer.code.length, EIP170_MAX_RUNTIME_BYTES);
        emit log_named_uint("sequencer runtime bytes", sequencerRuntime.length);
        emit log_named_uint("sequencer initcode bytes", prepared.createSequencer.initcode.length);
        emit log_named_uint("strategy deployer runtime bytes", strategyDeployer.code.length);
    }

    // ---------------------------------------------------------------------
    // FIVE_UNSIGNED_OUTPUTS
    // ---------------------------------------------------------------------

    /// @notice FIVE_UNSIGNED_OUTPUTS: preparation emits one structurally distinct creation record
    /// plus four zero-value governance calls, chooses no sender key, and broadcasts nothing.
    function testPreparedOutputsAreOneCreationAndFourGovernanceCalls() external view {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg = _config();
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(cfg);
        DeployAutolaunchInfraScript.DeploymentAddresses memory a = prepared.addresses;
        bytes[9] memory initcodes = script.childInitcodes(cfg);

        bytes32[9] memory hashes;
        for (uint256 i; i < 9; ++i) {
            hashes[i] = keccak256(initcodes[i]);
        }
        bytes memory expectedInitcode = bytes.concat(
            type(AutolaunchCreateSequencerV1).creationCode, abi.encode(governanceSafe, hashes)
        );

        assertEq(prepared.createSequencer.sender, CREATOR);
        assertEq(prepared.createSequencer.nonce, CREATOR_NONCE);
        assertEq(prepared.createSequencer.value, 0);
        assertEq(prepared.createSequencer.initcode, expectedInitcode);
        assertEq(prepared.createSequencer.initcodeHash, keccak256(expectedInitcode));
        assertEq(prepared.createSequencer.expectedAddress, a.sequencer);
        assertEq(a.sequencer, vm.computeCreateAddress(CREATOR, CREATOR_NONCE));
        for (uint256 i; i < 9; ++i) {
            assertEq(prepared.createSequencer.childInitcodeHashes[i], hashes[i]);
        }

        assertEq(prepared.dependenciesPhaseOne.sender, governanceSafe);
        assertEq(prepared.dependenciesPhaseOne.to, a.sequencer);
        assertEq(prepared.dependenciesPhaseOne.value, 0);
        assertEq(prepared.dependenciesPhaseTwo.sender, governanceSafe);
        assertEq(prepared.dependenciesPhaseTwo.to, a.sequencer);
        assertEq(prepared.dependenciesPhaseTwo.value, 0);
        assertEq(prepared.authorizeStrategyFactory.sender, governanceSafe);
        assertEq(prepared.authorizeStrategyFactory.to, a.strategyFactory);
        assertEq(prepared.authorizeStrategyFactory.value, 0);
        assertEq(prepared.deployFactory.sender, governanceSafe);
        assertEq(prepared.deployFactory.to, a.sequencer);
        assertEq(prepared.deployFactory.value, 0);

        bytes[4] memory phaseOne;
        bytes[4] memory phaseTwo;
        for (uint256 i; i < 4; ++i) {
            phaseOne[i] = initcodes[i];
            phaseTwo[i] = initcodes[i + 4];
        }
        assertEq(
            prepared.dependenciesPhaseOne.data,
            abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseOne, (phaseOne))
        );
        assertEq(
            prepared.dependenciesPhaseTwo.data,
            abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseTwo, (phaseTwo))
        );
        assertEq(
            prepared.authorizeStrategyFactory.data,
            abi.encodeCall(RegentLBPStrategyFactory.setAuthorizedCreator, (a.factory, true))
        );
        assertEq(
            prepared.deployFactory.data,
            abi.encodeCall(AutolaunchCreateSequencerV1.deployFactory, (initcodes[8]))
        );
        // The reviewed factory initcode is bound to the pinned factory source, not to whichever
        // compiler variant an artifact lookup happens to resolve.
        assertEq(
            initcodes[8],
            bytes.concat(
                type(AutolaunchFactoryV1).creationCode,
                abi.encode(
                    TOKEN_FACTORY,
                    a.strategyFactory,
                    a.revenueShareFactory,
                    a.revenueIngressFactory,
                    a.paymentLinkFactory,
                    a.feeInfraDeployer,
                    IDENTITY_REGISTRY,
                    OPERATIONS_SAFE
                )
            )
        );

        // Nothing was created, sent, or advanced by preparation itself.
        assertEq(a.sequencer.code.length, 0);
        assertEq(vm.getNonce(CREATOR), CREATOR_NONCE);
    }

    // ---------------------------------------------------------------------
    // NONCE_AND_ADDRESS_BINDING / FIXED_AUTHORITY_AND_PHASES
    // ---------------------------------------------------------------------

    /// @notice NONCE_AND_ADDRESS_BINDING: the ceremony runs end to end through the real governance
    /// Safe and lands every child on the internally derived CREATE address, with the sequencer
    /// spending exactly nonces one through nine.
    function testCeremonyExecutesThroughGovernanceSafeOnDerivedAddresses() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        DeployAutolaunchInfraScript.DeploymentAddresses memory a = prepared.addresses;

        address sequencer = _createSequencer(prepared);
        assertEq(sequencer, a.sequencer);
        assertEq(vm.getNonce(sequencer), 1);
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 0);
        assertEq(AutolaunchCreateSequencerV1(sequencer).governance(), governanceSafe);

        _safeExecute(prepared.dependenciesPhaseOne);
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 2);
        assertEq(vm.getNonce(sequencer), 5);

        _safeExecute(prepared.dependenciesPhaseTwo);
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 4);
        assertEq(vm.getNonce(sequencer), 9);

        _safeExecute(prepared.authorizeStrategyFactory);
        assertEq(vm.getNonce(sequencer), 9);
        assertTrue(RegentLBPStrategyFactory(a.strategyFactory).authorizedCreators(a.factory));

        _safeExecute(prepared.deployFactory);
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 6);
        assertEq(vm.getNonce(sequencer), 10);

        address[9] memory children = _children(a);
        for (uint256 i; i < 9; ++i) {
            assertEq(children[i], vm.computeCreateAddress(sequencer, i + 1));
            assertGt(children[i].code.length, 0);
            assertEq(children[i].balance, 0);
        }
        assertEq(sequencer.balance, 0);
        // The strategy factory creates its own fixed deployer without disturbing the sequence.
        assertGt(vm.computeCreateAddress(a.strategyFactory, 1).code.length, 0);
    }

    // ---------------------------------------------------------------------
    // BASE_TRANSACTION_BUDGET
    // ---------------------------------------------------------------------

    /// @notice BASE_TRANSACTION_BUDGET: every prepared transaction, measured as complete calldata
    /// plus intrinsic gas plus real Safe validation and forwarding, stays inside the fixed
    /// 100,000-byte and 20,000,000-gas ceilings.
    function testEveryPreparedTransactionFitsBaseCalldataAndGasCeilings() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());

        uint256 creationIntrinsic = _standardIntrinsicGas(prepared.createSequencer.initcode, true);
        assertLe(prepared.createSequencer.initcode.length, MAX_CALLDATA_BYTES);
        uint256 creationExecution = _createSequencerMeasured(prepared);
        uint256 creationTotal =
            _totalGas(prepared.createSequencer.initcode, creationIntrinsic, creationExecution);
        assertLe(creationTotal, MAX_TOTAL_GAS);
        emit log_named_uint(
            "createSequencer calldata bytes", prepared.createSequencer.initcode.length
        );
        emit log_named_uint("createSequencer total gas", creationTotal);

        _measureGovernanceCall("dependenciesPhaseOne", prepared.dependenciesPhaseOne);
        _measureGovernanceCall("dependenciesPhaseTwo", prepared.dependenciesPhaseTwo);
        _measureGovernanceCall("authorizeStrategyFactory", prepared.authorizeStrategyFactory);
        _measureGovernanceCall("deployFactory", prepared.deployFactory);
    }

    // ---------------------------------------------------------------------
    // EXACT_INITCODE_BINDING
    // ---------------------------------------------------------------------

    /// @notice EXACT_INITCODE_BINDING: a single flipped byte at any of the nine positions is
    /// refused onchain, in both dependency phases and in factory deployment.
    function testMutatedInitcodeIsRefusedAtEveryPosition() external {
        for (uint256 position; position < 9; ++position) {
            uint256 snapshot = vm.snapshotState();
            DeployAutolaunchInfraScript.PreparedDeployment memory prepared =
                script.prepare(_config());
            bytes[9] memory initcodes = script.childInitcodes(_config());
            address sequencer = _createSequencer(prepared);

            if (position >= 4) {
                _safeExecute(prepared.dependenciesPhaseOne);
            }
            if (position == 8) {
                _safeExecute(prepared.dependenciesPhaseTwo);
                _safeExecute(prepared.authorizeStrategyFactory);
            }

            initcodes[position] = _flipLastByte(initcodes[position]);
            bytes memory mutated = _phaseCalldata(initcodes, position);
            uint256 phaseBefore = uint256(AutolaunchCreateSequencerV1(sequencer).phase());
            uint64 nonceBefore = vm.getNonce(sequencer);

            vm.prank(governanceSafe);
            (bool ok, bytes memory ret) = sequencer.call(mutated);
            assertFalse(ok);
            assertEq(_revertReason(ret), "INITCODE_HASH_MISMATCH");
            assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), phaseBefore);
            assertEq(vm.getNonce(sequencer), nonceBefore);
            vm.revertToState(snapshot);
        }
    }

    /// @notice EXACT_INITCODE_BINDING: reordering or duplicating reviewed initcodes inside a phase
    /// is refused because each position carries its own immutable hash.
    function testReorderedAndDuplicatedInitcodesAreRefused() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        bytes[9] memory initcodes = script.childInitcodes(_config());
        address sequencer = _createSequencer(prepared);

        bytes[4] memory swapped;
        swapped[0] = initcodes[1];
        swapped[1] = initcodes[0];
        swapped[2] = initcodes[2];
        swapped[3] = initcodes[3];
        _expectPhaseOneRejection(sequencer, swapped, "INITCODE_HASH_MISMATCH");

        bytes[4] memory duplicated;
        duplicated[0] = initcodes[0];
        duplicated[1] = initcodes[0];
        duplicated[2] = initcodes[2];
        duplicated[3] = initcodes[3];
        _expectPhaseOneRejection(sequencer, duplicated, "INITCODE_HASH_MISMATCH");

        bytes[4] memory omitted;
        omitted[0] = initcodes[0];
        omitted[1] = initcodes[1];
        omitted[2] = initcodes[2];
        omitted[3] = "";
        _expectPhaseOneRejection(sequencer, omitted, "INITCODE_HASH_MISMATCH");

        bytes[4] memory phaseTwoInPhaseOne;
        for (uint256 i; i < 4; ++i) {
            phaseTwoInPhaseOne[i] = initcodes[i + 4];
        }
        _expectPhaseOneRejection(sequencer, phaseTwoInPhaseOne, "INITCODE_HASH_MISMATCH");
    }

    // ---------------------------------------------------------------------
    // FIXED_AUTHORITY_AND_PHASES
    // ---------------------------------------------------------------------

    /// @notice FIXED_AUTHORITY_AND_PHASES: only immutable governance may call the three
    /// entrypoints, and wrong, skipped, repeated, and post-terminal phases all fail.
    function testWrongCallerSkippedRepeatedAndPostTerminalPhasesFail() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        bytes[9] memory initcodes = script.childInitcodes(_config());
        address sequencer = _createSequencer(prepared);

        vm.prank(ATTACKER);
        (bool ok, bytes memory ret) = sequencer.call(prepared.dependenciesPhaseOne.data);
        assertFalse(ok);
        assertEq(_revertReason(ret), "ONLY_GOVERNANCE");
        vm.prank(CREATOR);
        (ok, ret) = sequencer.call(prepared.dependenciesPhaseOne.data);
        assertFalse(ok);
        assertEq(_revertReason(ret), "ONLY_GOVERNANCE");
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 0);
        assertEq(vm.getNonce(sequencer), 1);

        // Skipped phase two and skipped factory phase.
        _expectGovernanceRejection(sequencer, prepared.dependenciesPhaseTwo.data, "WRONG_PHASE");
        _expectGovernanceRejection(sequencer, prepared.deployFactory.data, "WRONG_PHASE");

        _safeExecute(prepared.dependenciesPhaseOne);
        // Repeated phase one and still-skipped factory phase.
        _expectGovernanceRejection(sequencer, prepared.dependenciesPhaseOne.data, "WRONG_PHASE");
        _expectGovernanceRejection(sequencer, prepared.deployFactory.data, "WRONG_PHASE");

        _safeExecute(prepared.dependenciesPhaseTwo);
        _expectGovernanceRejection(sequencer, prepared.dependenciesPhaseTwo.data, "WRONG_PHASE");
        _safeExecute(prepared.authorizeStrategyFactory);
        _safeExecute(prepared.deployFactory);

        // Post-terminal: every entrypoint is closed.
        _expectGovernanceRejection(sequencer, prepared.dependenciesPhaseOne.data, "WRONG_PHASE");
        _expectGovernanceRejection(sequencer, prepared.dependenciesPhaseTwo.data, "WRONG_PHASE");
        _expectGovernanceRejection(sequencer, prepared.deployFactory.data, "WRONG_PHASE");
        assertEq(vm.getNonce(sequencer), 10);
        assertGt(initcodes[8].length, 0);
    }

    /// @notice FIXED_AUTHORITY_AND_PHASES: the sequencer exposes no value, batch, delegation,
    /// reset, or authority-transfer surface and refuses plain value transfers.
    function testSequencerExposesNoValueOrAuthoritySurface() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        address sequencer = _createSequencer(prepared);

        vm.deal(ATTACKER, 1 ether);
        vm.prank(ATTACKER);
        (bool ok,) = sequencer.call{value: 1 ether}("");
        assertFalse(ok);

        bytes[8] memory probes;
        probes[0] = abi.encodeWithSignature("owner()");
        probes[1] = abi.encodeWithSignature("transferOwnership(address)", ATTACKER);
        probes[2] = abi.encodeWithSignature("setGovernance(address)", ATTACKER);
        probes[3] = abi.encodeWithSignature("reset()");
        probes[4] = abi.encodeWithSignature("execute(address,uint256,bytes)", ATTACKER, 0, "");
        probes[5] = abi.encodeWithSignature("deploy(bytes)", "");
        probes[6] = abi.encodeWithSignature("sweep(address)", ATTACKER);
        probes[7] = abi.encodeWithSignature("destroy()");
        for (uint256 i; i < probes.length; ++i) {
            vm.prank(governanceSafe);
            (ok,) = sequencer.call(probes[i]);
            assertFalse(ok);
        }
        assertEq(sequencer.balance, 0);
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 0);
        assertEq(vm.getNonce(sequencer), 1);
    }

    /// @notice FIXED_AUTHORITY_AND_PHASES: governance is immutable and nonzero.
    function testSequencerConstructionRejectsZeroGovernance() external {
        bytes32[9] memory hashes;
        vm.expectRevert("GOVERNANCE_ZERO");
        new AutolaunchCreateSequencerV1(address(0), hashes);
    }

    // ---------------------------------------------------------------------
    // ATOMIC_REACHABLE_FAILURES / EXISTING_FACTORY_AUTHORIZATION /
    // PREMATURE_AUTHORIZATION_IS_INEFFECTIVE
    // ---------------------------------------------------------------------

    /// @notice ATOMIC_REACHABLE_FAILURES, EXISTING_FACTORY_AUTHORIZATION and
    /// PREMATURE_AUTHORIZATION_IS_INEFFECTIVE: against the pinned Safe 1.4.1 harness, the
    /// authorization call sent to the predicted but still codeless strategy-factory address reports
    /// a successful Safe execution and advances the Safe nonce while granting no creator authority.
    /// Once the dependency phases have really created that factory, the reviewed factory deployment
    /// still makes the frozen factory constructor revert, and the sequencer restores its prior phase
    /// and nonce; only the real authorization lets the exact factory payload succeed.
    function testPrematureAuthorizationIsIneffectiveThenFactoryPhaseRetrySucceeds() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        DeployAutolaunchInfraScript.DeploymentAddresses memory a = prepared.addresses;
        address sequencer = _createSequencer(prepared);
        uint256 safeNonceBefore = ISafe(governanceSafe).nonce();

        // The Safe forwards a plain CALL, which the EVM completes successfully against an account
        // with no code, so the Safe reports success and spends its nonce for nothing.
        assertEq(a.strategyFactory.code.length, 0);
        (bool ok, bytes memory ret) =
            governanceSafe.call(_safeWrappedCalldata(prepared.authorizeStrategyFactory));
        assertTrue(ok);
        assertTrue(abi.decode(ret, (bool)));
        assertEq(ISafe(governanceSafe).nonce(), safeNonceBefore + 1);
        assertEq(a.strategyFactory.code.length, 0);

        _safeExecute(prepared.dependenciesPhaseOne);
        _safeExecute(prepared.dependenciesPhaseTwo);
        assertGt(a.strategyFactory.code.length, 0);
        assertFalse(RegentLBPStrategyFactory(a.strategyFactory).authorizedCreators(a.factory));

        // The unapproved factory payload reaches the frozen constructor readback and fails there,
        // not at the phase gate. This step uses the direct Governance caller path, so the exact
        // sequencer reason is observable and the Safe nonce is untouched by it.
        _expectGovernanceRejection(sequencer, prepared.deployFactory.data, "CREATE_FAILED");
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 4);
        assertEq(vm.getNonce(sequencer), 9);
        assertEq(ISafe(governanceSafe).nonce(), safeNonceBefore + 3);
        assertEq(a.factory.code.length, 0);

        _safeExecute(prepared.authorizeStrategyFactory);
        assertTrue(RegentLBPStrategyFactory(a.strategyFactory).authorizedCreators(a.factory));
        _safeExecute(prepared.deployFactory);
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 6);
        assertGt(a.factory.code.length, 0);
        assertEq(ISafe(governanceSafe).nonce(), safeNonceBefore + 5);
    }

    /// @notice ATOMIC_REACHABLE_FAILURES: an early, middle, or final failure inside a phase
    /// discards every creation that phase already made and leaves the phase retryable.
    function testPhaseFailureAtEveryPositionDiscardsThatWholePhase() external {
        for (uint256 position; position < 4; ++position) {
            uint256 snapshot = vm.snapshotState();
            DeployAutolaunchInfraScript.PreparedDeployment memory prepared =
                script.prepare(_config());
            bytes[9] memory initcodes = script.childInitcodes(_config());
            address sequencer = _createSequencer(prepared);

            bytes[4] memory phaseOne;
            for (uint256 i; i < 4; ++i) {
                phaseOne[i] = initcodes[i];
            }
            phaseOne[position] = _flipLastByte(phaseOne[position]);
            _expectPhaseOneRejection(sequencer, phaseOne, "INITCODE_HASH_MISMATCH");

            address[9] memory children = _children(prepared.addresses);
            for (uint256 i; i < 9; ++i) {
                assertEq(children[i].code.length, 0);
            }
            assertEq(vm.getNonce(sequencer), 1);
            assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 0);

            _safeExecute(prepared.dependenciesPhaseOne);
            assertEq(vm.getNonce(sequencer), 5);
            vm.revertToState(snapshot);
        }
    }

    /// @notice ATOMIC_REACHABLE_FAILURES: even if a committed initcode were hostile, a child
    /// constructor cannot reenter another phase and cannot leave a code-free result behind. The
    /// hostile payloads are committed to a separate instance of the real sequencer; no reviewed
    /// ceremony initcode is altered.
    function testHostileChildConstructorsCannotReenterOrReturnEmptyCode() external {
        bytes[4] memory unusedPayload;
        bytes memory reentrantCall =
            abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseTwo, (unusedPayload));

        // A child constructor reentering directly never reaches the phase gate.
        _assertReentryRefused(governanceSafe, address(0), reentrantCall, "ONLY_GOVERNANCE");
        // Even an authorized reentry is refused by the running phase the sequencer wrote first.
        GovernanceForwarder forwarder = new GovernanceForwarder();
        _assertReentryRefused(address(forwarder), address(forwarder), reentrantCall, "WRONG_PHASE");

        bytes memory emptyInitcode = type(EmptyRuntimeChildProbe).creationCode;
        bytes32[9] memory emptyHashes;
        emptyHashes[0] = keccak256(emptyInitcode);
        AutolaunchCreateSequencerV1 emptyProbe =
            new AutolaunchCreateSequencerV1(governanceSafe, emptyHashes);
        bytes[4] memory emptyPayload;
        emptyPayload[0] = emptyInitcode;
        vm.prank(governanceSafe);
        (bool ok, bytes memory ret) = address(emptyProbe)
            .call(
                abi.encodeCall(
                    AutolaunchCreateSequencerV1.deployDependenciesPhaseOne, (emptyPayload)
                )
            );
        assertFalse(ok);
        assertEq(_revertReason(ret), "CREATE_EMPTY_CODE");
        assertEq(uint256(emptyProbe.phase()), 0);
        assertEq(vm.getNonce(address(emptyProbe)), 1);
    }

    /// @dev Builds a sequencer whose four phase-one positions commit to a reentrant probe, runs
    /// the phase, and asserts every child's reentry attempt was refused for the given reason.
    function _assertReentryRefused(
        address probeGovernance,
        address reentryTarget,
        bytes memory reentrantCall,
        string memory reason
    ) private {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        address target = reentryTarget == address(0) ? predicted : reentryTarget;
        bytes memory data = reentryTarget == address(0)
            ? reentrantCall
            : abi.encodeCall(GovernanceForwarder.forward, (predicted, reentrantCall));
        bytes memory initcode =
            bytes.concat(type(ReentrantChildProbe).creationCode, abi.encode(target, data));

        bytes32[9] memory hashes;
        bytes[4] memory payload;
        for (uint256 i; i < 4; ++i) {
            hashes[i] = keccak256(initcode);
            payload[i] = initcode;
        }
        AutolaunchCreateSequencerV1 probe = new AutolaunchCreateSequencerV1(probeGovernance, hashes);
        assertEq(address(probe), predicted);

        vm.prank(probeGovernance);
        (bool ok,) = address(probe)
            .call(abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseOne, (payload)));
        assertTrue(ok);
        assertEq(uint256(probe.phase()), 2);
        assertEq(vm.getNonce(address(probe)), 5);
        for (uint256 i; i < 4; ++i) {
            ReentrantChildProbe child =
                ReentrantChildProbe(vm.computeCreateAddress(address(probe), i + 1));
            assertTrue(child.reentryRefused());
            assertEq(_revertReason(child.reentryReturnData()), reason);
        }
    }

    // ---------------------------------------------------------------------
    // NONCE_AND_ADDRESS_BINDING (preparation side)
    // ---------------------------------------------------------------------

    /// @notice NONCE_AND_ADDRESS_BINDING: preparation refuses a creator whose nonce has drifted
    /// away from the assumption the five outputs are bound to.
    function testPrepareRejectsCreatorNonceDrift() external {
        vm.setNonce(CREATOR, CREATOR_NONCE + 1);
        vm.expectRevert("CREATOR_NONCE_CHANGED");
        script.prepare(_config());
    }

    // ---------------------------------------------------------------------
    // DEPLOYED_ROLE_PREFLIGHT / FIXED_DEPENDENCY_PREFLIGHT
    // ---------------------------------------------------------------------

    /// @notice DEPLOYED_ROLE_PREFLIGHT: preparation yields the five-output packet only when the
    /// configured nonzero Governance and Guardian addresses both contain deployed code, and a
    /// configured zero address stays invalid under the existing rules.
    function testPrepareRequiresDeployedGovernanceAndGuardian() external view {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg = _config();
        assertGt(cfg.governance.code.length, 0);
        assertGt(cfg.guardian.code.length, 0);
        (bool ok,) = _prepareOutcome(cfg);
        assertTrue(ok);

        cfg.governance = ATTACKER;
        assertEq(ATTACKER.code.length, 0);
        _assertPrepareFails(cfg, "GOVERNANCE_NOT_DEPLOYED");

        cfg = _config();
        cfg.guardian = ATTACKER;
        _assertPrepareFails(cfg, "GUARDIAN_NOT_DEPLOYED");

        cfg = _config();
        cfg.governance = address(0);
        _assertPrepareFails(cfg, "GOVERNANCE_ZERO");

        cfg = _config();
        cfg.guardian = address(0);
        _assertPrepareFails(cfg, "GUARDIAN_ZERO");
    }

    /// @notice FIXED_DEPENDENCY_PREFLIGHT: preparation yields no packet unless canonical USDC, the
    /// canonical identity registry, and LIVE_STAKING each contain code and LIVE_STAKING decodes
    /// canonical USDC through `usdc()`. Harmless trailing return data is not a malformed answer.
    function testPrepareRequiresFixedDependencyCodeAndLiveStakingUsdcBinding() external {
        _assertPrepareFailsWithoutCode(USDC, "USDC_NOT_DEPLOYED");
        _assertPrepareFailsWithoutCode(IDENTITY_REGISTRY, "IDENTITY_REGISTRY_NOT_DEPLOYED");
        _assertPrepareFailsWithoutCode(LIVE_STAKING, "LIVE_STAKING_NOT_DEPLOYED");

        _mockUsdcReturn(abi.encode(ATTACKER));
        _assertPrepareFails(_config(), "LIVE_STAKING_USDC_MISMATCH");

        vm.clearMockedCalls();
        vm.mockCallRevert(LIVE_STAKING, _usdcCall(), bytes("LIVE_STAKING_READER_DOWN"));
        _assertPrepareRejected();

        _mockUsdcReturn(hex"");
        _assertPrepareRejected();
        _mockUsdcReturn(_slice(abi.encode(USDC), 1));
        _assertPrepareRejected();
        _mockUsdcReturn(abi.encode(uint256(uint160(USDC)) | (uint256(1) << 160)));
        _assertPrepareRejected();

        _mockUsdcReturn(bytes.concat(abi.encode(USDC), bytes32(0)));
        (bool ok,) = _prepareOutcome(_config());
        assertTrue(ok);
    }

    // ---------------------------------------------------------------------
    // PHASE_ONE_RETRY_PROOF
    // ---------------------------------------------------------------------

    /// @notice PHASE_ONE_RETRY_PROOF: a harness-induced LIVE_STAKING/USDC mismatch stands in for a
    /// fixed-dependency change between preparation and execution; it is not evidence that such
    /// drift is reachable on Base mainnet. The frozen router constructor reverts, the whole
    /// external phase-one call discards every child creation and its phase and nonce effects, and
    /// the byte-identical retry after the reviewed binding is restored succeeds once at the same
    /// predicted addresses. The failing call uses the direct Governance caller path so the exact
    /// sequencer reason is observable and the Safe nonce is untouched; the retry uses the Safe
    /// wrapper and advances that nonce by one.
    function testPhaseOneRollsBackOnFixedDependencyMismatchAndRetriesByteIdentically() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        DeployAutolaunchInfraScript.DeploymentAddresses memory a = prepared.addresses;
        address sequencer = _createSequencer(prepared);
        bytes memory reviewedPhaseOne = bytes.concat(prepared.dependenciesPhaseOne.data);
        uint256 safeNonceBefore = ISafe(governanceSafe).nonce();

        vm.mockCall(LIVE_STAKING, _usdcCall(), abi.encode(ATTACKER));
        _expectGovernanceRejection(sequencer, reviewedPhaseOne, "CREATE_FAILED");
        assertEq(ISafe(governanceSafe).nonce(), safeNonceBefore);
        address[9] memory children = _children(a);
        for (uint256 i; i < 9; ++i) {
            assertEq(children[i].code.length, 0);
        }

        vm.clearMockedCalls();
        assertEq(reviewedPhaseOne, prepared.dependenciesPhaseOne.data);
        _safeExecute(prepared.dependenciesPhaseOne);
        assertEq(ISafe(governanceSafe).nonce(), safeNonceBefore + 1);
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), 2);
        assertEq(vm.getNonce(sequencer), 5);
        for (uint256 i; i < 4; ++i) {
            assertEq(children[i], vm.computeCreateAddress(sequencer, i + 1));
            assertGt(children[i].code.length, 0);
        }
    }

    // ---------------------------------------------------------------------
    // EXACT_ARTIFACT_PROVENANCE
    // ---------------------------------------------------------------------

    /// @notice EXACT_ARTIFACT_PROVENANCE: the launch-time RevenueShareSplitterV2 sizes recorded in
    /// the draft manifest are recomputed from its own artifact and the real ten-argument
    /// constructor encoding, at the longest label its constructor accepts rather than at a shorter
    /// sample. The exact byte counts stay informational; only the protocol limits are asserted.
    function testRevenueShareSplitterV2SizesAreRecomputedFromItsArtifact() external {
        bytes memory runtime = vm.getDeployedCode(SPLITTER_ARTIFACT);
        assertLe(runtime.length, EIP170_MAX_RUNTIME_BYTES);
        emit log_named_uint("revenueShareSplitterV2 runtime bytes", runtime.length);

        uint256 enforcedMaximumInitcode = _splitterInitcodeLength(InputBounds.MAX_LABEL_BYTES);
        uint256 declaredTokenNameInitcode =
            _splitterInitcodeLength(InputBounds.MAX_TOKEN_NAME_BYTES);
        assertLe(enforcedMaximumInitcode, EIP3860_MAX_INITCODE_BYTES);
        assertGt(enforcedMaximumInitcode, declaredTokenNameInitcode);
        emit log_named_uint(
            "revenueShareSplitterV2 initcode bytes at MAX_LABEL_BYTES", enforcedMaximumInitcode
        );
        emit log_named_uint(
            "revenueShareSplitterV2 initcode bytes at MAX_TOKEN_NAME_BYTES",
            declaredTokenNameInitcode
        );
    }

    /// @notice EXACT_ARTIFACT_PROVENANCE: every artifact this suite reads by name is byte-identical
    /// to the compilation unit that actually builds the ceremony packet. This file is pinned to
    /// 0.8.28, so an identifier that silently resolved to another resolved compiler group would
    /// stop matching here before it could be recorded as ceremony evidence.
    function testNamedArtifactsAreTheSameUnitThatBuildsThePacket() external view {
        assertEq(
            keccak256(vm.getCode(SEQUENCER_ARTIFACT)),
            keccak256(type(AutolaunchCreateSequencerV1).creationCode)
        );
        assertEq(
            keccak256(vm.getCode(FACTORY_ARTIFACT)),
            keccak256(type(AutolaunchFactoryV1).creationCode)
        );
        assertEq(
            keccak256(vm.getCode(SPLITTER_ARTIFACT)),
            keccak256(type(RevenueShareSplitterV2).creationCode)
        );
    }

    /// @dev The launch-time label is the token name, bounded by the splitter constructor itself.
    function _splitterInitcodeLength(uint256 labelBytes) private pure returns (uint256) {
        return bytes.concat(
            type(RevenueShareSplitterV2).creationCode,
            abi.encode(
                address(1),
                USDC,
                address(2),
                address(3),
                bytes32(uint256(4)),
                address(5),
                address(6),
                uint256(7),
                string(new bytes(labelBytes)),
                address(8)
            )
        )
        .length;
    }

    // ---------------------------------------------------------------------
    // FACTORY_BEHAVIOR_UNCHANGED / COMPLETE_CANDIDATE_EVIDENCE
    // ---------------------------------------------------------------------

    /// @notice FACTORY_BEHAVIOR_UNCHANGED: the deployed factory runtime equals the candidate
    /// artifact except for its immutable address substitutions, and COMPLETE_CANDIDATE_EVIDENCE:
    /// the binding digest is recomputed from artifacts, typehashes, and live readbacks.
    function testFactoryIdentityAndBindingDigestAreRecomputed() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        DeployAutolaunchInfraScript.DeploymentAddresses memory a = prepared.addresses;
        _runCeremony(prepared);

        _assertRuntimeMatchesCandidateArtifact(a.factory);
        assertLe(a.factory.code.length, EIP170_MAX_RUNTIME_BYTES);
        emit log_named_uint("factory runtime bytes", a.factory.code.length);
        emit log_named_bytes32("factory runtime code hash", a.factory.codehash);

        IRegentStakingRevenueRouter router = IRegentStakingRevenueRouter(a.stakingRouter);
        assertEq(router.protocolSkimBps(), 200);
        bytes32 liveBeforeSkimChange = _liveReadbacksHash(a);
        vm.expectEmit(false, false, false, true, a.stakingRouter);
        emit IRegentStakingRevenueRouter.ProtocolSkimBpsSet(200, 0);
        vm.prank(governanceSafe);
        router.setProtocolSkimBps(0);
        assertEq(router.protocolSkimBps(), 0);
        assertEq(_liveReadbacksHash(a), liveBeforeSkimChange);

        bytes32 constructorHash = keccak256(
            abi.encode(
                CONSTRUCTOR_TYPEHASH,
                TOKEN_FACTORY,
                a.strategyFactory,
                a.revenueShareFactory,
                a.revenueIngressFactory,
                a.paymentLinkFactory,
                a.feeInfraDeployer,
                IDENTITY_REGISTRY,
                OPERATIONS_SAFE
            )
        );
        bytes32 fixedHash = keccak256(
            abi.encode(
                FIXED_TYPEHASH,
                USDC,
                0x6f89bcA4eA5931EdFCB09786267b251DeE752b07,
                0x000000001F26a0044BaA66024e7b6599c61963F8,
                0x498581fF718922c3f8e6A244956aF099B2652b2b,
                0x7C5f5A4bBd8fD63184577525326123B519429bDc,
                LIVE_STAKING
            )
        );
        bytes32 bindingDigest = keccak256(
            abi.encode(
                BINDING_TYPEHASH,
                block.chainid,
                a.factory,
                a.factory.codehash,
                ABI_SHA256,
                constructorHash,
                fixedHash,
                _liveReadbacksHash(a)
            )
        );
        emit log_named_bytes32("constructor bindings hash", constructorHash);
        emit log_named_bytes32("live readbacks hash", _liveReadbacksHash(a));
        emit log_named_bytes32("factory binding digest", bindingDigest);
        assertEq(fixedHash, 0x7fd468b6a0bc2dab66815bb15e6aa4ab42ec56e5f7aae62f4431bc94a58df03f);
        assertEq(
            constructorHash, 0xeb467fcf358652bf25f6a34005deb87d86a9d0ee9ae41ccfe25201f60ba031c5
        );
        assertEq(
            _liveReadbacksHash(a),
            0xbbdd4971cb8d0b08abe9bafa3fa25b761c49a3ae92de7c453927f68e3c93607b
        );
        assertEq(
            a.factory.codehash, 0xb73321bfe0953160466ee38a3ca235b908c165dfdfe76270f329a4cda905ae38
        );
        assertEq(bindingDigest, 0xf89577524e953e1cfee15260e3aa31234c434c38b56389b808c01e32dd0747eb);
    }

    /// @notice FACTORY_BEHAVIOR_UNCHANGED: retired controller-era selectors stay absent from the
    /// deployed factory and touch no ceremony state.
    function testRetiredFactorySelectorsStillReject() external {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        _runCeremony(prepared);
        address factory = prepared.addresses.factory;

        bytes[14] memory probes = _retiredSelectorProbes();
        address[9] memory targets = _children(prepared.addresses);
        bytes32[9] memory codehashes;
        for (uint256 i; i < targets.length; ++i) {
            codehashes[i] = targets[i].codehash;
        }
        uint64 sequencerNonce = vm.getNonce(prepared.addresses.sequencer);

        for (uint256 i; i < probes.length; ++i) {
            vm.recordLogs();
            (bool ok,) = factory.call(probes[i]);
            assertFalse(ok);
            assertEq(vm.getRecordedLogs().length, 0);
            assertEq(vm.getNonce(prepared.addresses.sequencer), sequencerNonce);
            for (uint256 j; j < targets.length; ++j) {
                assertEq(targets[j].codehash, codehashes[j]);
                assertEq(targets[j].balance, 0);
            }
        }
    }

    /// @notice COMPLETE_CANDIDATE_EVIDENCE: the candidate address vector and the nine exact
    /// initcode hashes recorded in the draft manifest are recomputed here from the current
    /// artifacts, never transcribed from an earlier run.
    function testCandidateDeterministicVectorIsRecomputed() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg = _config();
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(cfg);
        DeployAutolaunchInfraScript.DeploymentAddresses memory a = prepared.addresses;

        emit log_named_address("sequencer", a.sequencer);
        emit log_named_address("subjectRegistry", a.subjectRegistry);
        emit log_named_address("stakingRouter", a.stakingRouter);
        emit log_named_address("splitterDeployer", a.splitterDeployer);
        emit log_named_address("revenueShareFactory", a.revenueShareFactory);
        emit log_named_address("revenueIngressFactory", a.revenueIngressFactory);
        emit log_named_address("paymentLinkFactory", a.paymentLinkFactory);
        emit log_named_address("strategyFactory", a.strategyFactory);
        emit log_named_address("feeInfraDeployer", a.feeInfraDeployer);
        emit log_named_address("factory", a.factory);
        emit log_named_address("governanceSafe", governanceSafe);
        emit log_named_bytes32("sequencerInitcodeHash", prepared.createSequencer.initcodeHash);
        for (uint256 i; i < 9; ++i) {
            emit log_named_bytes32(
                "childInitcodeHash", prepared.createSequencer.childInitcodeHashes[i]
            );
        }

        assertEq(governanceSafe, 0x26a01Fa4aA5292821c8Ca62F2933D86969F462A2);
        assertEq(a.sequencer, 0xf05358E6880ed2b8Af3407cC296E2d994A6d7BE3);
        assertEq(a.subjectRegistry, 0x8CF0292787AAA4B728281daD16D178142CA1b290);
        assertEq(a.stakingRouter, 0xCc99CE29bf071c7986eb29C12bEd973e0D6C6390);
        assertEq(a.splitterDeployer, 0x36E43665b8ED43cE85f1966D5ba29D184547aB99);
        assertEq(a.revenueShareFactory, 0x138605F49375239eae0197D68ecc3630099025dD);
        assertEq(a.revenueIngressFactory, 0xAb707A94e6Af3dc23E47A5DADF9d39C005c81651);
        assertEq(a.paymentLinkFactory, 0x278048Ca4B6E5164f789b4355fBb922A1BC07c94);
        assertEq(a.strategyFactory, 0x2e612cE79A916276D24370290D102f2EED26F69F);
        assertEq(a.feeInfraDeployer, 0x3F664c2Ca8aDfAd88De1a3965C32cAf2FE4854b9);
        assertEq(a.factory, 0xF916521bf0AE0E520A0e179743e20F0Cd91d36f6);

        assertEq(
            prepared.createSequencer.initcodeHash,
            0x59859f466259129df57532544142c54ac31cdc0fdd191ad1949c99e1461e0ef4
        );
        bytes32[9] memory expectedChildHashes = [
            bytes32(0x21bf5664bce630094128dc01278503ae3ea7cea123fd8d1da58cfacece57c37e),
            0x8e18860604c47177b281de6b70f18a4e56574abf8af55a88a1a6738e0c448359,
            0xc17b27bc6f5a861698094174041ee41a149f39b20f220733caeda253a64ad3b6,
            0xb2f52e64f3e30dae89802bea9776b6c109f507808cdac703e6648f4f7886087d,
            0x49621d7d0bc6e117e962c41ceca776b41f1bc2495aeaf96163658dc4f03bcb9f,
            0xd3538683cc44680faaebeaac7dd77b7ced62441342bc390416abe561f70db7c4,
            0xf55e1729f747ea4fd65e87ffc7423e38685f1b8ab552dd2dec5633e2e5e03bdd,
            0xdea8c536f3de42a1ed8c8b23e53db4363b03e2c940ad970d787539576b7424d9,
            0x1dd5d1799f46f116ff2bea776039ff1683ae915957e647c63635e31f7701bd31
        ];
        for (uint256 i; i < 9; ++i) {
            assertEq(prepared.createSequencer.childInitcodeHashes[i], expectedChildHashes[i]);
        }
    }

    /// @notice COMPLETE_CANDIDATE_EVIDENCE: every binding typehash is derived from its exact
    /// string rather than transcribed.
    function testTypehashesAreDerivedFromExactStrings() external pure {
        assertEq(
            CONSTRUCTOR_TYPEHASH,
            keccak256(
                bytes(
                    "AutolaunchConstructorBindingsV1(address tokenFactory,address strategyFactory,address revenueShareFactory,address revenueIngressFactory,address paymentLinkFactory,address feeInfraDeployer,address identityRegistry,address operationsSafe)"
                )
            )
        );
        assertEq(
            FIXED_TYPEHASH,
            keccak256(
                bytes(
                    "AutolaunchFixedBindingsV1(address usdc,address regent,address ccaFactory,address poolManager,address positionManager,address liveStaking)"
                )
            )
        );
        assertEq(
            LIVE_TYPEHASH,
            keccak256(
                bytes(
                    "AutolaunchLiveReadbacksV1(address subjectRegistry,address subjectRegistryController,address revenueShareController,address revenueIngressController,address paymentLinkController,address revenueIngressSubjectRegistry,address paymentLinkSubjectRegistry,address stakingRouter,address splitterDeployer,address revenueShareUsdc,address revenueIngressUsdc,address paymentLinkUsdc,address stakingRouterUsdc,address stakingRouterSubjectRegistry,address stakingRouterRegentRevenueStaking,bool strategyFactoryAuthorized,address feeInfraAuthorizedController,address subjectRegistryGovernance,address subjectRegistryGuardian)"
                )
            )
        );
        assertEq(
            BINDING_TYPEHASH,
            keccak256(
                bytes(
                    "AutolaunchFactoryBindingV1(uint256 chainId,address factory,bytes32 runtimeCodeHash,bytes32 interfaceAbiSha256,bytes32 constructorBindingsHash,bytes32 fixedBindingsHash,bytes32 liveReadbacksHash)"
                )
            )
        );
    }

    // Auxiliary frozen vector only; release evidence normalizes the explicit compiler artifacts
    // out/IAutolaunchFactoryV1.sol/IAutolaunchFactoryV1.json and
    // out/AutolaunchFactoryV1.sol/AutolaunchFactoryV1.json with jq.
    function testAuxiliaryNormalizedInterfaceAbiVector() external pure {
        bytes memory normalized = bytes(
            '[{"inputs":[{"components":[{"name":"agentId","type":"uint256"},{"name":"tokenName","type":"string"},{"name":"tokenSymbol","type":"string"},{"name":"startBlock","type":"uint64"},{"name":"floorPrice","type":"uint256"},{"name":"requiredRegentRaised","type":"uint128"},{"name":"expectedFee","type":"uint256"},{"name":"launchFeeHookSalt","type":"bytes32"}],"name":"params","type":"tuple"}],"name":"launch","outputs":[{"components":[{"name":"token","type":"address"},{"name":"auction","type":"address"},{"name":"strategy","type":"address"},{"name":"vestingWallet","type":"address"},{"name":"revenueShare","type":"address"},{"name":"defaultIngress","type":"address"},{"name":"canonicalPaymentLink","type":"address"},{"name":"subjectId","type":"bytes32"},{"name":"poolId","type":"bytes32"}],"name":"result","type":"tuple"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"launchFee","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"newLaunchFee","type":"uint256"}],"name":"setLaunchFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"anonymous":false,"inputs":[{"indexed":true,"name":"launchId","type":"bytes32"},{"indexed":true,"name":"agentId","type":"uint256"},{"indexed":true,"name":"agentSafe","type":"address"},{"indexed":false,"name":"token","type":"address"},{"indexed":false,"name":"auction","type":"address"},{"indexed":false,"name":"strategy","type":"address"},{"indexed":false,"name":"vestingWallet","type":"address"},{"indexed":false,"name":"revenueShare","type":"address"},{"indexed":false,"name":"defaultIngress","type":"address"},{"indexed":false,"name":"canonicalPaymentLink","type":"address"},{"indexed":false,"name":"poolId","type":"bytes32"}],"name":"LaunchCreated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"previousLaunchFee","type":"uint256"},{"indexed":false,"name":"newLaunchFee","type":"uint256"}],"name":"LaunchFeeUpdated","type":"event"}]'
        );
        assertEq(normalized.length, 1982);
        assertEq(sha256(normalized), ABI_SHA256);
    }

    function testSelectorTopicAndTupleShapesAreDerivedIndependently() external pure {
        IAutolaunchFactoryV1.LaunchParams memory params = IAutolaunchFactoryV1.LaunchParams({
            agentId: 7,
            tokenName: "Agent",
            tokenSymbol: "AGENT",
            startBlock: 1234,
            floorPrice: 5678,
            requiredRegentRaised: 90,
            expectedFee: 123,
            launchFeeHookSalt: bytes32(uint256(11))
        });
        bytes memory callData = abi.encodeCall(IAutolaunchFactoryV1.launch, (params));
        assertEq(
            IAutolaunchFactoryV1.launch.selector,
            bytes4(
                keccak256("launch((uint256,string,string,uint64,uint256,uint128,uint256,bytes32))")
            )
        );
        assertEq(bytes4(callData), IAutolaunchFactoryV1.launch.selector);
        IAutolaunchFactoryV1.LaunchParams memory decoded =
            abi.decode(_slice(callData, 4), (IAutolaunchFactoryV1.LaunchParams));
        assertEq(decoded.agentId, params.agentId);
        assertEq(decoded.tokenName, params.tokenName);
        assertEq(decoded.tokenSymbol, params.tokenSymbol);
        assertEq(decoded.startBlock, params.startBlock);
        assertEq(decoded.floorPrice, params.floorPrice);
        assertEq(decoded.requiredRegentRaised, params.requiredRegentRaised);
        assertEq(decoded.expectedFee, params.expectedFee);
        assertEq(decoded.launchFeeHookSalt, params.launchFeeHookSalt);

        IAutolaunchFactoryV1.LaunchResult memory result = IAutolaunchFactoryV1.LaunchResult({
            token: address(1),
            auction: address(2),
            strategy: address(3),
            vestingWallet: address(4),
            revenueShare: address(5),
            defaultIngress: address(6),
            canonicalPaymentLink: address(7),
            subjectId: bytes32(uint256(8)),
            poolId: bytes32(uint256(9))
        });
        assertEq(abi.encode(result).length, 9 * 32);
        assertEq(
            keccak256(
                "LaunchCreated(bytes32,uint256,address,address,address,address,address,address,address,address,bytes32)"
            ),
            0xb94615399bcd85c2768d93dd0d311a8b2bf5f21033f836bfee1a08992018db18
        );
    }

    // ---------------------------------------------------------------------
    // Ceremony helpers
    // ---------------------------------------------------------------------

    function _config() private view returns (DeployAutolaunchInfraScript.ScriptConfig memory) {
        return DeployAutolaunchInfraScript.ScriptConfig({
            creator: CREATOR,
            creatorNonce: CREATOR_NONCE,
            governance: governanceSafe,
            guardian: GUARDIAN,
            tokenFactory: TOKEN_FACTORY,
            operationsSafe: OPERATIONS_SAFE
        });
    }

    /// @dev A refused preflight must return no packet at all, so the outcome is observed as the
    /// raw call result rather than as a decoded return value.
    function _prepareOutcome(DeployAutolaunchInfraScript.ScriptConfig memory cfg)
        private
        view
        returns (bool ok, bytes memory ret)
    {
        (ok, ret) = address(script)
            .staticcall(abi.encodeCall(DeployAutolaunchInfraScript.prepare, (cfg)));
    }

    function _assertPrepareFails(
        DeployAutolaunchInfraScript.ScriptConfig memory cfg,
        string memory reason
    ) private view {
        (bool ok, bytes memory ret) = _prepareOutcome(cfg);
        assertFalse(ok);
        assertEq(_revertReason(ret), reason);
    }

    function _assertPrepareFailsWithoutCode(address dependency, string memory reason) private {
        bytes memory restored = dependency.code;
        vm.etch(dependency, hex"");
        _assertPrepareFails(_config(), reason);
        vm.etch(dependency, restored);
    }

    function _assertPrepareRejected() private view {
        (bool ok,) = _prepareOutcome(_config());
        assertFalse(ok);
    }

    function _mockUsdcReturn(bytes memory returnData) private {
        vm.clearMockedCalls();
        vm.mockCall(LIVE_STAKING, _usdcCall(), returnData);
    }

    function _usdcCall() private pure returns (bytes memory) {
        return abi.encodeCall(IRegentRevenueStakingMinimal.usdc, ());
    }

    function _createSequencer(DeployAutolaunchInfraScript.PreparedDeployment memory prepared)
        private
        returns (address created)
    {
        bytes memory initcode = prepared.createSequencer.initcode;
        vm.prank(prepared.createSequencer.sender);
        assembly ("memory-safe") {
            created := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(created == prepared.createSequencer.expectedAddress, "SEQUENCER_ADDRESS_MISMATCH");
    }

    function _createSequencerMeasured(
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared
    ) private returns (uint256 executionGas) {
        bytes memory initcode = prepared.createSequencer.initcode;
        address created;
        vm.prank(prepared.createSequencer.sender);
        uint256 startGas = gasleft();
        assembly ("memory-safe") {
            created := create(0, add(initcode, 0x20), mload(initcode))
        }
        executionGas = startGas - gasleft();
        assertEq(created, prepared.createSequencer.expectedAddress);
    }

    function _runCeremony(DeployAutolaunchInfraScript.PreparedDeployment memory prepared) private {
        _createSequencer(prepared);
        _safeExecute(prepared.dependenciesPhaseOne);
        _safeExecute(prepared.dependenciesPhaseTwo);
        _safeExecute(prepared.authorizeStrategyFactory);
        _safeExecute(prepared.deployFactory);
    }

    function _phaseCalldata(bytes[9] memory initcodes, uint256 position)
        private
        pure
        returns (bytes memory)
    {
        if (position == 8) {
            return abi.encodeCall(AutolaunchCreateSequencerV1.deployFactory, (initcodes[8]));
        }
        bytes[4] memory payload;
        uint256 base = position < 4 ? 0 : 4;
        for (uint256 i; i < 4; ++i) {
            payload[i] = initcodes[base + i];
        }
        return base == 0
            ? abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseOne, (payload))
            : abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseTwo, (payload));
    }

    function _expectPhaseOneRejection(
        address sequencer,
        bytes[4] memory payload,
        string memory reason
    ) private {
        _expectGovernanceRejection(
            sequencer,
            abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseOne, (payload)),
            reason
        );
    }

    function _expectGovernanceRejection(address sequencer, bytes memory data, string memory reason)
        private
    {
        uint256 phaseBefore = uint256(AutolaunchCreateSequencerV1(sequencer).phase());
        uint64 nonceBefore = vm.getNonce(sequencer);
        vm.prank(governanceSafe);
        (bool ok, bytes memory ret) = sequencer.call(data);
        assertFalse(ok);
        assertEq(_revertReason(ret), reason);
        assertEq(uint256(AutolaunchCreateSequencerV1(sequencer).phase()), phaseBefore);
        assertEq(vm.getNonce(sequencer), nonceBefore);
    }

    function _children(DeployAutolaunchInfraScript.DeploymentAddresses memory a)
        private
        pure
        returns (address[9] memory children)
    {
        children = [
            a.subjectRegistry,
            a.stakingRouter,
            a.splitterDeployer,
            a.revenueShareFactory,
            a.revenueIngressFactory,
            a.paymentLinkFactory,
            a.strategyFactory,
            a.feeInfraDeployer,
            a.factory
        ];
    }

    // ---------------------------------------------------------------------
    // Governance Safe helpers (harness-only fixed external fixture)
    // ---------------------------------------------------------------------

    function _installPinnedSafeFixture() private {
        vm.etch(SAFE_SINGLETON, _safeSingletonRuntime());
        vm.etch(SAFE_PROXY_FACTORY, _safeProxyFactoryRuntime());
        vm.etch(SAFE_FALLBACK_HANDLER, _safeFallbackHandlerRuntime());

        string memory json = vm.readFile(SAFE_FIXTURE);
        assertEq(vm.parseJsonUint(json, ".chainId"), 8453);
        assertEq(SAFE_SINGLETON.codehash, vm.parseJsonBytes32(json, ".assets.safe.runtimeCodeHash"));
        assertEq(
            SAFE_PROXY_FACTORY.codehash,
            vm.parseJsonBytes32(json, ".assets.safeProxyFactory.runtimeCodeHash")
        );
        assertEq(
            SAFE_FALLBACK_HANDLER.codehash,
            vm.parseJsonBytes32(json, ".assets.compatibilityFallbackHandler.runtimeCodeHash")
        );
    }

    function _createGovernanceSafe() private returns (address created) {
        address[] memory owners = new address[](3);
        owners[0] = vm.addr(OWNER_ONE_KEY);
        owners[1] = vm.addr(OWNER_TWO_KEY);
        owners[2] = vm.addr(OWNER_THREE_KEY);
        bytes memory initializer = abi.encodeCall(
            ISafe.setup,
            (
                owners,
                SAFE_THRESHOLD,
                address(0),
                "",
                SAFE_FALLBACK_HANDLER,
                address(0),
                0,
                payable(address(0))
            )
        );
        created = ISafeProxyFactory(SAFE_PROXY_FACTORY)
            .createProxyWithNonce(SAFE_SINGLETON, initializer, 1);
        assertEq(ISafe(created).getThreshold(), SAFE_THRESHOLD);
        assertEq(ISafe(created).getOwners().length, 3);
    }

    function _safeWrappedCalldata(DeployAutolaunchInfraScript.PreparedCall memory prepared)
        private
        view
        returns (bytes memory)
    {
        bytes32 safeTxHash = ISafe(governanceSafe)
            .getTransactionHash(
                prepared.to,
                prepared.value,
                prepared.data,
                0,
                0,
                0,
                0,
                address(0),
                address(0),
                ISafe(governanceSafe).nonce()
            );
        return abi.encodeCall(
            ISafe.execTransaction,
            (
                prepared.to,
                prepared.value,
                prepared.data,
                0,
                0,
                0,
                0,
                address(0),
                payable(address(0)),
                _safeSignatures(safeTxHash)
            )
        );
    }

    function _safeSignatures(bytes32 digest) private pure returns (bytes memory signatures) {
        uint256[2] memory keys = [OWNER_ONE_KEY, OWNER_TWO_KEY];
        if (vm.addr(keys[0]) > vm.addr(keys[1])) {
            (keys[0], keys[1]) = (keys[1], keys[0]);
        }
        for (uint256 i; i < keys.length; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            signatures = bytes.concat(signatures, abi.encodePacked(r, s, v));
        }
    }

    function _safeExecute(DeployAutolaunchInfraScript.PreparedCall memory prepared) private {
        assertEq(prepared.sender, governanceSafe);
        bytes memory wrapped = _safeWrappedCalldata(prepared);
        (bool ok,) = governanceSafe.call(wrapped);
        assertTrue(ok);
    }

    function _measureGovernanceCall(
        string memory label,
        DeployAutolaunchInfraScript.PreparedCall memory prepared
    ) private {
        bytes memory wrapped = _safeWrappedCalldata(prepared);
        assertLe(wrapped.length, MAX_CALLDATA_BYTES);

        uint256 intrinsic = _standardIntrinsicGas(wrapped, false);
        // A real transaction hands the top-level frame exactly the limit minus intrinsic gas, so
        // every nested EIP-150 63/64 reservation inside the Safe is exercised for real here.
        uint256 available = MAX_TOTAL_GAS - intrinsic;
        uint256 startGas = gasleft();
        (bool ok,) = governanceSafe.call{gas: available}(wrapped);
        uint256 executionGas = startGas - gasleft();
        assertTrue(ok);

        uint256 total = _totalGas(wrapped, intrinsic, executionGas);
        assertLe(total, MAX_TOTAL_GAS);
        emit log_named_uint(string.concat(label, " calldata bytes"), wrapped.length);
        emit log_named_uint(string.concat(label, " intrinsic gas"), intrinsic);
        emit log_named_uint(string.concat(label, " total gas"), total);
    }

    // ---------------------------------------------------------------------
    // Gas and byte accounting
    // ---------------------------------------------------------------------

    function _tokens(bytes memory data) private pure returns (uint256 tokens) {
        uint256 zeros;
        for (uint256 i; i < data.length; ++i) {
            if (data[i] == 0) {
                ++zeros;
            }
        }
        tokens = zeros + 4 * (data.length - zeros);
    }

    function _standardIntrinsicGas(bytes memory data, bool creation)
        private
        pure
        returns (uint256 intrinsic)
    {
        intrinsic = 21_000 + 4 * _tokens(data);
        if (creation) {
            intrinsic += 32_000 + 2 * ((data.length + 31) / 32);
        }
    }

    /// @dev Total transaction gas under the EIP-7623 calldata floor that Base applies.
    function _totalGas(bytes memory data, uint256 intrinsic, uint256 executionGas)
        private
        pure
        returns (uint256)
    {
        uint256 floor = 21_000 + 10 * _tokens(data);
        uint256 standard = intrinsic + executionGas;
        return standard > floor ? standard : floor;
    }

    // ---------------------------------------------------------------------
    // Evidence helpers
    // ---------------------------------------------------------------------

    function _liveReadbacksHash(DeployAutolaunchInfraScript.DeploymentAddresses memory a)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                LIVE_TYPEHASH,
                a.subjectRegistry,
                a.factory,
                a.factory,
                a.factory,
                a.factory,
                a.subjectRegistry,
                a.subjectRegistry,
                a.stakingRouter,
                a.splitterDeployer,
                USDC,
                USDC,
                USDC,
                USDC,
                a.subjectRegistry,
                LIVE_STAKING,
                RegentLBPStrategyFactory(a.strategyFactory).authorizedCreators(a.factory),
                a.factory,
                governanceSafe,
                GUARDIAN
            )
        );
    }

    function _assertRuntimeMatchesCandidateArtifact(address deployed) private view {
        bytes memory candidate = vm.getDeployedCode(FACTORY_ARTIFACT);
        bytes memory runtime = deployed.code;
        assertEq(runtime.length, candidate.length);
        for (uint256 i; i < candidate.length; ++i) {
            if (candidate[i] == 0) {
                runtime[i] = 0;
            }
        }
        assertEq(keccak256(runtime), keccak256(candidate));
    }

    function _retiredSelectorProbes() private pure returns (bytes[14] memory probes) {
        probes[0] = abi.encodeWithSelector(
            bytes4(keccak256("deploy(bytes,bytes,bytes,bytes)")),
            bytes(""),
            bytes(""),
            bytes(""),
            bytes("")
        );
        probes[1] = abi.encodeWithSelector(
            bytes4(keccak256("prepareLaunch(bytes,bytes,bytes,bytes)")),
            bytes(""),
            bytes(""),
            bytes(""),
            bytes("")
        );
        probes[2] = abi.encodeWithSelector(
            bytes4(keccak256("deployLaunchFeeInfra(bytes32,bytes,bytes,bytes,bytes)")),
            bytes32(0),
            bytes(""),
            bytes(""),
            bytes(""),
            bytes("")
        );
        probes[3] = abi.encodeWithSelector(
            bytes4(keccak256("finalizeLaunch(bytes32,bytes,bytes,bytes,bytes)")),
            bytes32(0),
            bytes(""),
            bytes(""),
            bytes(""),
            bytes("")
        );
        probes[4] =
            abi.encodeWithSelector(bytes4(keccak256("stagedLaunchCore(bytes32)")), bytes32(0));
        probes[5] =
            abi.encodeWithSelector(bytes4(keccak256("stagedLaunchInfra(bytes32)")), bytes32(0));
        probes[6] =
            abi.encodeWithSelector(bytes4(keccak256("stagedLaunchRevenue(bytes32)")), bytes32(0));
        probes[7] = abi.encodeWithSelector(bytes4(keccak256("owner()")));
        probes[8] = abi.encodeWithSelector(bytes4(keccak256("pendingOwner()")));
        probes[9] =
            abi.encodeWithSelector(bytes4(keccak256("transferOwnership(address)")), ATTACKER);
        probes[10] = abi.encodeWithSelector(bytes4(keccak256("acceptOwnership()")));
        probes[11] = abi.encodeWithSelector(bytes4(keccak256("rescueNative(address)")), ATTACKER);
        probes[12] = abi.encodeWithSelector(bytes4(0x032876d3), TOKEN_FACTORY, uint256(1), ATTACKER);
        probes[13] = abi.encodeWithSelector(bytes4(keccak256("refundLaunchFee(address)")), ATTACKER);
    }

    function _flipLastByte(bytes memory data) private pure returns (bytes memory flipped) {
        flipped = bytes.concat(data);
        flipped[flipped.length - 1] = bytes1(uint8(flipped[flipped.length - 1]) ^ 0x01);
    }

    function _revertReason(bytes memory ret) private pure returns (string memory) {
        if (ret.length < 68) {
            return "";
        }
        return abi.decode(_slice(ret, 4), (string));
    }

    function _slice(bytes memory data, uint256 start) private pure returns (bytes memory out) {
        out = new bytes(data.length - start);
        for (uint256 i; i < out.length; ++i) {
            out[i] = data[start + i];
        }
    }

    function _safeSingletonRuntime() private pure returns (bytes memory) {
        return hex"6080604052600436106101d15760003560e01c8063affed0e0116100f7578063e19a9dd911610095578063f08a032311610064578063f08a03231461156b578063f698da25146115bc578063f8dc5dd9146115e7578063ffa1ad741461166257610226565b8063e19a9dd9146112bf578063e318b52b14611310578063e75235b8146113a1578063e86637db146113cc57610226565b8063cc2f8452116100d1578063cc2f84521461100c578063d4d9bdcd146110d9578063d8d11f7814611114578063e009cfde1461124e57610226565b8063affed0e014610d89578063b4faba0914610db4578063b63e800d14610e9c57610226565b80635624b25b1161016f5780636a7612021161013e5780636a761202146109895780637d83297414610b45578063934f3a1114610bb4578063a0e67e2b14610d1d57610226565b80635624b25b146107f05780635ae6bd37146108ae578063610b5925146108fd578063694e80c31461094e57610226565b80632f54bf6e116101ab5780632f54bf6e146104c85780633408e4701461052f578063468721a71461055a5780635229073f1461066f57610226565b80630d582f131461029357806312fb68e0146102ee5780632d9ad53d1461046157610226565b36610226573373ffffffffffffffffffffffffffffffffffffffff167f3d0ce9bfc3ed7d6862dbb28b2dea94561fe714a1b4d019aa8af39730d1ad7c3d346040518082815260200191505060405180910390a2005b34801561023257600080fd5b5060007f6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d560001b905080548061026757600080f35b36600080373360601b365260008060143601600080855af13d6000803e8061028e573d6000fd5b3d6000f35b34801561029f57600080fd5b506102ec600480360360408110156102b657600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291905050506116f2565b005b3480156102fa57600080fd5b5061045f6004803603608081101561031157600080fd5b81019080803590602001909291908035906020019064010000000081111561033857600080fd5b82018360208201111561034a57600080fd5b8035906020019184600183028401116401000000008311171561036c57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803590602001906401000000008111156103cf57600080fd5b8201836020820111156103e157600080fd5b8035906020019184600183028401116401000000008311171561040357600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f82011690508083019250505050505050919291929080359060200190929190505050611ad8565b005b34801561046d57600080fd5b506104b06004803603602081101561048457600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506123d6565b60405180821515815260200191505060405180910390f35b3480156104d457600080fd5b50610517600480360360208110156104eb57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506124a8565b60405180821515815260200191505060405180910390f35b34801561053b57600080fd5b5061054461257a565b6040518082815260200191505060405180910390f35b34801561056657600080fd5b506106576004803603608081101561057d57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190803590602001906401000000008111156105c457600080fd5b8201836020820111156105d657600080fd5b803590602001918460018302840111640100000000831117156105f857600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803560ff169060200190929190505050612587565b60405180821515815260200191505060405180910390f35b34801561067b57600080fd5b5061076c6004803603608081101561069257600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190803590602001906401000000008111156106d957600080fd5b8201836020820111156106eb57600080fd5b8035906020019184600183028401116401000000008311171561070d57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803560ff16906020019092919050505061278d565b60405180831515815260200180602001828103825283818151815260200191508051906020019080838360005b838110156107b4578082015181840152602081019050610799565b50505050905090810190601f1680156107e15780820380516001836020036101000a031916815260200191505b50935050505060405180910390f35b3480156107fc57600080fd5b506108336004803603604081101561081357600080fd5b8101908080359060200190929190803590602001909291905050506127c3565b6040518080602001828103825283818151815260200191508051906020019080838360005b83811015610873578082015181840152602081019050610858565b50505050905090810190601f1680156108a05780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b3480156108ba57600080fd5b506108e7600480360360208110156108d157600080fd5b810190808035906020019092919050505061284a565b6040518082815260200191505060405180910390f35b34801561090957600080fd5b5061094c6004803603602081101561092057600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050612862565b005b34801561095a57600080fd5b506109876004803603602081101561097157600080fd5b8101908080359060200190929190505050612bea565b005b610b2d60048036036101408110156109a057600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190803590602001906401000000008111156109e757600080fd5b8201836020820111156109f957600080fd5b80359060200191846001830284011164010000000083111715610a1b57600080fd5b9091929391929390803560ff169060200190929190803590602001909291908035906020019092919080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190640100000000811115610aa757600080fd5b820183602082011115610ab957600080fd5b80359060200191846001830284011164010000000083111715610adb57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050612d24565b60405180821515815260200191505060405180910390f35b348015610b5157600080fd5b50610b9e60048036036040811015610b6857600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050613253565b6040518082815260200191505060405180910390f35b348015610bc057600080fd5b50610d1b60048036036060811015610bd757600080fd5b810190808035906020019092919080359060200190640100000000811115610bfe57600080fd5b820183602082011115610c1057600080fd5b80359060200191846001830284011164010000000083111715610c3257600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f82011690508083019250505050505050919291929080359060200190640100000000811115610c9557600080fd5b820183602082011115610ca757600080fd5b80359060200191846001830284011164010000000083111715610cc957600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050613278565b005b348015610d2957600080fd5b50610d32613307565b6040518080602001828103825283818151815260200191508051906020019060200280838360005b83811015610d75578082015181840152602081019050610d5a565b505050509050019250505060405180910390f35b348015610d9557600080fd5b50610d9e6134b0565b6040518082815260200191505060405180910390f35b348015610dc057600080fd5b50610e9a60048036036040811015610dd757600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190640100000000811115610e1457600080fd5b820183602082011115610e2657600080fd5b80359060200191846001830284011164010000000083111715610e4857600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f8201169050808301925050505050505091929192905050506134b6565b005b348015610ea857600080fd5b5061100a6004803603610100811015610ec057600080fd5b8101908080359060200190640100000000811115610edd57600080fd5b820183602082011115610eef57600080fd5b80359060200191846020830284011164010000000083111715610f1157600080fd5b909192939192939080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190640100000000811115610f5c57600080fd5b820183602082011115610f6e57600080fd5b80359060200191846001830284011164010000000083111715610f9057600080fd5b9091929391929390803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506134d8565b005b34801561101857600080fd5b506110656004803603604081101561102f57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050613696565b60405180806020018373ffffffffffffffffffffffffffffffffffffffff168152602001828103825284818151815260200191508051906020019060200280838360005b838110156110c45780820151818401526020810190506110a9565b50505050905001935050505060405180910390f35b3480156110e557600080fd5b50611112600480360360208110156110fc57600080fd5b81019080803590602001909291905050506139f9565b005b34801561112057600080fd5b50611238600480360361014081101561113857600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561117f57600080fd5b82018360208201111561119157600080fd5b803590602001918460018302840111640100000000831117156111b357600080fd5b9091929391929390803560ff169060200190929190803590602001909291908035906020019092919080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050613b98565b6040518082815260200191505060405180910390f35b34801561125a57600080fd5b506112bd6004803603604081101561127157600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050613bc5565b005b3480156112cb57600080fd5b5061130e600480360360208110156112e257600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050613f4c565b005b34801561131c57600080fd5b5061139f6004803603606081101561133357600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050614138565b005b3480156113ad57600080fd5b506113b6614796565b6040518082815260200191505060405180910390f35b3480156113d857600080fd5b506114f060048036036101408110156113f057600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561143757600080fd5b82018360208201111561144957600080fd5b8035906020019184600183028401116401000000008311171561146b57600080fd5b9091929391929390803560ff169060200190929190803590602001909291908035906020019092919080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291905050506147a0565b6040518080602001828103825283818151815260200191508051906020019080838360005b83811015611530578082015181840152602081019050611515565b50505050905090810190601f16801561155d5780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b34801561157757600080fd5b506115ba6004803603602081101561158e57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050614948565b005b3480156115c857600080fd5b506115d161499f565b6040518082815260200191505060405180910390f35b3480156115f357600080fd5b506116606004803603606081101561160a57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050614a1d565b005b34801561166e57600080fd5b50611677614e46565b6040518080602001828103825283818151815260200191508051906020019080838360005b838110156116b757808201518184015260208101905061169c565b50505050905090810190601f1680156116e45780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b6116fa614e7f565b600073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff16141580156117645750600173ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614155b801561179c57503073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614155b61180e576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303300000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff16600260008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff161461190f576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303400000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60026000600173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff16600260008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055508160026000600173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506003600081548092919060010191905055508173ffffffffffffffffffffffffffffffffffffffff167f9465fa0c962cc76958e6373a993326400c1c94f8be2fe3a952adfa7f60b2ea2660405160405180910390a28060045414611ad457611ad381612bea565b5b5050565b611aec604182614f2290919063ffffffff16565b82511015611b62576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330323000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b6000808060008060005b868110156123ca57611b7e8882614f5c565b80945081955082965050505060008460ff1614156120035789898051906020012014611c12576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330323700000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b8260001c9450611c2c604188614f2290919063ffffffff16565b8260001c1015611ca4576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330323100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b8751611cbd60208460001c614f8b90919063ffffffff16565b1115611d31576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330323200000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60006020838a01015190508851611d6782611d5960208760001c614f8b90919063ffffffff16565b614f8b90919063ffffffff16565b1115611ddb576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330323300000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60606020848b010190506320c13b0b60e01b7bffffffffffffffffffffffffffffffffffffffffffffffffffffffff19168773ffffffffffffffffffffffffffffffffffffffff166320c13b0b8d846040518363ffffffff1660e01b8152600401808060200180602001838103835285818151815260200191508051906020019080838360005b83811015611e7d578082015181840152602081019050611e62565b50505050905090810190601f168015611eaa5780820380516001836020036101000a031916815260200191505b50838103825284818151815260200191508051906020019080838360005b83811015611ee3578082015181840152602081019050611ec8565b50505050905090810190601f168015611f105780820380516001836020036101000a031916815260200191505b5094505050505060206040518083038186803b158015611f2f57600080fd5b505afa158015611f43573d6000803e3d6000fd5b505050506040513d6020811015611f5957600080fd5b81019080805190602001909291905050507bffffffffffffffffffffffffffffffffffffffffffffffffffffffff191614611ffc576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330323400000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b5050612248565b60018460ff161415612117578260001c94508473ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614806120a057506000600860008773ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008c81526020019081526020016000205414155b612112576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330323500000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b612247565b601e8460ff1611156121df5760018a60405160200180807f19457468657265756d205369676e6564204d6573736167653a0a333200000000815250601c018281526020019150506040516020818303038152906040528051906020012060048603858560405160008152602001604052604051808581526020018460ff1681526020018381526020018281526020019450505050506020604051602081039080840390855afa1580156121ce573d6000803e3d6000fd5b505050602060405103519450612246565b60018a85858560405160008152602001604052604051808581526020018460ff1681526020018381526020018281526020019450505050506020604051602081039080840390855afa158015612239573d6000803e3d6000fd5b5050506020604051035194505b5b5b8573ffffffffffffffffffffffffffffffffffffffff168573ffffffffffffffffffffffffffffffffffffffff1611801561230f5750600073ffffffffffffffffffffffffffffffffffffffff16600260008773ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614155b80156123485750600173ffffffffffffffffffffffffffffffffffffffff168573ffffffffffffffffffffffffffffffffffffffff1614155b6123ba576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330323600000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b8495508080600101915050611b6c565b50505050505050505050565b60008173ffffffffffffffffffffffffffffffffffffffff16600173ffffffffffffffffffffffffffffffffffffffff16141580156124a15750600073ffffffffffffffffffffffffffffffffffffffff16600160008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614155b9050919050565b6000600173ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff16141580156125735750600073ffffffffffffffffffffffffffffffffffffffff16600260008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614155b9050919050565b6000804690508091505090565b6000600173ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16141580156126525750600073ffffffffffffffffffffffffffffffffffffffff16600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614155b6126c4576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475331303400000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b6126f1858585857fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff614faa565b90508015612741573373ffffffffffffffffffffffffffffffffffffffff167f6895c13664aa4f67288b25d7a21d7aaa34916e355fb9b6fae0a139a9085becb860405160405180910390a2612785565b3373ffffffffffffffffffffffffffffffffffffffff167facd2c8702804128fdb0db2bb49f6d127dd0181c13fd45dbfe16de0930e2bd37560405160405180910390a25b949350505050565b6000606061279d86868686612587565b915060405160203d0181016040523d81523d6000602083013e8091505094509492505050565b606060006020830267ffffffffffffffff811180156127e157600080fd5b506040519080825280601f01601f1916602001820160405280156128145781602001600182028036833780820191505090505b50905060005b8381101561283f5780850154806020830260208501015250808060010191505061281a565b508091505092915050565b60076020528060005260406000206000915090505481565b61286a614e7f565b600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff16141580156128d45750600173ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614155b612946576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475331303100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff16600160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614612a47576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475331303200000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60016000600173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff16600160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055508060016000600173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055508073ffffffffffffffffffffffffffffffffffffffff167fecdf3a3effea5783a3c4c2140e677577666428d44ed9d474a0b3a4c9943f844060405160405180910390a250565b612bf2614e7f565b600354811115612c6a576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b6001811015612ce1576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303200000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b806004819055507f610f7ff2b304ae8903c3de74c60c6ab1f7d6226b3f52c5161905bb5ad4039c936004546040518082815260200191505060405180910390a150565b6000806000612d3e8e8e8e8e8e8e8e8e8e8e6005546147a0565b905060056000815480929190600101919050555080805190602001209150612d67828286613278565b506000612d72614ff6565b9050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614612f58578073ffffffffffffffffffffffffffffffffffffffff166375f0bb528f8f8f8f8f8f8f8f8f8f8f336040518d63ffffffff1660e01b8152600401808d73ffffffffffffffffffffffffffffffffffffffff1681526020018c8152602001806020018a6001811115612e1557fe5b81526020018981526020018881526020018781526020018673ffffffffffffffffffffffffffffffffffffffff1681526020018573ffffffffffffffffffffffffffffffffffffffff168152602001806020018473ffffffffffffffffffffffffffffffffffffffff16815260200183810383528d8d82818152602001925080828437600081840152601f19601f820116905080830192505050838103825285818151815260200191508051906020019080838360005b83811015612ee7578082015181840152602081019050612ecc565b50505050905090810190601f168015612f145780820380516001836020036101000a031916815260200191505b509e505050505050505050505050505050600060405180830381600087803b158015612f3f57600080fd5b505af1158015612f53573d6000803e3d6000fd5b505050505b6101f4612f7f6109c48b01603f60408d0281612f7057fe5b0461502790919063ffffffff16565b015a1015612ff5576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330313000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60005a905061305e8f8f8f8f8080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050508e60008d14613053578e613059565b6109c45a035b614faa565b93506130735a8261504190919063ffffffff16565b90508380613082575060008a14155b8061308e575060008814155b613100576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330313300000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60008089111561311a57613117828b8b8b8b615061565b90505b841561315d57837f442e715f626346e8c54381002da614f62bee8d27386535b2521ec8540898556e826040518082815260200191505060405180910390a2613196565b837f23428b18acfb3ea64b08dc0c1d296ea9c09702c09083ca5272e64d115b687d23826040518082815260200191505060405180910390a25b5050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614613242578073ffffffffffffffffffffffffffffffffffffffff16639327136883856040518363ffffffff1660e01b815260040180838152602001821515815260200192505050600060405180830381600087803b15801561322957600080fd5b505af115801561323d573d6000803e3d6000fd5b505050505b50509b9a5050505050505050505050565b6008602052816000526040600020602052806000526040600020600091509150505481565b60006004549050600081116132f5576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330303100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b61330184848484611ad8565b50505050565b6060600060035467ffffffffffffffff8111801561332457600080fd5b506040519080825280602002602001820160405280156133535781602001602082028036833780820191505090505b50905060008060026000600173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1690505b600173ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff16146134a757808383815181106133fe57fe5b602002602001019073ffffffffffffffffffffffffffffffffffffffff16908173ffffffffffffffffffffffffffffffffffffffff1681525050600260008273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff16905081806001019250506133bd565b82935050505090565b60055481565b600080825160208401855af4806000523d6020523d600060403e60403d016000fd5b6135238a8a80806020026020016040519081016040528093929190818152602001838360200280828437600081840152601f19601f8201169050808301925050505050505089615267565b600073ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff16146135615761356084615767565b5b6135af8787878080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f82011690508083019250505050505050615838565b60008211156135c9576135c782600060018685615061565b505b3373ffffffffffffffffffffffffffffffffffffffff167f141df868a6331af528e38c83b7aa03edc19be66e37ae67f9285bf4f8e3c6a1a88b8b8b8b8960405180806020018581526020018473ffffffffffffffffffffffffffffffffffffffff1681526020018373ffffffffffffffffffffffffffffffffffffffff1681526020018281038252878782818152602001925060200280828437600081840152601f19601f820116905080830192505050965050505050505060405180910390a250505050505050505050565b60606000600173ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff1614806136da57506136d9846123d6565b5b61374c576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475331303500000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600083116137c2576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475331303600000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b8267ffffffffffffffff811180156137d957600080fd5b506040519080825280602002602001820160405280156138085781602001602082028036833780820191505090505b5091506000600160008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1691505b600073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff16141580156138da5750600173ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614155b80156138e557508381105b156139a057818382815181106138f757fe5b602002602001019073ffffffffffffffffffffffffffffffffffffffff16908173ffffffffffffffffffffffffffffffffffffffff1681525050600160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1691508080600101915050613870565b600173ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff16146139ee578260018203815181106139e357fe5b602002602001015191505b808352509250929050565b600073ffffffffffffffffffffffffffffffffffffffff16600260003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff161415613afb576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330333000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b6001600860003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000206000838152602001908152602001600020819055503373ffffffffffffffffffffffffffffffffffffffff16817ff2a0eb156472d1440255b0d7c1e19cc07115d1051fe605b0dce69acfec884d9c60405160405180910390a350565b6000613bad8c8c8c8c8c8c8c8c8c8c8c6147a0565b8051906020012090509b9a5050505050505050505050565b613bcd614e7f565b600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614158015613c375750600173ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614155b613ca9576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475331303100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b8073ffffffffffffffffffffffffffffffffffffffff16600160008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614613da9576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475331303300000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600160008273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff16600160008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506000600160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055508073ffffffffffffffffffffffffffffffffffffffff167faab4fa2b463f581b2b32cb3b7e3b704b9ce37cc209b5fb4d77e593ace405427660405160405180910390a25050565b613f54614e7f565b600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff16146140c6578073ffffffffffffffffffffffffffffffffffffffff166301ffc9a77fe6d7a83a000000000000000000000000000000000000000000000000000000006040518263ffffffff1660e01b815260040180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060206040518083038186803b15801561401857600080fd5b505afa15801561402c573d6000803e3d6000fd5b505050506040513d602081101561404257600080fd5b81019080805190602001909291905050506140c5576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475333303000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b5b60007f4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c860001b90508181558173ffffffffffffffffffffffffffffffffffffffff167f1151116914515bc0891ff9047a6cb32cf902546f83066499bcf8ba33d2353fa260405160405180910390a25050565b614140614e7f565b600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff16141580156141aa5750600173ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614155b80156141e257503073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614155b614254576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303300000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff16600260008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614614355576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303400000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff16141580156143bf5750600173ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614155b614431576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303300000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b8173ffffffffffffffffffffffffffffffffffffffff16600260008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614614531576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303500000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600260008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff16600260008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff16021790555080600260008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506000600260008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055508173ffffffffffffffffffffffffffffffffffffffff167ff8d49fc529812e9a7c5c50e69c20f0dccc0db8fa95c98bc58cc9a4f1c1299eaf60405160405180910390a28073ffffffffffffffffffffffffffffffffffffffff167f9465fa0c962cc76958e6373a993326400c1c94f8be2fe3a952adfa7f60b2ea2660405160405180910390a2505050565b6000600454905090565b606060007fbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d860001b8d8d8d8d60405180838380828437808301925050509250505060405180910390208c8c8c8c8c8c8c604051602001808c81526020018b73ffffffffffffffffffffffffffffffffffffffff1681526020018a815260200189815260200188600181111561483157fe5b81526020018781526020018681526020018581526020018473ffffffffffffffffffffffffffffffffffffffff1681526020018373ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019b505050505050505050505050604051602081830303815290604052805190602001209050601960f81b600160f81b6148bd61499f565b8360405160200180857effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff19168152600101847effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff191681526001018381526020018281526020019450505050506040516020818303038152906040529150509b9a5050505050505050505050565b614950614e7f565b61495981615767565b8073ffffffffffffffffffffffffffffffffffffffff167f5ac6c46c93c8d0e53714ba3b53db3e7c046da994313d7ed0d192028bc7c228b060405160405180910390a250565b60007f47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a7946921860001b6149cd61257a565b30604051602001808481526020018381526020018273ffffffffffffffffffffffffffffffffffffffff168152602001935050505060405160208183030381529060405280519060200120905090565b614a25614e7f565b806001600354031015614aa0576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614158015614b0a5750600173ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614155b614b7c576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303300000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b8173ffffffffffffffffffffffffffffffffffffffff16600260008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614614c7c576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303500000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600260008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff16600260008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506000600260008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff160217905550600360008154809291906001900391905055508173ffffffffffffffffffffffffffffffffffffffff167ff8d49fc529812e9a7c5c50e69c20f0dccc0db8fa95c98bc58cc9a4f1c1299eaf60405160405180910390a28060045414614e4157614e4081612bea565b5b505050565b6040518060400160405280600581526020017f312e342e3100000000000000000000000000000000000000000000000000000081525081565b3073ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614614f20576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330333100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b565b600080831415614f355760009050614f56565b6000828402905082848281614f4657fe5b0414614f5157600080fd5b809150505b92915050565b60008060008360410260208101860151925060408101860151915060ff60418201870151169350509250925092565b600080828401905083811015614fa057600080fd5b8091505092915050565b6000600180811115614fb857fe5b836001811115614fc457fe5b1415614fdd576000808551602087018986f49050614fed565b600080855160208701888a87f190505b95945050505050565b6000807f4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c860001b9050805491505090565b6000818310156150375781615039565b825b905092915050565b60008282111561505057600080fd5b600082840390508091505092915050565b600080600073ffffffffffffffffffffffffffffffffffffffff168373ffffffffffffffffffffffffffffffffffffffff161461509e57826150a0565b325b9050600073ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff1614156151b85761510a3a86106150e7573a6150e9565b855b6150fc888a614f8b90919063ffffffff16565b614f2290919063ffffffff16565b91508073ffffffffffffffffffffffffffffffffffffffff166108fc839081150290604051600060405180830381858888f193505050506151b3576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330313100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b61525d565b6151dd856151cf888a614f8b90919063ffffffff16565b614f2290919063ffffffff16565b91506151ea848284615b0e565b61525c576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330313200000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b5b5095945050505050565b6000600454146152df576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b8151811115615356576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303100000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60018110156153cd576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303200000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60006001905060005b83518110156156d35760008482815181106153ed57fe5b60200260200101519050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff16141580156154615750600173ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614155b801561549957503073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614155b80156154d157508073ffffffffffffffffffffffffffffffffffffffff168373ffffffffffffffffffffffffffffffffffffffff1614155b615543576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303300000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff16600260008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614615644576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475332303400000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b80600260008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055508092505080806001019150506153d6565b506001600260008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff160217905550825160038190555081600481905550505050565b3073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff161415615809576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475334303000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b60007f6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d560001b90508181555050565b600073ffffffffffffffffffffffffffffffffffffffff1660016000600173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff161461593a576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475331303000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b6001806000600173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff160217905550600073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614615b0a576159f682615bd2565b615a68576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330303200000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b615a978260008360017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff614faa565b615b09576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260058152602001807f475330303000000000000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b5b5050565b60008063a9059cbb8484604051602401808373ffffffffffffffffffffffffffffffffffffffff168152602001828152602001925050506040516020818303038152906040529060e01b6020820180517bffffffffffffffffffffffffffffffffffffffffffffffffffffffff83818316178352505050509050602060008251602084016000896127105a03f13d60008114615bb55760208114615bbd5760009350615bc8565b819350615bc8565b600051158215171593505b5050509392505050565b600080823b90506000811191505091905056fea264697066735822122057398fa72884cf9a6cb78aab2fb58a6b927f0e9d97d75b015daaee0959a153bf64736f6c63430007060033";
    }

    function _safeProxyFactoryRuntime() private pure returns (bytes memory) {
        return hex"608060405234801561001057600080fd5b50600436106100575760003560e01c80631688f0b91461005c5780633408e4701461016b57806353e5d93514610189578063d18af54d1461020c578063ec9e80bb1461033b575b600080fd5b61013f6004803603606081101561007257600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001906401000000008111156100af57600080fd5b8201836020820111156100c157600080fd5b803590602001918460018302840111640100000000831117156100e357600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f8201169050808301925050505050505091929192908035906020019092919050505061044a565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6101736104fe565b6040518082815260200191505060405180910390f35b61019161050b565b6040518080602001828103825283818151815260200191508051906020019080838360005b838110156101d15780820151818401526020810190506101b6565b50505050905090810190601f1680156101fe5780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b61030f6004803603608081101561022257600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561025f57600080fd5b82018360208201111561027157600080fd5b8035906020019184600183028401116401000000008311171561029357600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f82011690508083019250505050505050919291929080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610536565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b61041e6004803603606081101561035157600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561038e57600080fd5b8201836020820111156103a057600080fd5b803590602001918460018302840111640100000000831117156103c257600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290803590602001909291905050506106e5565b604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b60008083805190602001208360405160200180838152602001828152602001925050506040516020818303038152906040528051906020012090506104908585836107a8565b91508173ffffffffffffffffffffffffffffffffffffffff167f4f51faf6c4561ff95f067657e43439f0f856d97c04d9ec9070a6199ad418e23586604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390a2509392505050565b6000804690508091505090565b60606040518060200161051d906109c5565b6020820181038252601f19601f82011660405250905090565b6000808383604051602001808381526020018273ffffffffffffffffffffffffffffffffffffffff1660601b8152601401925050506040516020818303038152906040528051906020012060001c905061059186868361044a565b9150600073ffffffffffffffffffffffffffffffffffffffff168373ffffffffffffffffffffffffffffffffffffffff16146106dc578273ffffffffffffffffffffffffffffffffffffffff16631e52b518838888886040518563ffffffff1660e01b8152600401808573ffffffffffffffffffffffffffffffffffffffff1681526020018473ffffffffffffffffffffffffffffffffffffffff16815260200180602001838152602001828103825284818151815260200191508051906020019080838360005b83811015610674578082015181840152602081019050610659565b50505050905090810190601f1680156106a15780820380516001836020036101000a031916815260200191505b5095505050505050600060405180830381600087803b1580156106c357600080fd5b505af11580156106d7573d6000803e3d6000fd5b505050505b50949350505050565b6000808380519060200120836106f96104fe565b60405160200180848152602001838152602001828152602001935050505060405160208183030381529060405280519060200120905061073a8585836107a8565b91508173ffffffffffffffffffffffffffffffffffffffff167f4f51faf6c4561ff95f067657e43439f0f856d97c04d9ec9070a6199ad418e23586604051808273ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390a2509392505050565b60006107b3846109b2565b610825576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252601f8152602001807f53696e676c65746f6e20636f6e7472616374206e6f74206465706c6f7965640081525060200191505060405180910390fd5b600060405180602001610837906109c5565b6020820181038252601f19601f820116604052508573ffffffffffffffffffffffffffffffffffffffff166040516020018083805190602001908083835b602083106108985780518252602082019150602081019050602083039250610875565b6001836020036101000a038019825116818451168082178552505050505050905001828152602001925050506040516020818303038152906040529050828151826020016000f59150600073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff161415610984576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260138152602001807f437265617465322063616c6c206661696c65640000000000000000000000000081525060200191505060405180910390fd5b6000845111156109aa5760008060008651602088016000875af114156109a957600080fd5b5b509392505050565b600080823b905060008111915050919050565b6101e6806109d38339019056fe608060405234801561001057600080fd5b506040516101e63803806101e68339818101604052602081101561003357600080fd5b8101908080519060200190929190505050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff1614156100ca576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260228152602001806101c46022913960400191505060405180910390fd5b806000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505060ab806101196000396000f3fe608060405273ffffffffffffffffffffffffffffffffffffffff600054167fa619486e0000000000000000000000000000000000000000000000000000000060003514156050578060005260206000f35b3660008037600080366000845af43d6000803e60008114156070573d6000fd5b3d6000f3fea264697066735822122003d1488ee65e08fa41e58e888a9865554c535f2c77126a82cb4c0f917f31441364736f6c63430007060033496e76616c69642073696e676c65746f6e20616464726573732070726f7669646564a26469706673582212200fd975ca8e62d9bf08aa3d09c74b9bdc9d7acba7621835be4187989ddd0e54b164736f6c63430007060033";
    }

    function _safeFallbackHandlerRuntime() private pure returns (bytes memory) {
        return hex"608060405234801561001057600080fd5b50600436106100b35760003560e01c8063230316401161007157806323031640146106535780636ac24784146107a7578063b2494df314610896578063bc197c81146108f5578063bd61951d14610a8b578063f23a6e6114610b9d576100b3565b806223de29146100b857806301ffc9a7146101f05780630a1028c414610253578063150b7a02146103225780631626ba7e1461041857806320c13b0b146104ce575b600080fd5b6101ee600480360360c08110156100ce57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561015557600080fd5b82018360208201111561016757600080fd5b8035906020019184600183028401116401000000008311171561018957600080fd5b9091929391929390803590602001906401000000008111156101aa57600080fd5b8201836020820111156101bc57600080fd5b803590602001918460018302840111640100000000831117156101de57600080fd5b9091929391929390505050610c9d565b005b61023b6004803603602081101561020657600080fd5b8101908080357bffffffffffffffffffffffffffffffffffffffffffffffffffffffff19169060200190929190505050610ca7565b60405180821515815260200191505060405180910390f35b61030c6004803603602081101561026957600080fd5b810190808035906020019064010000000081111561028657600080fd5b82018360208201111561029857600080fd5b803590602001918460018302840111640100000000831117156102ba57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050610de1565b6040518082815260200191505060405180910390f35b6103e36004803603608081101561033857600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019064010000000081111561039f57600080fd5b8201836020820111156103b157600080fd5b803590602001918460018302840111640100000000831117156103d357600080fd5b9091929391929390505050610df4565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b6104996004803603604081101561042e57600080fd5b81019080803590602001909291908035906020019064010000000081111561045557600080fd5b82018360208201111561046757600080fd5b8035906020019184600183028401116401000000008311171561048957600080fd5b9091929391929390505050610e09565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b61061e600480360360408110156104e457600080fd5b810190808035906020019064010000000081111561050157600080fd5b82018360208201111561051357600080fd5b8035906020019184600183028401116401000000008311171561053557600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f8201169050808301925050505050505091929192908035906020019064010000000081111561059857600080fd5b8201836020820111156105aa57600080fd5b803590602001918460018302840111640100000000831117156105cc57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050610fc1565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b61072c6004803603604081101561066957600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001906401000000008111156106a657600080fd5b8201836020820111156106b857600080fd5b803590602001918460018302840111640100000000831117156106da57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050611249565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561076c578082015181840152602081019050610751565b50505050905090810190601f1680156107995780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b610880600480360360408110156107bd57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001906401000000008111156107fa57600080fd5b82018360208201111561080c57600080fd5b8035906020019184600183028401116401000000008311171561082e57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f8201169050808301925050505050505091929192905050506113b5565b6040518082815260200191505060405180910390f35b61089e6113d0565b6040518080602001828103825283818151815260200191508051906020019060200280838360005b838110156108e15780820151818401526020810190506108c6565b505050509050019250505060405180910390f35b610a56600480360360a081101561090b57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019064010000000081111561096857600080fd5b82018360208201111561097a57600080fd5b8035906020019184602083028401116401000000008311171561099c57600080fd5b9091929391929390803590602001906401000000008111156109bd57600080fd5b8201836020820111156109cf57600080fd5b803590602001918460208302840111640100000000831117156109f157600080fd5b909192939192939080359060200190640100000000811115610a1257600080fd5b820183602082011115610a2457600080fd5b80359060200191846001830284011164010000000083111715610a4657600080fd5b9091929391929390505050611537565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b610b2260048036036040811015610aa157600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190640100000000811115610ade57600080fd5b820183602082011115610af057600080fd5b80359060200191846001830284011164010000000083111715610b1257600080fd5b909192939192939050505061154f565b6040518080602001828103825283818151815260200191508051906020019080838360005b83811015610b62578082015181840152602081019050610b47565b50505050905090810190601f168015610b8f5780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b610c68600480360360a0811015610bb357600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291908035906020019092919080359060200190640100000000811115610c2457600080fd5b820183602082011115610c3657600080fd5b80359060200191846001830284011164010000000083111715610c5857600080fd5b90919293919293905050506115b9565b60405180827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260200191505060405180910390f35b5050505050505050565b60007f4e2312e0000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff19161480610d7257507f150b7a02000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b80610dda57507f01ffc9a7000000000000000000000000000000000000000000000000000000007bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916827bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916145b9050919050565b6000610ded33836113b5565b9050919050565b600063150b7a0260e01b905095945050505050565b60008033905060008173ffffffffffffffffffffffffffffffffffffffff166320c13b0b876040516020018082815260200191505060405160208183030381529060405287876040518463ffffffff1660e01b8152600401808060200180602001838103835286818151815260200191508051906020019080838360005b83811015610ea2578082015181840152602081019050610e87565b50505050905090810190601f168015610ecf5780820380516001836020036101000a031916815260200191505b508381038252858582818152602001925080828437600081840152601f19601f8201169050808301925050509550505050505060206040518083038186803b158015610f1a57600080fd5b505afa158015610f2e573d6000803e3d6000fd5b505050506040513d6020811015610f4457600080fd5b810190808051906020019092919050505090506320c13b0b60e01b7bffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916817bffffffffffffffffffffffffffffffffffffffffffffffffffffffff191614610fad57600060e01b610fb6565b631626ba7e60e01b5b925050509392505050565b6000803390506000610fd38286611249565b90506000818051906020012090506000855114156110f25760008373ffffffffffffffffffffffffffffffffffffffff16635ae6bd37836040518263ffffffff1660e01b81526004018082815260200191505060206040518083038186803b15801561103e57600080fd5b505afa158015611052573d6000803e3d6000fd5b505050506040513d602081101561106857600080fd5b810190808051906020019092919050505014156110ed576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260118152602001807f48617368206e6f7420617070726f76656400000000000000000000000000000081525060200191505060405180910390fd5b611236565b8273ffffffffffffffffffffffffffffffffffffffff1663934f3a118284886040518463ffffffff1660e01b8152600401808481526020018060200180602001838103835285818151815260200191508051906020019080838360005b8381101561116a57808201518184015260208101905061114f565b50505050905090810190601f1680156111975780820380516001836020036101000a031916815260200191505b50838103825284818151815260200191508051906020019080838360005b838110156111d05780820151818401526020810190506111b5565b50505050905090810190601f1680156111fd5780820380516001836020036101000a031916815260200191505b509550505050505060006040518083038186803b15801561121d57600080fd5b505afa158015611231573d6000803e3d6000fd5b505050505b6320c13b0b60e01b935050505092915050565b606060007f60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca60001b83805190602001206040516020018083815260200182815260200192505050604051602081830303815290604052805190602001209050601960f81b600160f81b8573ffffffffffffffffffffffffffffffffffffffff1663f698da256040518163ffffffff1660e01b815260040160206040518083038186803b1580156112f857600080fd5b505afa15801561130c573d6000803e3d6000fd5b505050506040513d602081101561132257600080fd5b81019080805190602001909291905050508360405160200180857effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff19168152600101847effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1916815260010183815260200182815260200194505050505060405160208183030381529060405291505092915050565b60006113c18383611249565b80519060200120905092915050565b6060600033905060008173ffffffffffffffffffffffffffffffffffffffff1663cc2f84526001600a6040518363ffffffff1660e01b8152600401808373ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019250505060006040518083038186803b15801561144a57600080fd5b505afa15801561145e573d6000803e3d6000fd5b505050506040513d6000823e3d601f19601f82011682018060405250604081101561148857600080fd5b81019080805160405193929190846401000000008211156114a857600080fd5b838201915060208201858111156114be57600080fd5b82518660208202830111640100000000821117156114db57600080fd5b8083526020830192505050908051906020019060200280838360005b838110156115125780820151818401526020810190506114f7565b5050505090500160405260200180519060200190929190505050509050809250505090565b600063bc197c8160e01b905098975050505050505050565b60606040517fb4faba09000000000000000000000000000000000000000000000000000000008152600436036004808301376020600036836000335af15060203d036040519250808301604052806020843e6000516115b057825160208401fd5b50509392505050565b600063f23a6e6160e01b9050969550505050505056fea26469706673582212201b4a724e94687b6683f72064694993023a1b3dbf13a3418c0926ebb253c030fe64736f6c63430007060033";
    }
}
