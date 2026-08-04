// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/shared/auth/Owned.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol";
import {
    IRegentRevenueStakingMinimal
} from "src/autolaunch/revenue/interfaces/IRegentRevenueStakingMinimal.sol";
import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";

contract RegentStakingRevenueRouter is Owned, IRegentStakingRevenueRouter {
    using SafeTransferLib for address;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint16 public constant override protocolSkimBps = 100;

    address public immutable override usdc;
    address public immutable override regentRevenueStaking;
    address public immutable subjectRegistry;

    uint256 public maxUsdcPerSettlement = 50_000e6;
    uint256 public totalUsdcSettled;
    uint256 public totalUsdcDepositedToRegentStaking;

    uint256 private _reentrancyGuard = 1;

    event MaxUsdcPerSettlementSet(uint256 previousAmount, uint256 newAmount);
    event ProtocolFeeDepositedToRegentStaking(
        bytes32 indexed subjectId,
        address indexed splitter,
        address indexed subjectTreasury,
        uint256 usdcAmount,
        uint256 depositedUsdc,
        bytes32 sourceRef
    );

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    constructor(
        address owner_,
        address usdc_,
        address subjectRegistry_,
        address regentRevenueStaking_
    ) Owned(owner_) {
        require(usdc_ != address(0), "USDC_ZERO");
        require(subjectRegistry_ != address(0), "SUBJECT_REGISTRY_ZERO");
        require(regentRevenueStaking_ != address(0), "STAKING_ZERO");
        require(
            IRegentRevenueStakingMinimal(regentRevenueStaking_).usdc() == usdc_,
            "STAKING_USDC_MISMATCH"
        );

        usdc = usdc_;
        subjectRegistry = subjectRegistry_;
        regentRevenueStaking = regentRevenueStaking_;
    }

    function processProtocolFee(bytes32 subjectId, uint256 usdcAmount, bytes32 sourceRef)
        external
        override
        nonReentrant
        returns (uint256 depositedUsdc)
    {
        require(subjectId != bytes32(0), "SUBJECT_ZERO");
        require(usdcAmount != 0, "AMOUNT_ZERO");
        require(usdcAmount <= maxUsdcPerSettlement, "SETTLEMENT_TOO_LARGE");

        address subjectTreasury = _requireRegisteredSubjectSplitter(subjectId);
        require(
            IERC20SupplyMinimal(usdc).balanceOf(address(this)) >= usdcAmount, "USDC_NOT_RECEIVED"
        );

        usdc.forceApprove(regentRevenueStaking, usdcAmount);
        depositedUsdc = IRegentRevenueStakingMinimal(regentRevenueStaking)
            .depositUSDC(usdcAmount, subjectId, sourceRef);
        require(depositedUsdc == usdcAmount, "STAKING_DEPOSIT_INEXACT");

        totalUsdcSettled += usdcAmount;
        totalUsdcDepositedToRegentStaking += depositedUsdc;

        emit ProtocolFeeDepositedToRegentStaking(
            subjectId, msg.sender, subjectTreasury, usdcAmount, depositedUsdc, sourceRef
        );
    }

    function setMaxUsdcPerSettlement(uint256 newAmount) external onlyOwner {
        require(newAmount != 0, "MAX_SETTLEMENT_ZERO");
        uint256 previous = maxUsdcPerSettlement;
        maxUsdcPerSettlement = newAmount;
        emit MaxUsdcPerSettlementSet(previous, newAmount);
    }

    function _requireRegisteredSubjectSplitter(bytes32 subjectId)
        internal
        view
        returns (address treasurySafe)
    {
        ISubjectRegistry.SubjectConfig memory cfg =
            ISubjectRegistry(subjectRegistry).getSubject(subjectId);
        require(cfg.splitter == msg.sender, "ONLY_SUBJECT_SPLITTER");
        treasurySafe = cfg.treasurySafe;
    }

    function _isProtectedToken(address token) internal view override returns (bool) {
        return token == usdc;
    }
}
