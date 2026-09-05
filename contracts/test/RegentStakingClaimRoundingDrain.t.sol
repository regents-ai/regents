// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, stdError} from "forge-std/Test.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";

/// @notice Characterization of the deployed RegentRevenueStaking claim-rounding behavior.
///
/// A per-account `_sync` floors once over the SUM of several deposits' accumulator deltas, so a
/// staker's merged claimable can exceed the per-deposit `creditedToStakers` floors by a wei-scale
/// rounding overage. `_recordUsdcClaim` covers that overage out of `treasuryResidualUsdc`.
///
/// The deployed contract reserves nothing against that draw, so a treasury withdrawal of the full
/// residual can leave an affected claim unable to settle. These tests pin that behavior as it is
/// live on Base rather than as anyone would prefer it: the drain is permitted, and the claim then
/// reverts on arithmetic underflow until residual USDC is restored. It is a bounded
/// claim-availability risk, not reentrancy and not fund loss. Do not "fix" this file; a fix is a
/// redeploy, and the source here must keep matching what is deployed.
contract RegentStakingClaimRoundingDrainTest is Test {
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

    /// @dev Two deposits WITHOUT the staker syncing in between: the later single `_sync` floors
    ///      over the SUM of both accumulator deltas, which is what creates the overage.
    function _depositTwiceAndMeasureOverage()
        internal
        returns (uint256 previewClaim, uint256 overage)
    {
        _deposit(100e18);
        _deposit(100e18);

        previewClaim = staking.previewClaimableUSDC(STAKER);
        uint256 outstandingCredit =
            staking.totalUsdcCreditedToStakers() - staking.totalClaimedUsdc();
        assertGt(previewClaim, outstandingCredit, "no overage -> scenario not triggered");
        overage = previewClaim - outstandingCredit;
        assertGt(overage, 0, "expected a rounding overage");
    }

    function testTreasuryMayDrainTheResidualThatBacksTheOverage() external {
        _stakeFull();
        (, uint256 overage) = _depositTwiceAndMeasureOverage();

        uint256 residual = staking.treasuryResidualUsdc();
        assertGt(residual, overage, "residual should exceed the overage in this scenario");

        // The deployed contract holds nothing back: the whole residual is withdrawable, including
        // the dust the staker accounting still counts as claimable.
        vm.prank(TREASURY);
        staking.withdrawTreasuryResidual(residual, TREASURY);
        assertEq(staking.treasuryResidualUsdc(), 0, "residual fully drained");
    }

    function testClaimRevertsAfterTheTreasuryDrainsTheFullResidual() external {
        _stakeFull();
        _depositTwiceAndMeasureOverage();

        uint256 residual = staking.treasuryResidualUsdc();
        vm.prank(TREASURY);
        staking.withdrawTreasuryResidual(residual, TREASURY);

        // `_recordUsdcClaim` covers the overage out of `treasuryResidualUsdc`, which is now zero,
        // so the subtraction underflows and the claim cannot settle.
        vm.prank(STAKER);
        vm.expectRevert(stdError.arithmeticError);
        staking.claimUSDC(STAKER);
    }

    function testClaimSucceedsWhenResidualNotDrained() external {
        _stakeFull();
        (uint256 previewClaim,) = _depositTwiceAndMeasureOverage();

        vm.prank(STAKER);
        uint256 claimed = staking.claimUSDC(STAKER);
        assertEq(claimed, previewClaim, "staker claims full merged reward");
        assertEq(usdc.balanceOf(STAKER), previewClaim);
    }

    /// @dev The shortfall does not heal. `treasuryResidualUsdc` is only ever increased by
    ///      `_recordRevenue`, and every path into it (`depositUSDC`, `redepositSurplusUSDC`)
    ///      raises the aggregate rounding overage by the same wei, so the residual never catches
    ///      up with what the claim needs.
    function testFurtherDepositsDoNotUnblockTheClaim() external {
        _stakeFull();
        _depositTwiceAndMeasureOverage();

        uint256 residual = staking.treasuryResidualUsdc();
        vm.prank(TREASURY);
        staking.withdrawTreasuryResidual(residual, TREASURY);

        uint256[8] memory amounts = [uint256(1e18), 3e18, 7e18, 13e18, 999e18, 1, 7, 1e6];
        for (uint256 i = 0; i < amounts.length; i++) {
            _deposit(amounts[i]);

            uint256 previewClaim = staking.previewClaimableUSDC(STAKER);
            uint256 outstandingCredit =
                staking.totalUsdcCreditedToStakers() - staking.totalClaimedUsdc();
            uint256 overage = previewClaim - outstandingCredit;

            assertGt(overage, staking.treasuryResidualUsdc(), "residual never catches the overage");

            vm.prank(STAKER);
            vm.expectRevert(stdError.arithmeticError);
            staking.claimUSDC(STAKER);
        }
    }
}
