// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRevenueShareSplitter} from "src/autolaunch/revenue/interfaces/IRevenueShareSplitter.sol";

interface ILiveStakeFeePoolSplitter is IRevenueShareSplitter {
    function stakerPoolBps() external view returns (uint16);
    function accRewardPerTokenUsdc() external view returns (uint256);
    function protocolFeeUsdc() external view returns (uint256);
    function stakerPoolInflowUsdc() external view returns (uint256);
    function treasuryReservedUsdc() external view returns (uint256);
    function stakedBalance(address account) external view returns (uint256);
}
