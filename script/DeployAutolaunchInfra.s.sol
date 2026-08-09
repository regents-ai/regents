// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";

import {AutolaunchFactoryV1} from "src/autolaunch/AutolaunchFactoryV1.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {PaymentLinkFactory} from "src/autolaunch/revenue/PaymentLinkFactory.sol";
import {RegentStakingRevenueRouter} from "src/autolaunch/revenue/RegentStakingRevenueRouter.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";

/// @notice Disposable CREATE deployer. Its nonce must be N before the first call.
contract AutolaunchInfraDeployerV1 {
    address public immutable governance;
    SubjectRegistry public subjectRegistry;
    RegentStakingRevenueRouter public stakingRouter;
    RevenueShareSplitterV2Deployer public splitterDeployer;
    RevenueShareFactory public revenueShareFactory;
    RevenueIngressFactory public revenueIngressFactory;
    PaymentLinkFactory public paymentLinkFactory;
    RegentLBPStrategyFactory public strategyFactory;
    LaunchFeeInfraDeployer public feeInfraDeployer;

    constructor(address governance_) {
        require(governance_ != address(0), "GOVERNANCE_ZERO");
        governance = governance_;
    }

    function deployDependencies(
        address predictedFactory,
        address guardian,
        address usdc,
        address liveStaking
    ) external {
        require(msg.sender == governance, "ONLY_GOVERNANCE");
        require(address(subjectRegistry) == address(0), "DEPENDENCIES_ALREADY_DEPLOYED");
        subjectRegistry = new SubjectRegistry(predictedFactory, governance, guardian);
        stakingRouter =
            new RegentStakingRevenueRouter(governance, usdc, address(subjectRegistry), liveStaking);
        splitterDeployer = new RevenueShareSplitterV2Deployer();
        revenueShareFactory = new RevenueShareFactory(
            governance, usdc, subjectRegistry, address(stakingRouter), address(splitterDeployer)
        );
        revenueIngressFactory =
            new RevenueIngressFactory(usdc, address(subjectRegistry), governance);
        paymentLinkFactory = new PaymentLinkFactory(governance, usdc, address(subjectRegistry));
        strategyFactory = new RegentLBPStrategyFactory(governance);
        feeInfraDeployer = new LaunchFeeInfraDeployer(predictedFactory);
    }

    function deployFactory(address tokenFactory, address identityRegistry, address operationsSafe)
        external
        returns (AutolaunchFactoryV1 factory)
    {
        require(msg.sender == governance, "ONLY_GOVERNANCE");
        require(address(feeInfraDeployer) != address(0), "DEPENDENCIES_NOT_DEPLOYED");
        factory = new AutolaunchFactoryV1(
            tokenFactory,
            address(strategyFactory),
            address(revenueShareFactory),
            address(revenueIngressFactory),
            address(paymentLinkFactory),
            address(feeInfraDeployer),
            identityRegistry,
            operationsSafe
        );
    }
}

