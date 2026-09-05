// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RevenueShareSplitter} from "reference/revenue/RevenueShareSplitter.sol";

/// @notice Legacy reference deployer. Active deployment tooling must not use it.
contract RevenueShareSplitterDeployer {
    function deploy(
        address stakeToken,
        address usdc,
        address ingressFactory,
        address subjectRegistry,
        bytes32 subjectId,
        address treasuryRecipient,
        address protocolRecipient,
        uint256 revenueShareSupplyDenominator,
        string calldata label,
        address owner
    ) external returns (RevenueShareSplitter splitter) {
        splitter = new RevenueShareSplitter(
            stakeToken,
            usdc,
            ingressFactory,
            subjectRegistry,
            subjectId,
            treasuryRecipient,
            protocolRecipient,
            revenueShareSupplyDenominator,
            label,
            owner
        );
    }
}
