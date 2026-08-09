// SPDX-License-Identifier: MIT
// slither-disable-next-line pragma
pragma solidity ^0.8.26;

// slither-disable-next-line missing-inheritance
interface IRegentRevenueStakingFunding {
    function fundRegentRewards(uint256 amount) external returns (uint256 received);
}
