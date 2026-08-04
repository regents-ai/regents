// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";

contract MockRegentStakingRevenueRouter is IRegentStakingRevenueRouter {
    address public immutable override usdc;
    address public immutable override regentRevenueStaking;
    uint16 public override protocolSkimBps = 100;
    bool public shouldRevert;
    uint256 public totalUsdcProcessed;
    uint256 public totalUsdcDepositedToRegentStaking;
    bytes32 public lastSubjectId;
    bytes32 public lastSourceRef;
    uint256 public processProtocolFeeReturnOverride = type(uint256).max;

    constructor(address usdc_, address regentRevenueStaking_) {
        usdc = usdc_;
        regentRevenueStaking = regentRevenueStaking_;
    }

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function setProcessProtocolFeeReturnOverride(uint256 returnOverride) external {
        processProtocolFeeReturnOverride = returnOverride;
    }

    function processProtocolFee(bytes32 subjectId, uint256 usdcAmount, bytes32 sourceRef)
        external
        override
        returns (uint256 depositedUsdc)
    {
        require(!shouldRevert, "MOCK_ROUTER_REVERT");
        totalUsdcProcessed += usdcAmount;
        totalUsdcDepositedToRegentStaking += usdcAmount;
        lastSubjectId = subjectId;
        lastSourceRef = sourceRef;
        if (processProtocolFeeReturnOverride != type(uint256).max) {
            return processProtocolFeeReturnOverride;
        }
        return usdcAmount;
    }
}
