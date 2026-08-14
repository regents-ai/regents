// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";

import {AutolaunchCreateSequencerV1} from "src/autolaunch/AutolaunchCreateSequencerV1.sol";
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
import {
    IRegentRevenueStakingMinimal
} from "src/autolaunch/revenue/interfaces/IRegentRevenueStakingMinimal.sol";

/// @notice Offchain builder for the Autolaunch ceremony. It produces one unsigned sequencer
/// creation record and four unsigned zero-value governance calls. It never starts a broadcast,
/// signs, deploys, or reads chain state beyond the local preflight assumptions it validates.
contract DeployAutolaunchInfraScript is Script {
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address internal constant LIVE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;

    struct ScriptConfig {
        address creator;
        uint64 creatorNonce;
        address governance;
        address guardian;
        address tokenFactory;
        address operationsSafe;
    }

    /// @notice A direct contract-creation transaction. It has no `to` and carries initcode.
    struct PreparedCreation {
        address sender;
        uint64 nonce;
        uint256 value;
        bytes initcode;
        bytes32 initcodeHash;
        address expectedAddress;
        bytes32[9] childInitcodeHashes;
    }

    struct PreparedCall {
        address sender;
        address to;
        uint256 value;
        bytes data;
    }

    struct DeploymentAddresses {
        address sequencer;
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
        PreparedCreation createSequencer;
        PreparedCall dependenciesPhaseOne;
        PreparedCall dependenciesPhaseTwo;
        PreparedCall authorizeStrategyFactory;
        PreparedCall deployFactory;
    }

    function prepare(ScriptConfig memory cfg)
        public
        view
        returns (PreparedDeployment memory prepared)
    {
        _validate(cfg);
        prepared.addresses = predictedAddresses(cfg.creator, cfg.creatorNonce);
        bytes[9] memory initcodes = _childInitcodes(cfg, prepared.addresses);
        bytes32[9] memory hashes;
        for (uint256 i; i < 9; ++i) {
            hashes[i] = keccak256(initcodes[i]);
        }

        bytes memory sequencerInitcode = bytes.concat(
            type(AutolaunchCreateSequencerV1).creationCode, abi.encode(cfg.governance, hashes)
        );
        prepared.createSequencer = PreparedCreation({
            sender: cfg.creator,
            nonce: cfg.creatorNonce,
            value: 0,
            initcode: sequencerInitcode,
            initcodeHash: keccak256(sequencerInitcode),
            expectedAddress: prepared.addresses.sequencer,
            childInitcodeHashes: hashes
        });

        bytes[4] memory phaseOne;
        bytes[4] memory phaseTwo;
        for (uint256 i; i < 4; ++i) {
            phaseOne[i] = initcodes[i];
            phaseTwo[i] = initcodes[i + 4];
        }
        prepared.dependenciesPhaseOne = PreparedCall({
            sender: cfg.governance,
            to: prepared.addresses.sequencer,
            value: 0,
            data: abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseOne, (phaseOne))
        });
        prepared.dependenciesPhaseTwo = PreparedCall({
            sender: cfg.governance,
            to: prepared.addresses.sequencer,
            value: 0,
            data: abi.encodeCall(AutolaunchCreateSequencerV1.deployDependenciesPhaseTwo, (phaseTwo))
        });
        prepared.authorizeStrategyFactory = PreparedCall({
            sender: cfg.governance,
            to: prepared.addresses.strategyFactory,
            value: 0,
            data: abi.encodeCall(
                RegentLBPStrategyFactory.setAuthorizedCreator, (prepared.addresses.factory, true)
            )
        });
        prepared.deployFactory = PreparedCall({
            sender: cfg.governance,
            to: prepared.addresses.sequencer,
            value: 0,
            data: abi.encodeCall(AutolaunchCreateSequencerV1.deployFactory, (initcodes[8]))
        });
    }

    /// @notice The nine reviewed complete initcodes in ceremony order, dependencies then factory.
    function childInitcodes(ScriptConfig memory cfg) public view returns (bytes[9] memory) {
        _validate(cfg);
        return _childInitcodes(cfg, predictedAddresses(cfg.creator, cfg.creatorNonce));
    }

    /// @dev An ordinarily created sequencer starts at nonce one, so the ceremony has no
    /// operator-supplied starting nonce.
    function predictedAddresses(address creator, uint64 creatorNonce)
        public
        pure
        returns (DeploymentAddresses memory addresses)
    {
        address sequencer = vm.computeCreateAddress(creator, creatorNonce);
        addresses.sequencer = sequencer;
        addresses.subjectRegistry = vm.computeCreateAddress(sequencer, 1);
        addresses.stakingRouter = vm.computeCreateAddress(sequencer, 2);
        addresses.splitterDeployer = vm.computeCreateAddress(sequencer, 3);
        addresses.revenueShareFactory = vm.computeCreateAddress(sequencer, 4);
        addresses.revenueIngressFactory = vm.computeCreateAddress(sequencer, 5);
        addresses.paymentLinkFactory = vm.computeCreateAddress(sequencer, 6);
        addresses.strategyFactory = vm.computeCreateAddress(sequencer, 7);
        addresses.feeInfraDeployer = vm.computeCreateAddress(sequencer, 8);
        addresses.factory = vm.computeCreateAddress(sequencer, 9);
    }

    function loadConfigFromEnv() public view returns (ScriptConfig memory cfg) {
        cfg.creator = vm.envAddress("AUTOLAUNCH_SEQUENCER_CREATOR_ADDRESS");
        cfg.creatorNonce = uint64(vm.envUint("AUTOLAUNCH_SEQUENCER_CREATOR_NONCE"));
        cfg.governance = vm.envAddress("AUTOLAUNCH_GOVERNANCE_ADDRESS");
        cfg.guardian = vm.envAddress("AUTOLAUNCH_GUARDIAN_ADDRESS");
        cfg.tokenFactory = vm.envAddress("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS");
        cfg.operationsSafe = vm.envAddress("AUTOLAUNCH_OPERATIONS_SAFE_ADDRESS");
        _validate(cfg);
    }

    function run() external view returns (PreparedDeployment memory) {
        return prepare(loadConfigFromEnv());
    }

    function _childInitcodes(ScriptConfig memory cfg, DeploymentAddresses memory addresses)
        private
        pure
        returns (bytes[9] memory initcodes)
    {
        initcodes[0] = bytes.concat(
            type(SubjectRegistry).creationCode,
            abi.encode(addresses.factory, cfg.governance, cfg.guardian)
        );
        initcodes[1] = bytes.concat(
            type(RegentStakingRevenueRouter).creationCode,
            abi.encode(cfg.governance, USDC, addresses.subjectRegistry, LIVE_STAKING)
        );
        initcodes[2] = type(RevenueShareSplitterV2Deployer).creationCode;
        initcodes[3] = bytes.concat(
            type(RevenueShareFactory).creationCode,
            abi.encode(
                cfg.governance,
                USDC,
                addresses.subjectRegistry,
                addresses.stakingRouter,
                addresses.splitterDeployer
            )
        );
        initcodes[4] = bytes.concat(
            type(RevenueIngressFactory).creationCode,
            abi.encode(USDC, addresses.subjectRegistry, cfg.governance)
        );
        initcodes[5] = bytes.concat(
            type(PaymentLinkFactory).creationCode,
            abi.encode(cfg.governance, USDC, addresses.subjectRegistry)
        );
        initcodes[6] =
            bytes.concat(type(RegentLBPStrategyFactory).creationCode, abi.encode(cfg.governance));
        initcodes[7] =
            bytes.concat(type(LaunchFeeInfraDeployer).creationCode, abi.encode(addresses.factory));
        initcodes[8] = bytes.concat(
            type(AutolaunchFactoryV1).creationCode,
            abi.encode(
                cfg.tokenFactory,
                addresses.strategyFactory,
                addresses.revenueShareFactory,
                addresses.revenueIngressFactory,
                addresses.paymentLinkFactory,
                addresses.feeInfraDeployer,
                IDENTITY_REGISTRY,
                cfg.operationsSafe
            )
        );
    }

    /// @dev Code presence here is local preparation evidence only. The future ceremony preflight
    /// revalidates it, and the exact live Safe identity and configuration, against a provider.
    function _validate(ScriptConfig memory cfg) private view {
        require(block.chainid == BASE_MAINNET_CHAIN_ID, "BASE_MAINNET_ONLY");
        require(cfg.creator != address(0), "CREATOR_ZERO");
        require(cfg.creator.code.length == 0, "CREATOR_IS_CONTRACT");
        require(vm.getNonce(cfg.creator) == cfg.creatorNonce, "CREATOR_NONCE_CHANGED");
        require(cfg.governance != address(0), "GOVERNANCE_ZERO");
        require(cfg.guardian != address(0), "GUARDIAN_ZERO");
        require(cfg.governance != cfg.guardian, "GOVERNANCE_IS_GUARDIAN");
        require(cfg.governance.code.length != 0, "GOVERNANCE_NOT_DEPLOYED");
        require(cfg.guardian.code.length != 0, "GUARDIAN_NOT_DEPLOYED");
        require(cfg.tokenFactory.code.length != 0, "TOKEN_FACTORY_NOT_DEPLOYED");
        require(cfg.operationsSafe.code.length != 0, "OPERATIONS_SAFE_NOT_DEPLOYED");
        require(USDC.code.length != 0, "USDC_NOT_DEPLOYED");
        require(IDENTITY_REGISTRY.code.length != 0, "IDENTITY_REGISTRY_NOT_DEPLOYED");
        require(LIVE_STAKING.code.length != 0, "LIVE_STAKING_NOT_DEPLOYED");
        // The typed reader is the check: a revert, short or dirty return word, or different
        // binding fails here, while harmless trailing return data stays acceptable.
        require(
            IRegentRevenueStakingMinimal(LIVE_STAKING).usdc() == USDC, "LIVE_STAKING_USDC_MISMATCH"
        );
    }
}
