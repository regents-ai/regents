// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";

/// @notice Regression for the RegentRevenueStaking claim-rounding reserve (regent-2vmz).
///
/// A per-account `_sync` floors once over the SUM of several deposits' accumulator deltas, so a
/// staker's merged claimable can exceed the per-deposit `creditedToStakers` floors by a wei-scale
/// rounding overage. That overage is now reserved in `claimRoundingReserveUsdc` — a subset of
/// `treasuryResidualUsdc` that `withdrawTreasuryResidual` may not touch — so the treasury can never
/// drain dust the staker accounting still counts as claimable, and a claim can never underflow.
contract RegentStakingClaimRoundingReserveTest is Test {
    // Fully-staked regime: totalStaked == revenueShareSupplyDenominator == 7e18. This 7e18 /
    // two-100e18-deposit rounding scenario is known to leave a 1-wei accumulator overage.
    uint256 internal constant DENOM = 7e18;

    address internal constant OWNER = address(0xA11CE);
    address internal constant TREASURY = address(0xBEEF);
    address internal constant STAKER = address(0x5741);

    MintableBurnableERC20Mock internal regent;
    MintableBurnableERC20Mock internal usdc;
    RegentRevenueStaking internal staking;

    function setUp() external {
        regent = new MintableBurnableERC20Mock("Regent", "REGENT", 18);
        usdc = new MintableBurnableERC20Mock("USD Coin", "USDC", 6);
        staking = new RegentRevenueStaking(address(regent), address(usdc), TREASURY, DENOM, OWNER);
    }

    function _stakeFull() internal {
        regent.mint(STAKER, DENOM);
        vm.prank(STAKER);
        regent.approve(address(staking), DENOM);
        vm.prank(STAKER);
        staking.stake(DENOM, STAKER);
    }

    function _deposit(uint256 amount) internal {
        usdc.mint(address(this), amount);
        usdc.approve(address(staking), amount);
        staking.depositUSDC(amount, bytes32("fee"), bytes32("ref"));
    }

    function testClaimSucceedsAfterTreasuryDrainsWithdrawableResidual() external {
        _stakeFull();

        // Two deposits WITHOUT the staker syncing in between: the later single `_sync` floors over
        // the SUM of both accumulator deltas — the trigger for the rounding overage.
        _deposit(100e18);
        _deposit(100e18);

        // A rounding overage must actually exist for this regression to be meaningful.
        uint256 previewClaim = staking.previewClaimableUSDC(STAKER);
        uint256 outstandingCredit =
            staking.totalUsdcCreditedToStakers() - staking.totalClaimedUsdc();
        assertGt(previewClaim, outstandingCredit, "no overage -> scenario not triggered");
        uint256 overage = previewClaim - outstandingCredit;
        assertGt(overage, 0, "expected a rounding overage");

        // The overage is reserved: it is a subset of the residual that the treasury cannot take.
        uint256 residual = staking.treasuryResidualUsdc();
        uint256 reserve = staking.claimRoundingReserveUsdc();
        assertEq(reserve, overage, "reserve equals the rounding overage owed to stakers");
        assertGt(residual, reserve, "residual holds withdrawable funds beyond the reserve");

        // Draining the FULL residual (reserve included) is rejected...
        vm.prank(TREASURY);
        vm.expectRevert("TREASURY_RESERVED_FOR_STAKERS");
        staking.withdrawTreasuryResidual(residual, TREASURY);

        // ...but the treasury may still take everything above the reserve.
        uint256 withdrawable = residual - reserve;
        vm.prank(TREASURY);
        staking.withdrawTreasuryResidual(withdrawable, TREASURY);
        assertEq(staking.treasuryResidualUsdc(), reserve, "only the staker reserve remains");

        // The staker's full ~200e18 claim now succeeds: the reserved dust backs the overage.
        vm.prank(STAKER);
        uint256 claimed = staking.claimUSDC(STAKER);
        assertEq(claimed, previewClaim, "staker claims full merged reward");
        assertEq(usdc.balanceOf(STAKER), previewClaim);
        assertEq(staking.claimRoundingReserveUsdc(), 0, "reserve consumed by the claim overage");
    }

    function testClaimSucceedsWhenResidualNotDrained() external {
        _stakeFull();
        _deposit(100e18);
        _deposit(100e18);

        vm.prank(STAKER);
        uint256 claimed = staking.claimUSDC(STAKER);
        assertGt(claimed, 0, "claim should succeed when residual is intact");
    }
}
