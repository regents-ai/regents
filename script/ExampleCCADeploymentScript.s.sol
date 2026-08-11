// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {IAutolaunchFactoryV1} from "src/autolaunch/interfaces/IAutolaunchFactoryV1.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {HookMiner} from "src/shared/libraries/HookMiner.sol";

/// @notice Prepares the exact inner Safe CALL. It never reads a key or starts a broadcast.
contract ExampleCCADeploymentScript is Script {
    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;
    uint256 internal constant AUCTION_TICK_SPACING = 79_228_162_514_264_337_593_543_950;
    uint160 internal constant REQUIRED_HOOK_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG
        | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    struct ScriptConfig {
        address agentSafe;
        address factory;
        address feeInfraDeployer;
        uint256 agentId;
        string tokenName;
        string tokenSymbol;
        uint64 startBlock;
        uint256 floorPrice;
        uint128 requiredRegentRaised;
    }

    struct PreparedSafeCall {
        address from;
        address to;
        uint256 value;
        bytes data;
        uint8 operation;
        uint64 feeInfraDeployerNonce;
        bytes32 launchFeeHookSalt;
    }

    function prepare(ScriptConfig memory cfg) public view returns (PreparedSafeCall memory call) {
        _validate(cfg);
        uint64 nonce = vm.getNonce(cfg.feeInfraDeployer);
        bytes32 salt = _launchFeeHookSalt(cfg.feeInfraDeployer, nonce);
        uint256 expectedFee = IAutolaunchFactoryV1(cfg.factory).launchFee();
        IAutolaunchFactoryV1.LaunchParams memory params = IAutolaunchFactoryV1.LaunchParams({
            agentId: cfg.agentId,
            tokenName: cfg.tokenName,
            tokenSymbol: cfg.tokenSymbol,
            startBlock: cfg.startBlock,
            floorPrice: cfg.floorPrice,
            requiredRegentRaised: cfg.requiredRegentRaised,
            expectedFee: expectedFee,
            launchFeeHookSalt: salt
        });
        call = PreparedSafeCall({
            from: cfg.agentSafe,
            to: cfg.factory,
            value: 0,
            data: abi.encodeCall(IAutolaunchFactoryV1.launch, (params)),
            operation: 0,
            feeInfraDeployerNonce: nonce,
            launchFeeHookSalt: salt
        });
    }

    function loadConfigFromEnv() public view returns (ScriptConfig memory cfg) {
        cfg.agentSafe = vm.envAddress("AUTOLAUNCH_AGENT_SAFE_ADDRESS");
        cfg.factory = vm.envAddress("AUTOLAUNCH_FACTORY_ADDRESS");
        cfg.feeInfraDeployer = vm.envAddress("AUTOLAUNCH_FEE_INFRA_DEPLOYER_ADDRESS");
        cfg.agentId = vm.envUint("AUTOLAUNCH_AGENT_ID");
        cfg.tokenName = vm.envString("AUTOLAUNCH_TOKEN_NAME");
        cfg.tokenSymbol = vm.envString("AUTOLAUNCH_TOKEN_SYMBOL");
        cfg.startBlock = uint64(vm.envUint("AUTOLAUNCH_START_BLOCK"));
        cfg.floorPrice = vm.envUint("AUTOLAUNCH_FLOOR_PRICE");
        cfg.requiredRegentRaised = uint128(vm.envUint("AUTOLAUNCH_REQUIRED_REGENT_RAISED"));
        _validate(cfg);
    }

    function run() external view returns (PreparedSafeCall memory) {
        return prepare(loadConfigFromEnv());
    }

    function _validate(ScriptConfig memory cfg) private view {
        require(block.chainid == BASE_MAINNET_CHAIN_ID, "BASE_MAINNET_ONLY");
        require(cfg.agentSafe.code.length != 0, "AGENT_SAFE_NOT_DEPLOYED");
        require(cfg.factory.code.length != 0, "FACTORY_NOT_DEPLOYED");
        require(cfg.feeInfraDeployer.code.length != 0, "FEE_DEPLOYER_NOT_DEPLOYED");
        require(
            LaunchFeeInfraDeployer(cfg.feeInfraDeployer).authorizedController() == cfg.factory,
            "FEE_DEPLOYER_FACTORY_MISMATCH"
        );
        require(cfg.startBlock >= block.number + 300, "START_BLOCK_TOO_SOON");
        require(cfg.floorPrice != 0, "FLOOR_PRICE_ZERO");
        require(cfg.floorPrice % AUCTION_TICK_SPACING == 0, "FLOOR_PRICE_TICK_MISALIGNED");
        require(cfg.requiredRegentRaised != 0, "REQUIRED_REGENT_ZERO");
        require(bytes(cfg.tokenName).length != 0, "NAME_EMPTY");
        require(bytes(cfg.tokenSymbol).length != 0, "SYMBOL_EMPTY");
    }

    function _launchFeeHookSalt(address feeInfraDeployer, uint64 nonce)
        private
        pure
        returns (bytes32 hookSalt)
    {
        address launchFeeRegistry = vm.computeCreateAddress(feeInfraDeployer, nonce);
        address feeVault = vm.computeCreateAddress(feeInfraDeployer, nonce + 1);
        (hookSalt,) = HookMiner.find(
            feeInfraDeployer,
            REQUIRED_HOOK_FLAGS,
            type(LaunchPoolFeeHook).creationCode,
            abi.encode(feeInfraDeployer, POOL_MANAGER, launchFeeRegistry, feeVault)
        );
    }
}
