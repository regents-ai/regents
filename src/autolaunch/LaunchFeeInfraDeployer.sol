// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "src/shared/libraries/HookMiner.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";

contract LaunchFeeInfraDeployer {
    uint160 internal constant REQUIRED_HOOK_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG
        | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
    address public immutable authorizedController;

    constructor(address authorizedController_) {
        require(authorizedController_ != address(0), "AUTHORIZED_CONTROLLER_ZERO");
        authorizedController = authorizedController_;
    }

    function deploy(
        address agentSafe,
        address subjectRegistry,
        bytes32 subjectId,
        address poolManager,
        address quoteToken,
        bytes32 hookSalt
    )
        external
        returns (
            LaunchFeeRegistry launchFeeRegistry,
            LaunchFeeVault feeVault,
            LaunchPoolFeeHook hook
        )
    {
        require(msg.sender == authorizedController, "ONLY_AUTHORIZED_CONTROLLER");
        require(agentSafe != address(0), "AGENT_SAFE_ZERO");
        require(subjectRegistry != address(0), "SUBJECT_REGISTRY_ZERO");
        require(subjectId != bytes32(0), "SUBJECT_ID_ZERO");
        require(poolManager != address(0), "POOL_MANAGER_ZERO");
        require(quoteToken != address(0), "QUOTE_TOKEN_ZERO");

        launchFeeRegistry =
            new LaunchFeeRegistry(agentSafe, msg.sender, subjectRegistry, subjectId, quoteToken);
        feeVault = new LaunchFeeVault(address(launchFeeRegistry));

        bytes memory hookConstructorArgs =
            abi.encode(address(this), poolManager, address(launchFeeRegistry), address(feeVault));
        // slither-disable-next-line too-many-digits
        bytes32 hookInitCodeHash =
            keccak256(abi.encodePacked(type(LaunchPoolFeeHook).creationCode, hookConstructorArgs));
        address expectedHookAddress =
            HookMiner.computeCreate2Address(address(this), hookSalt, hookInitCodeHash);
        require(
            (uint160(expectedHookAddress) & uint160((1 << 14) - 1)) == REQUIRED_HOOK_FLAGS,
            "HOOK_FLAGS_INVALID"
        );

        hook = new LaunchPoolFeeHook{salt: hookSalt}(
            address(this), poolManager, address(launchFeeRegistry), address(feeVault)
        );
        require(address(hook) == expectedHookAddress, "HOOK_ADDRESS_MISMATCH");

        feeVault.setHook(address(hook));
    }
}
