// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {
    AutolaunchInfraDeployerV1,
    DeployAutolaunchInfraScript
} from "script/DeployAutolaunchInfra.s.sol";
import {AutolaunchFactoryV1} from "src/autolaunch/AutolaunchFactoryV1.sol";
import {IAutolaunchFactoryV1} from "src/autolaunch/interfaces/IAutolaunchFactoryV1.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";

contract LiveStakingBindingMock {
    address public constant usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
}

contract DeployAutolaunchInfraScriptTest is Test {
    address internal constant D = 0x000000000000000000000000000000000000D00d;
    address internal constant TOKEN_FACTORY = 0x1111111111111111111111111111111111111111;
    address internal constant OPERATIONS_SAFE = 0x2222222222222222222222222222222222222222;
    address internal constant GOVERNANCE = 0x3333333333333333333333333333333333333333;
    address internal constant GUARDIAN = 0x4444444444444444444444444444444444444444;
    address internal constant ATTACKER = 0x5555555555555555555555555555555555555555;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address internal constant LIVE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;
    uint64 internal constant N = 7;

    bytes32 internal constant CONSTRUCTOR_TYPEHASH =
        0x6e1e8f7b1a5de15fa2aadd33503de85b47cdbc151c53c83df2df74862a6e0fba;
    bytes32 internal constant FIXED_TYPEHASH =
        0x32ba980f8a2e1edef01731a3c84113908d409e004d68bd4677bf33faad970eba;
    bytes32 internal constant LIVE_TYPEHASH =
        0xa95774e92247e20d445e762ad35b922069db60bcc3a13a7174ed7bfa39396546;
    bytes32 internal constant BINDING_TYPEHASH =
        0xece30424d68a49316340bac7da891d7930b005201ccaea7ba1bcf2ef915ea7e6;
    bytes32 internal constant ABI_SHA256 =
        0xfc54a41c85077366fe7df844dbbd539bf992f1a6c30593cee3f0b0d5b31cf1ba;

    DeployAutolaunchInfraScript internal script;

    function setUp() external {
        vm.chainId(8453);
        script = new DeployAutolaunchInfraScript();
        AutolaunchInfraDeployerV1 template = new AutolaunchInfraDeployerV1(GOVERNANCE);
        vm.etch(D, address(template).code);
        vm.setNonce(D, N);
        vm.etch(TOKEN_FACTORY, hex"00");
        vm.etch(OPERATIONS_SAFE, hex"00");
        vm.etch(IDENTITY_REGISTRY, hex"00");
        LiveStakingBindingMock staking = new LiveStakingBindingMock();
        vm.etch(LIVE_STAKING, address(staking).code);
    }

    function testPrepareIsKeylessBroadcastFreeAndNonceExact() external view {
        DeployAutolaunchInfraScript.PreparedDeployment memory prepared = script.prepare(_config());
        DeployAutolaunchInfraScript.DeploymentAddresses memory a = prepared.addresses;

        assertEq(a.subjectRegistry, vm.computeCreateAddress(D, N));
        assertEq(a.stakingRouter, vm.computeCreateAddress(D, N + 1));
        assertEq(a.splitterDeployer, vm.computeCreateAddress(D, N + 2));
        assertEq(a.revenueShareFactory, vm.computeCreateAddress(D, N + 3));
        assertEq(a.revenueIngressFactory, vm.computeCreateAddress(D, N + 4));
        assertEq(a.paymentLinkFactory, vm.computeCreateAddress(D, N + 5));
        assertEq(a.strategyFactory, vm.computeCreateAddress(D, N + 6));
        assertEq(a.feeInfraDeployer, vm.computeCreateAddress(D, N + 7));
        assertEq(a.factory, vm.computeCreateAddress(D, N + 8));
        assertEq(a.strategyFactory, 0xEA3b1315A1d214bA7f9Afe726860571D76f8b82c);
        assertEq(a.factory, 0xDc883b4bf20Ee92d81c390A4E57896cd81532184);
        assertEq(prepared.deployDependencies.sender, GOVERNANCE);
        assertEq(prepared.deployDependencies.to, D);
        assertEq(prepared.authorizeFactory.sender, GOVERNANCE);
        assertEq(prepared.authorizeFactory.to, a.strategyFactory);
        assertEq(prepared.deployFactory.sender, GOVERNANCE);
        assertEq(prepared.deployFactory.to, D);
        assertEq(prepared.deployDependencies.value, 0);
        assertEq(prepared.authorizeFactory.value, 0);
        assertEq(prepared.deployFactory.value, 0);
        assertEq(vm.getNonce(D), N);
    }

    function testDeploysExactStackAndRecomputesBindingVector() external {
        DeployAutolaunchInfraScript.DeploymentAddresses memory expected =
            script.predictedAddresses(D, N);
        AutolaunchInfraDeployerV1 deployer = AutolaunchInfraDeployerV1(D);

        bytes32 deployerCodehash = D.codehash;
        uint256 deployerBalance = D.balance;
        _assertPristineDeployer(deployer, expected, deployerCodehash, deployerBalance);

        vm.expectRevert("ONLY_GOVERNANCE");
        vm.prank(ATTACKER);
        deployer.deployDependencies(expected.factory, GUARDIAN, _usdc(), LIVE_STAKING);
        _assertPristineDeployer(deployer, expected, deployerCodehash, deployerBalance);

        vm.prank(GOVERNANCE);
        deployer.deployDependencies(expected.factory, GUARDIAN, _usdc(), LIVE_STAKING);
        assertEq(vm.getNonce(D), N + 8);
        assertEq(address(deployer.subjectRegistry()), expected.subjectRegistry);
        assertEq(address(deployer.stakingRouter()), expected.stakingRouter);
        assertEq(address(deployer.splitterDeployer()), expected.splitterDeployer);
        assertEq(address(deployer.revenueShareFactory()), expected.revenueShareFactory);
        assertEq(address(deployer.revenueIngressFactory()), expected.revenueIngressFactory);
        assertEq(address(deployer.paymentLinkFactory()), expected.paymentLinkFactory);
        assertEq(address(deployer.strategyFactory()), expected.strategyFactory);
        assertEq(address(deployer.feeInfraDeployer()), expected.feeInfraDeployer);

        RegentLBPStrategyFactory strategyFactory = deployer.strategyFactory();
        vm.prank(GOVERNANCE);
        strategyFactory.setAuthorizedCreator(expected.factory, true);
        assertEq(vm.getNonce(D), N + 8);
        vm.expectRevert("ONLY_GOVERNANCE");
        vm.prank(ATTACKER);
        deployer.deployFactory(TOKEN_FACTORY, IDENTITY_REGISTRY, OPERATIONS_SAFE);
        assertEq(D.codehash, deployerCodehash);
        assertEq(D.balance, deployerBalance);
        assertEq(vm.getNonce(D), N + 8);
        assertEq(expected.factory.code.length, 0);
        assertEq(expected.factory.balance, 0);
        _assertDeployerBindings(deployer, expected);
        assertTrue(strategyFactory.authorizedCreators(expected.factory));

        vm.prank(GOVERNANCE);
        AutolaunchFactoryV1 factory =
            deployer.deployFactory(TOKEN_FACTORY, IDENTITY_REGISTRY, OPERATIONS_SAFE);
        assertEq(address(factory), expected.factory);
        assertEq(vm.getNonce(D), N + 9);
        assertEq(address(factory).code.length, 14_777);
        assertLe(address(factory).code.length, 23_576);
        assertEq(
            address(factory).codehash,
            0x26fbb4084d4e17058476a1d255453e36494d2e96e70135ad47f037a2cf9a76cd
        );

        bytes memory args = abi.encode(
            TOKEN_FACTORY,
            expected.strategyFactory,
            expected.revenueShareFactory,
            expected.revenueIngressFactory,
            expected.paymentLinkFactory,
            expected.feeInfraDeployer,
            IDENTITY_REGISTRY,
            OPERATIONS_SAFE
        );
        assertEq(type(AutolaunchFactoryV1).creationCode.length + args.length, 20_242);
        assertLe(type(AutolaunchFactoryV1).creationCode.length + args.length, 48_152);

        bytes32 constructorHash = keccak256(
            abi.encode(
                CONSTRUCTOR_TYPEHASH,
                TOKEN_FACTORY,
                expected.strategyFactory,
                expected.revenueShareFactory,
                expected.revenueIngressFactory,
                expected.paymentLinkFactory,
                expected.feeInfraDeployer,
                IDENTITY_REGISTRY,
                OPERATIONS_SAFE
            )
        );
        bytes32 fixedHash = keccak256(
            abi.encode(
                FIXED_TYPEHASH,
                _usdc(),
                0x6f89bcA4eA5931EdFCB09786267b251DeE752b07,
                0x000000001F26a0044BaA66024e7b6599c61963F8,
                0x498581fF718922c3f8e6A244956aF099B2652b2b,
                0x7C5f5A4bBd8fD63184577525326123B519429bDc,
                LIVE_STAKING
            )
        );
        bytes32 liveHash = _liveReadbacksHash(deployer, expected.factory);
        assertEq(
            constructorHash, 0x38e8be9d89750ebe652b1fef010a53b9e487b7bba2803d3d20cc02ce8e41c13d
        );
        assertEq(fixedHash, 0x7fd468b6a0bc2dab66815bb15e6aa4ab42ec56e5f7aae62f4431bc94a58df03f);
        assertEq(liveHash, 0xdd3da8abc137bbe448b87405f36120c2684fa0d34fbd992862ec0a3df2a9d8cc);
        assertEq(
            keccak256(
                abi.encode(
                    BINDING_TYPEHASH,
                    block.chainid,
                    address(factory),
                    address(factory).codehash,
                    ABI_SHA256,
                    constructorHash,
                    fixedHash,
                    liveHash
                )
            ),
            0xc7b3c6119f5a2f8f8973c3a5d063963b5e0c3e853314e7bff96fa0ef1ab4c35d
        );
        _assertRetiredSelectorsReject(address(factory), deployer, expected);
    }

    function testDeployerConstructionRejectsZeroGovernance() external {
        vm.expectRevert("GOVERNANCE_ZERO");
        new AutolaunchInfraDeployerV1(address(0));
    }

    function testPrepareRejectsDeployerGovernanceMismatch() external {
        AutolaunchInfraDeployerV1 wrong = new AutolaunchInfraDeployerV1(ATTACKER);
        DeployAutolaunchInfraScript.ScriptConfig memory cfg = _config();
        cfg.deployer = address(wrong);
        cfg.startingNonce = vm.getNonce(address(wrong));
        vm.expectRevert("DEPLOYER_GOVERNANCE_MISMATCH");
        script.prepare(cfg);
    }

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
                    "AutolaunchLiveReadbacksV1(address subjectRegistry,address subjectRegistryController,address revenueShareController,address revenueIngressController,address paymentLinkController,address revenueIngressSubjectRegistry,address paymentLinkSubjectRegistry,address stakingRouter,address splitterDeployer,address revenueShareUsdc,address revenueIngressUsdc,address paymentLinkUsdc,address stakingRouterUsdc,address stakingRouterSubjectRegistry,address stakingRouterRegentRevenueStaking,uint16 stakingRouterProtocolSkimBps,bool strategyFactoryAuthorized,address feeInfraAuthorizedController,address subjectRegistryGovernance,address subjectRegistryGuardian)"
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
            '[{"inputs":[{"components":[{"name":"agentId","type":"uint256"},{"name":"tokenName","type":"string"},{"name":"tokenSymbol","type":"string"},{"name":"startBlock","type":"uint64"},{"name":"floorPrice","type":"uint256"},{"name":"requiredRegentRaised","type":"uint128"},{"name":"launchFeeHookSalt","type":"bytes32"}],"name":"params","type":"tuple"}],"name":"launch","outputs":[{"components":[{"name":"token","type":"address"},{"name":"auction","type":"address"},{"name":"strategy","type":"address"},{"name":"vestingWallet","type":"address"},{"name":"revenueShare","type":"address"},{"name":"defaultIngress","type":"address"},{"name":"canonicalPaymentLink","type":"address"},{"name":"subjectId","type":"bytes32"},{"name":"poolId","type":"bytes32"}],"name":"result","type":"tuple"}],"stateMutability":"nonpayable","type":"function"},{"anonymous":false,"inputs":[{"indexed":true,"name":"launchId","type":"bytes32"},{"indexed":true,"name":"agentId","type":"uint256"},{"indexed":true,"name":"agentSafe","type":"address"},{"indexed":false,"name":"token","type":"address"},{"indexed":false,"name":"auction","type":"address"},{"indexed":false,"name":"strategy","type":"address"},{"indexed":false,"name":"vestingWallet","type":"address"},{"indexed":false,"name":"revenueShare","type":"address"},{"indexed":false,"name":"defaultIngress","type":"address"},{"indexed":false,"name":"canonicalPaymentLink","type":"address"},{"indexed":false,"name":"poolId","type":"bytes32"}],"name":"LaunchCreated","type":"event"}]'
        );
        assertEq(normalized.length, 1496);
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
            launchFeeHookSalt: bytes32(uint256(11))
        });
        bytes memory callData = abi.encodeCall(IAutolaunchFactoryV1.launch, (params));
        assertEq(
            IAutolaunchFactoryV1.launch.selector,
            bytes4(keccak256("launch((uint256,string,string,uint64,uint256,uint128,bytes32))"))
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

    function testPrepareRejectsNonceDrift() external {
        vm.setNonce(D, N + 1);
        vm.expectRevert("DEPLOYER_NONCE_CHANGED");
        script.prepare(_config());
    }

    function _liveReadbacksHash(AutolaunchInfraDeployerV1 d, address factory)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                LIVE_TYPEHASH,
                address(d.subjectRegistry()),
                factory,
                factory,
                factory,
                factory,
                address(d.subjectRegistry()),
                address(d.subjectRegistry()),
                address(d.stakingRouter()),
                address(d.splitterDeployer()),
                _usdc(),
                _usdc(),
                _usdc(),
                _usdc(),
                address(d.subjectRegistry()),
                LIVE_STAKING,
                uint16(100),
                true,
                factory,
                GOVERNANCE,
                GUARDIAN
            )
        );
    }

    function _assertRetiredSelectorsReject(
        address factory,
        AutolaunchInfraDeployerV1 deployer,
        DeployAutolaunchInfraScript.DeploymentAddresses memory expected
    ) private {
        bytes[13] memory probes;
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

        address[9] memory targets = _targets(expected);
        bytes32[9] memory codehashes;
        uint256[9] memory balances;
        for (uint256 i; i < targets.length; ++i) {
            codehashes[i] = targets[i].codehash;
            balances[i] = targets[i].balance;
        }
        bytes32 factoryCodehash = factory.codehash;
        uint256 factoryBalance = factory.balance;
        uint256 deployerBalance = D.balance;
        uint64 deployerNonce = vm.getNonce(D);

        for (uint256 i; i < probes.length; ++i) {
            vm.recordLogs();
            (bool ok,) = factory.call(probes[i]);
            assertFalse(ok);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(logs.length, 0);
            assertEq(factory.codehash, factoryCodehash);
            assertEq(factory.balance, factoryBalance);
            assertEq(D.balance, deployerBalance);
            assertEq(vm.getNonce(D), deployerNonce);
            for (uint256 j; j < targets.length; ++j) {
                assertEq(targets[j].codehash, codehashes[j]);
                assertEq(targets[j].balance, balances[j]);
            }
            _assertDeployerBindings(deployer, expected);
            assertTrue(
                RegentLBPStrategyFactory(expected.strategyFactory).authorizedCreators(factory)
            );
        }
    }

    function _assertPristineDeployer(
        AutolaunchInfraDeployerV1 deployer,
        DeployAutolaunchInfraScript.DeploymentAddresses memory expected,
        bytes32 deployerCodehash,
        uint256 deployerBalance
    ) private view {
        assertEq(deployer.governance(), GOVERNANCE);
        assertEq(D.codehash, deployerCodehash);
        assertEq(D.balance, deployerBalance);
        assertEq(vm.getNonce(D), N);
        assertEq(address(deployer.subjectRegistry()), address(0));
        assertEq(address(deployer.stakingRouter()), address(0));
        assertEq(address(deployer.splitterDeployer()), address(0));
        assertEq(address(deployer.revenueShareFactory()), address(0));
        assertEq(address(deployer.revenueIngressFactory()), address(0));
        assertEq(address(deployer.paymentLinkFactory()), address(0));
        assertEq(address(deployer.strategyFactory()), address(0));
        assertEq(address(deployer.feeInfraDeployer()), address(0));
        address[9] memory targets = _targets(expected);
        for (uint256 i; i < targets.length; ++i) {
            assertEq(targets[i].code.length, 0);
            assertEq(targets[i].balance, 0);
        }
    }

    function _assertDeployerBindings(
        AutolaunchInfraDeployerV1 deployer,
        DeployAutolaunchInfraScript.DeploymentAddresses memory expected
    ) private view {
        assertEq(deployer.governance(), GOVERNANCE);
        assertEq(address(deployer.subjectRegistry()), expected.subjectRegistry);
        assertEq(address(deployer.stakingRouter()), expected.stakingRouter);
        assertEq(address(deployer.splitterDeployer()), expected.splitterDeployer);
        assertEq(address(deployer.revenueShareFactory()), expected.revenueShareFactory);
        assertEq(address(deployer.revenueIngressFactory()), expected.revenueIngressFactory);
        assertEq(address(deployer.paymentLinkFactory()), expected.paymentLinkFactory);
        assertEq(address(deployer.strategyFactory()), expected.strategyFactory);
        assertEq(address(deployer.feeInfraDeployer()), expected.feeInfraDeployer);
    }

    function _targets(DeployAutolaunchInfraScript.DeploymentAddresses memory expected)
        private
        pure
        returns (address[9] memory targets)
    {
        targets = [
            expected.subjectRegistry,
            expected.stakingRouter,
            expected.splitterDeployer,
            expected.revenueShareFactory,
            expected.revenueIngressFactory,
            expected.paymentLinkFactory,
            expected.strategyFactory,
            expected.feeInfraDeployer,
            expected.factory
        ];
    }

    function _slice(bytes memory data, uint256 start) private pure returns (bytes memory out) {
        out = new bytes(data.length - start);
        for (uint256 i; i < out.length; ++i) {
            out[i] = data[start + i];
        }
    }

    function _config() private pure returns (DeployAutolaunchInfraScript.ScriptConfig memory) {
        return DeployAutolaunchInfraScript.ScriptConfig({
            deployer: D,
            startingNonce: N,
            governance: GOVERNANCE,
            guardian: GUARDIAN,
            tokenFactory: TOKEN_FACTORY,
            operationsSafe: OPERATIONS_SAFE
        });
    }

    function _usdc() private pure returns (address) {
        return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    }
}
