// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRegentStakingRevenueRouter {
    event ProtocolSkimBpsSet(uint16 previousBps, uint16 newBps);

    function usdc() external view returns (address);
    function regentRevenueStaking() external view returns (address);
    function protocolSkimBps() external view returns (uint16);
    function setProtocolSkimBps(uint16 newBps) external;

    function processProtocolFee(bytes32 subjectId, uint256 usdcAmount, bytes32 sourceRef)
        external
        returns (uint256 depositedUsdc);
}
