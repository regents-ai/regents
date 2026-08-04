// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {IRevenueShareSplitterV2Deployer} from "src/autolaunch/revenue/RevenueShareFactory.sol";

contract RevenueShareSplitterV2Deployer is IRevenueShareSplitterV2Deployer {
    function deploy(
        address stakeToken,
        address usdc,
        address ingressFactory,
        address subjectRegistry,
        bytes32 subjectId,
        address treasuryRecipient,
        address stakingRevenueRouter,
        uint256 revenueShareSupplyDenominator,
        string calldata label,
        address owner
    ) external returns (address splitter) {
        splitter = address(
            new RevenueShareSplitterV2(
                stakeToken,
                usdc,
                ingressFactory,
                subjectRegistry,
                subjectId,
                treasuryRecipient,
                stakingRevenueRouter,
                revenueShareSupplyDenominator,
                label,
                owner
            )
        );
    }
}
