// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentSafePolicy} from "src/autolaunch/libraries/AgentSafePolicy.sol";

contract AgentSafePolicyMock {
    function validate(
        address safe,
        address controller,
        address runtime,
        AgentSafePolicy.ExpectedState calldata expected,
        bytes32 digest,
        bytes calldata signature
    ) external view {
        AgentSafePolicy.validate(safe, controller, runtime, expected, digest, signature);
    }

    function emptyModulesHash() external pure returns (bytes32) {
        return AgentSafePolicy.emptyModulesHash();
    }

    function structureCommitment(address safe, address controller, address runtime)
        external
        view
        returns (bytes32)
    {
        return AgentSafePolicy.structureCommitment(
            AgentSafePolicy.readStructure(safe, controller, runtime)
        );
    }

    function identityPins()
        external
        pure
        returns (
            bytes20 sourceCommit,
            bytes20 sourceTree,
            bytes20 deploymentsCommit,
            bytes20 deploymentsTree
        )
    {
        return (
            AgentSafePolicy.SAFE_SOURCE_COMMIT,
            AgentSafePolicy.SAFE_SOURCE_TREE,
            AgentSafePolicy.SAFE_DEPLOYMENTS_COMMIT,
            AgentSafePolicy.SAFE_DEPLOYMENTS_TREE
        );
    }

    function selectors()
        external
        pure
        returns (
            bytes4 createProxyWithNonce,
            bytes4 setup,
            bytes4 excludedChainSpecific,
            bytes4 excludedCallback,
            bytes4 legacyEip1271,
            bytes4 eip1271
        )
    {
        return (
            AgentSafePolicy.CREATE_PROXY_WITH_NONCE_SELECTOR,
            AgentSafePolicy.SAFE_SETUP_SELECTOR,
            AgentSafePolicy.EXCLUDED_CHAIN_SPECIFIC_PROXY_SELECTOR,
            AgentSafePolicy.EXCLUDED_CALLBACK_PROXY_SELECTOR,
            AgentSafePolicy.EIP1271_BYTES_MAGIC_VALUE,
            AgentSafePolicy.EIP1271_BYTES32_MAGIC_VALUE
        );
    }
}