/// @notice Produces unsigned, zero-value calls only. It never starts a broadcast.
contract DeployAutolaunchInfraScript is Script {
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address internal constant LIVE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;

    struct ScriptConfig {
        address deployer;
        uint64 startingNonce;
        address governance;
        address guardian;
        address tokenFactory;
        address operationsSafe;
    }

    struct PreparedCall {
        address sender;
        address to;
        uint256 value;
        bytes data;
    }

    struct DeploymentAddresses {
        address subjectRegistry;
        address stakingRouter;
        address splitterDeployer;
        address revenueShareFactory;
        address revenueIngressFactory;
        address paymentLinkFactory;
        address strategyFactory;
        address feeInfraDeployer;
        address factory;
    }

    struct PreparedDeployment {
        DeploymentAddresses addresses;
        PreparedCall deployDependencies;
        PreparedCall authorizeFactory;
        PreparedCall deployFactory;
    }

    function prepare(ScriptConfig memory cfg)
        public
        view
        returns (PreparedDeployment memory prepared)
    {
        _validate(cfg);
        prepared.addresses = predictedAddresses(cfg.deployer, cfg.startingNonce);
        prepared.deployDependencies = PreparedCall({
            sender: cfg.governance,
            to: cfg.deployer,
            value: 0,
            data: abi.encodeCall(
                AutolaunchInfraDeployerV1.deployDependencies,
                (prepared.addresses.factory, cfg.guardian, USDC, LIVE_STAKING)
            )
        });
        prepared.authorizeFactory = PreparedCall({
            sender: cfg.governance,
            to: prepared.addresses.strategyFactory,
            value: 0,
            data: abi.encodeCall(
                RegentLBPStrategyFactory.setAuthorizedCreator, (prepared.addresses.factory, true)
            )
        });
        prepared.deployFactory = PreparedCall({
            sender: cfg.governance,
            to: cfg.deployer,
            value: 0,
            data: abi.encodeCall(
                AutolaunchInfraDeployerV1.deployFactory,
                (cfg.tokenFactory, IDENTITY_REGISTRY, cfg.operationsSafe)
            )
        });
    }

    function predictedAddresses(address deployer, uint64 nonce)
        public
        pure
        returns (DeploymentAddresses memory addresses)
    {
        addresses.subjectRegistry = vm.computeCreateAddress(deployer, nonce);
        addresses.stakingRouter = vm.computeCreateAddress(deployer, nonce + 1);
        addresses.splitterDeployer = vm.computeCreateAddress(deployer, nonce + 2);
        addresses.revenueShareFactory = vm.computeCreateAddress(deployer, nonce + 3);
        addresses.revenueIngressFactory = vm.computeCreateAddress(deployer, nonce + 4);
        addresses.paymentLinkFactory = vm.computeCreateAddress(deployer, nonce + 5);
        addresses.strategyFactory = vm.computeCreateAddress(deployer, nonce + 6);
        addresses.feeInfraDeployer = vm.computeCreateAddress(deployer, nonce + 7);
        addresses.factory = vm.computeCreateAddress(deployer, nonce + 8);
    }

    function loadConfigFromEnv() public view returns (ScriptConfig memory cfg) {
        cfg.deployer = vm.envAddress("AUTOLAUNCH_DISPOSABLE_DEPLOYER_ADDRESS");
        cfg.startingNonce = uint64(vm.envUint("AUTOLAUNCH_DISPOSABLE_DEPLOYER_NONCE"));
        cfg.governance = vm.envAddress("AUTOLAUNCH_GOVERNANCE_ADDRESS");
        cfg.guardian = vm.envAddress("AUTOLAUNCH_GUARDIAN_ADDRESS");
        cfg.tokenFactory = vm.envAddress("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS");
        cfg.operationsSafe = vm.envAddress("AUTOLAUNCH_OPERATIONS_SAFE_ADDRESS");
        _validate(cfg);
    }

    function run() external view returns (PreparedDeployment memory) {
        return prepare(loadConfigFromEnv());
    }

    function _validate(ScriptConfig memory cfg) private view {
        require(block.chainid == BASE_MAINNET_CHAIN_ID, "BASE_MAINNET_ONLY");
        require(cfg.deployer.code.length != 0, "DEPLOYER_NOT_DEPLOYED");
        require(vm.getNonce(cfg.deployer) == cfg.startingNonce, "DEPLOYER_NONCE_CHANGED");
        require(cfg.governance != address(0), "GOVERNANCE_ZERO");
        require(
            AutolaunchInfraDeployerV1(cfg.deployer).governance() == cfg.governance,
            "DEPLOYER_GOVERNANCE_MISMATCH"
        );
        require(cfg.guardian != address(0), "GUARDIAN_ZERO");
        require(cfg.governance != cfg.guardian, "GOVERNANCE_IS_GUARDIAN");
        require(cfg.tokenFactory.code.length != 0, "TOKEN_FACTORY_NOT_DEPLOYED");
        require(cfg.operationsSafe.code.length != 0, "OPERATIONS_SAFE_NOT_DEPLOYED");
    }
}
