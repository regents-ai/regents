// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";
import {TransferFeeERC20Mock} from "test/mocks/TransferFeeERC20Mock.sol";

contract RegentRevenueStakingTest is Test {
    uint256 internal constant REGENT = 1e18;
    uint256 internal constant USDC = 1e6;
    uint256 internal constant REVENUE_SHARE_SUPPLY_DENOMINATOR = 1000 * REGENT;
    uint16 internal constant MAX_APR_BPS = 2000;

    address internal constant OWNER = address(0xA11CE);
    address internal constant TREASURY = address(0xBEEF);
    address internal constant ALICE = address(0xA1);
    address internal constant BOB = address(0xB2);
    address internal constant CAROL = address(0xC3);
    address internal constant FUNDER = address(0xF00D);

    MintableBurnableERC20Mock internal regent;
    MintableBurnableERC20Mock internal usdc;
    RegentRevenueStaking internal staking;

    event AccountSynced(address indexed account);

    function setUp() external {
        regent = new MintableBurnableERC20Mock("Regent", "REGENT", 18);
        usdc = new MintableBurnableERC20Mock("USD Coin", "USDC", 6);

        staking = new RegentRevenueStaking(
            address(regent), address(usdc), TREASURY, REVENUE_SHARE_SUPPLY_DENOMINATOR, OWNER
        );

        regent.mint(ALICE, 200 * REGENT);
        regent.mint(BOB, 300 * REGENT);
        regent.mint(CAROL, 500 * REGENT);
        regent.mint(FUNDER, 10_000 * REGENT);
    }

    function testSyncEmitsAccountSynced() external {
        vm.expectEmit(true, false, false, true, address(staking));
        emit AccountSynced(ALICE);

        staking.sync(ALICE);
    }

    function testSingleStakerDepositAndClaimUsesFixedSupplyDenominator() external {
        _stake(ALICE, 200 * REGENT);

        usdc.mint(address(this), 1000 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(1000 * USDC, bytes32("manual"), bytes32("round-1"));

        assertEq(staking.totalUsdcReceived(), 1000 * USDC);
        assertEq(staking.directDepositUsdc(), 1000 * USDC);
        assertEq(staking.previewClaimableUSDC(ALICE), 200 * USDC);
        assertEq(staking.treasuryResidualUsdc(), 800 * USDC);

        vm.prank(ALICE);
        uint256 claimed = staking.claimUSDC(ALICE);

        assertEq(claimed, 200 * USDC);
        assertEq(usdc.balanceOf(ALICE), 200 * USDC);
        assertEq(staking.previewClaimableUSDC(ALICE), 0);
    }

    function testDirectTransferCreatesSurplusButNoClaimableUsdc() external {
        _stake(ALICE, 200 * REGENT);

        usdc.mint(address(staking), 1000 * USDC);

        assertEq(staking.surplusUsdc(), 1000 * USDC);
        assertEq(staking.reservedUsdc(), 0);
        assertEq(staking.previewClaimableUSDC(ALICE), 0);
        assertEq(staking.totalUsdcReceived(), 0);
    }

    function testRedepositSurplusCreditsStakersAndTreasury() external {
        _stake(ALICE, 200 * REGENT);
        usdc.mint(address(staking), 1000 * USDC);

        vm.prank(OWNER);
        staking.redepositSurplusUSDC(1000 * USDC, bytes32("surplus"), bytes32("manual"));

        assertEq(staking.totalUsdcReceived(), 1000 * USDC);
        assertEq(staking.surplusRedepositUsdc(), 1000 * USDC);
        assertEq(staking.totalSurplusUsdcRedeposited(), 1000 * USDC);
        assertEq(staking.totalUsdcCreditedToStakers(), 200 * USDC);
        assertEq(staking.previewClaimableUSDC(ALICE), 200 * USDC);
        assertEq(staking.treasuryResidualUsdc(), 800 * USDC);
        assertEq(staking.reservedUsdc(), 1000 * USDC);
        assertEq(staking.surplusUsdc(), 0);
    }

    function testSweepSurplusCannotWithdrawReservedStakerRewardsOrTreasuryResidual() external {
        _stake(ALICE, 200 * REGENT);

        usdc.mint(address(this), 1000 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(1000 * USDC, bytes32("manual"), bytes32("round-1"));

        assertEq(staking.reservedUsdc(), 1000 * USDC);
        assertEq(staking.surplusUsdc(), 0);

        vm.prank(OWNER);
        vm.expectRevert("SURPLUS_BALANCE_LOW");
        staking.sweepSurplusUSDC(1, TREASURY);

        usdc.mint(address(staking), 10 * USDC);

        vm.prank(TREASURY);
        staking.sweepSurplusUSDC(10 * USDC, TREASURY);

        assertEq(usdc.balanceOf(TREASURY), 10 * USDC);
        assertEq(staking.reservedUsdc(), 1000 * USDC);
        assertEq(staking.totalSurplusUsdcSwept(), 10 * USDC);
    }

    function testClaimUsdcReducesReservedUsdc() external {
        _stake(ALICE, 200 * REGENT);
        usdc.mint(address(staking), 1000 * USDC);

        vm.prank(OWNER);
        staking.redepositSurplusUSDC(1000 * USDC, bytes32("surplus"), bytes32("manual"));

        assertEq(staking.reservedUsdc(), 1000 * USDC);

        vm.prank(ALICE);
        staking.claimUSDC(ALICE);

        assertEq(staking.totalClaimedUsdc(), 200 * USDC);
        assertEq(staking.reservedUsdc(), 800 * USDC);
        assertEq(usdc.balanceOf(address(staking)), 800 * USDC);
    }

    function testRedepositSurplusUsesFixedDenominatorModel() external {
        _stake(ALICE, 200 * REGENT);
        _stake(BOB, 300 * REGENT);
        usdc.mint(address(staking), 1000 * USDC);

        vm.prank(OWNER);
        staking.redepositSurplusUSDC(1000 * USDC, bytes32("surplus"), bytes32("manual"));

        assertEq(staking.previewClaimableUSDC(ALICE), 200 * USDC);
        assertEq(staking.previewClaimableUSDC(BOB), 300 * USDC);
        assertEq(staking.treasuryResidualUsdc(), 500 * USDC);
        assertEq(staking.totalUsdcCreditedToStakers(), 500 * USDC);
    }

    function testMultipleStakersReceiveProRataShareAcrossDeposits() external {
        _stake(ALICE, 200 * REGENT);
        _stake(BOB, 300 * REGENT);

        usdc.mint(address(this), 1000 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(1000 * USDC, bytes32("manual"), bytes32("round-1"));

        assertEq(staking.previewClaimableUSDC(ALICE), 200 * USDC);
        assertEq(staking.previewClaimableUSDC(BOB), 300 * USDC);
        assertEq(staking.treasuryResidualUsdc(), 500 * USDC);

        _stake(CAROL, 500 * REGENT);

        usdc.mint(address(this), 500 * USDC);
        staking.depositUSDC(500 * USDC, bytes32("manual"), bytes32("round-2"));

        assertEq(staking.previewClaimableUSDC(ALICE), 300 * USDC);
        assertEq(staking.previewClaimableUSDC(BOB), 450 * USDC);
        assertEq(staking.previewClaimableUSDC(CAROL), 250 * USDC);
        assertEq(staking.treasuryResidualUsdc(), 500 * USDC);
    }

    function testBurningTokensElsewhereDoesNotChangeUsdcParticipation() external {
        _stake(ALICE, 200 * REGENT);

        usdc.mint(address(this), 1000 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(1000 * USDC, bytes32("manual"), bytes32("round-1"));
        uint256 aliceBefore = staking.previewClaimableUSDC(ALICE);

        regent.burn(CAROL, 500 * REGENT);

        usdc.mint(address(this), 1000 * USDC);
        staking.depositUSDC(1000 * USDC, bytes32("manual"), bytes32("round-2"));

        uint256 aliceAfter = staking.previewClaimableUSDC(ALICE) - aliceBefore;
        assertEq(aliceAfter, 200 * USDC);
    }

    function testNoStakersLeavesFullDepositInTreasuryResidual() external {
        usdc.mint(address(this), 200 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(200 * USDC, bytes32("manual"), bytes32("round-1"));

        assertEq(staking.previewClaimableUSDC(ALICE), 0);
        assertEq(staking.treasuryResidualUsdc(), 200 * USDC);
    }

    function testFuzzSingleStakerUsdcAccountingConservesDeposits(
        uint256 stakeAmount,
        uint256 depositAmount
    ) external {
        stakeAmount = bound(stakeAmount, 1, REVENUE_SHARE_SUPPLY_DENOMINATOR);
        depositAmount = bound(depositAmount, 1, 1_000_000_000 * USDC);

        regent.mint(ALICE, stakeAmount);
        _stake(ALICE, stakeAmount);

        usdc.mint(address(this), depositAmount);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(depositAmount, bytes32("fuzz"), bytes32("single"));

        uint256 tracked = staking.treasuryResidualUsdc() + staking.previewClaimableUSDC(ALICE);
        assertEq(usdc.balanceOf(address(staking)), tracked);
        assertEq(staking.totalUsdcReceived(), depositAmount);
        assertEq(staking.directDepositUsdc(), depositAmount);
    }

    function testFuzzUsdcRewardsUseFixedSupplyDenominator(
        uint256 aliceStake,
        uint256 bobStake,
        uint256 depositAmount
    ) external {
        aliceStake = bound(aliceStake, 1, REVENUE_SHARE_SUPPLY_DENOMINATOR / 2);
        bobStake = bound(bobStake, 1, REVENUE_SHARE_SUPPLY_DENOMINATOR - aliceStake);
        depositAmount = bound(depositAmount, 1, 1_000_000_000 * USDC);

        regent.mint(ALICE, aliceStake);
        regent.mint(BOB, bobStake);
        _stake(ALICE, aliceStake);
        _stake(BOB, bobStake);

        usdc.mint(address(this), depositAmount);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(depositAmount, bytes32("fuzz"), bytes32("denominator"));

        uint256 deltaAcc =
            depositAmount * staking.ACC_PRECISION() / REVENUE_SHARE_SUPPLY_DENOMINATOR;
        uint256 expectedAlice = aliceStake * deltaAcc / staking.ACC_PRECISION();
        uint256 expectedBob = bobStake * deltaAcc / staking.ACC_PRECISION();
        uint256 creditedToStakers = deltaAcc * (aliceStake + bobStake) / staking.ACC_PRECISION();
        uint256 expectedTreasury = depositAmount - creditedToStakers;

        assertEq(staking.previewClaimableUSDC(ALICE), expectedAlice);
        assertEq(staking.previewClaimableUSDC(BOB), expectedBob);
        assertEq(staking.treasuryResidualUsdc(), expectedTreasury);
        assertLe(expectedAlice + expectedBob, creditedToStakers);
    }

    function testTreasuryWithdrawalIsRestricted() external {
        _stake(ALICE, 100 * REGENT);
        usdc.mint(address(this), 100 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(100 * USDC, bytes32("manual"), bytes32("round-1"));

        vm.expectRevert("ONLY_TREASURY");
        vm.prank(ALICE);
        staking.withdrawTreasuryResidual(10 * USDC, TREASURY);

        vm.prank(TREASURY);
        staking.withdrawTreasuryResidual(90 * USDC, TREASURY);

        assertEq(usdc.balanceOf(TREASURY), 90 * USDC);
        assertEq(staking.treasuryResidualUsdc(), 0);
    }

    function testTreasuryWithdrawalRejectsZeroAmount() external {
        vm.prank(TREASURY);
        vm.expectRevert("AMOUNT_ZERO");
        staking.withdrawTreasuryResidual(0, TREASURY);
    }

    function testRejectsSelfRecipients() external {
        _stake(ALICE, 100 * REGENT);
        usdc.mint(address(this), 100 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(100 * USDC, bytes32("manual"), bytes32("round-1"));
        _fundRegentRewards(1000 * REGENT);

        vm.expectRevert("RECEIVER_IS_SELF");
        vm.prank(ALICE);
        staking.stake(REGENT, address(staking));

        vm.expectRevert("RECIPIENT_IS_SELF");
        vm.prank(ALICE);
        staking.claimUSDC(address(staking));

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);
        vm.warp(block.timestamp + 30 days);

        vm.expectRevert("RECIPIENT_IS_SELF");
        vm.prank(ALICE);
        staking.claimRegent(address(staking));

        vm.expectRevert("RECIPIENT_IS_SELF");
        vm.prank(ALICE);
        staking.unstake(REGENT, address(staking));

        vm.expectRevert("TREASURY_IS_SELF");
        vm.prank(OWNER);
        staking.setTreasuryRecipient(address(staking));
    }

    function testConstructorRejectsRegentTokenAsUsdc() external {
        vm.expectRevert("STAKE_TOKEN_IS_USDC");
        new RegentRevenueStaking(
            address(regent), address(regent), TREASURY, REVENUE_SHARE_SUPPLY_DENOMINATOR, OWNER
        );
    }

    function testTreasuryWithdrawalRejectsZeroAndRecipientSelf() external {
        usdc.mint(address(this), 100 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(100 * USDC, bytes32("manual"), bytes32("round-1"));

        vm.startPrank(TREASURY);
        vm.expectRevert("AMOUNT_ZERO");
        staking.withdrawTreasuryResidual(0, TREASURY);

        vm.expectRevert("RECIPIENT_IS_SELF");
        staking.withdrawTreasuryResidual(1 * USDC, address(staking));
        vm.stopPrank();
    }

    function testUsdcClaimAndSurplusSweepRejectRecipientSelf() external {
        _stake(ALICE, 200 * REGENT);
        usdc.mint(address(this), 1000 * USDC);
        usdc.approve(address(staking), type(uint256).max);
        staking.depositUSDC(1000 * USDC, bytes32("manual"), bytes32("round-1"));
        usdc.mint(address(staking), 10 * USDC);

        vm.prank(ALICE);
        vm.expectRevert("RECIPIENT_IS_SELF");
        staking.claimUSDC(address(staking));

        vm.prank(OWNER);
        vm.expectRevert("RECIPIENT_IS_SELF");
        staking.sweepSurplusUSDC(10 * USDC, address(staking));
    }

    function testStakeTokenExitPathsRejectRecipientSelf() external {
        _stake(ALICE, 100 * REGENT);
        _fundRegentRewards(1000 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);
        vm.warp(block.timestamp + 30 days);

        vm.prank(ALICE);
        vm.expectRevert("RECIPIENT_IS_SELF");
        staking.claimRegent(address(staking));

        vm.prank(ALICE);
        vm.expectRevert("RECIPIENT_IS_SELF");
        staking.unstake(1 * REGENT, address(staking));
    }

    function testEmissionAprAccruesAndClaimTransfersRegent() external {
        _stake(ALICE, 100 * REGENT);
        _fundRegentRewards(1000 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);

        vm.warp(block.timestamp + 30 days);

        uint256 expected = _expectedEmission(100 * REGENT, MAX_APR_BPS, 30 days);
        assertEq(staking.previewClaimableRegent(ALICE), expected);

        vm.prank(ALICE);
        uint256 claimed = staking.claimRegent(ALICE);

        assertEq(claimed, expected);
        assertEq(staking.totalClaimedRegent(), expected);
        assertEq(regent.balanceOf(ALICE), 100 * REGENT + expected);
        assertEq(staking.previewClaimableRegent(ALICE), 0);
    }

    function testStakeRejectsInboundFeeOnTransferToken() external {
        TransferFeeERC20Mock taxed =
            new TransferFeeERC20Mock("Taxed Regent", "tREG", 18, address(0));
        RegentRevenueStaking taxedStaking = new RegentRevenueStaking(
            address(taxed), address(usdc), TREASURY, REVENUE_SHARE_SUPPLY_DENOMINATOR, OWNER
        );

        taxed.setFeeBps(500);
        taxed.setFeeTriggers(address(taxedStaking), false, true);
        taxed.mint(ALICE, 100 * REGENT);

        vm.startPrank(ALICE);
        taxed.approve(address(taxedStaking), type(uint256).max);
        vm.expectRevert("STAKE_TOKEN_IN_EXACT");
        taxedStaking.stake(100 * REGENT, ALICE);
        vm.stopPrank();
    }

    function testClaimRejectsOutboundFeeOnTransferToken() external {
        TransferFeeERC20Mock taxed =
            new TransferFeeERC20Mock("Taxed Regent", "tREG", 18, address(0));
        RegentRevenueStaking taxedStaking = new RegentRevenueStaking(
            address(taxed), address(usdc), TREASURY, REVENUE_SHARE_SUPPLY_DENOMINATOR, OWNER
        );

        taxed.mint(ALICE, 100 * REGENT);
        taxed.mint(FUNDER, 1000 * REGENT);

        vm.startPrank(ALICE);
        taxed.approve(address(taxedStaking), type(uint256).max);
        taxedStaking.stake(100 * REGENT, ALICE);
        vm.stopPrank();

        vm.startPrank(FUNDER);
        taxed.approve(address(taxedStaking), type(uint256).max);
        taxedStaking.fundRegentRewards(1000 * REGENT);
        vm.stopPrank();

        vm.prank(OWNER);
        taxedStaking.setEmissionAprBps(MAX_APR_BPS);
        vm.warp(block.timestamp + 30 days);

        taxed.setFeeBps(500);
        taxed.setFeeTriggers(address(taxedStaking), true, false);

        vm.prank(ALICE);
        vm.expectRevert("STAKE_TOKEN_OUT_EXACT");
        taxedStaking.claimRegent(ALICE);
    }

    function testAprChangeMidstreamSettlesUsingBothRates() external {
        _stake(ALICE, 1000 * REGENT / 10);
        _fundRegentRewards(1000 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(1500);

        vm.warp(150 days);

        vm.prank(OWNER);
        staking.setEmissionAprBps(1000);

        vm.warp(210 days);

        uint256 expected = _expectedEmission(100 * REGENT, 1500, 150 days)
            + _expectedEmission(100 * REGENT, 1000, 60 days);
        assertApproxEqAbs(staking.previewClaimableRegent(ALICE), expected, 1e14);
    }

    function testNoStakerIntervalAccruesZeroRegentEmissions() external {
        _fundRegentRewards(1000 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);

        vm.warp(block.timestamp + 30 days);

        assertEq(staking.totalEmittedRegent(), 0);

        _stake(ALICE, 100 * REGENT);
        assertEq(staking.previewClaimableRegent(ALICE), 0);
    }

    function testClaimRegentRevertsWhenInventoryIsShort() external {
        _stake(ALICE, 100 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);

        vm.warp(block.timestamp + 365 days);

        assertGt(staking.previewClaimableRegent(ALICE), 0);
        assertEq(staking.previewFundedClaimableRegent(ALICE), 0);

        vm.expectRevert("REWARD_INVENTORY_LOW");
        vm.prank(ALICE);
        staking.claimRegent(ALICE);
    }

    function testClaimAndRestakeRegentRevertsWhenInventoryIsShort() external {
        _stake(ALICE, 100 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);

        vm.warp(block.timestamp + 365 days);

        assertGt(staking.previewClaimableRegent(ALICE), 0);
        assertEq(staking.previewFundedClaimableRegent(ALICE), 0);

        vm.expectRevert("REWARD_INVENTORY_LOW");
        vm.prank(ALICE);
        staking.claimAndRestakeRegent();
    }

    function testRegentClaimsRecoverAfterFundingArrivesLater() external {
        _stake(ALICE, 200 * REGENT);
        _stake(BOB, 300 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);

        vm.warp(block.timestamp + 365 days);

        uint256 aliceExpected = _expectedEmission(200 * REGENT, MAX_APR_BPS, 365 days);
        uint256 bobExpected = _expectedEmission(300 * REGENT, MAX_APR_BPS, 365 days);

        _fundRegentRewards(bobExpected);

        assertEq(staking.previewFundedClaimableRegent(BOB), bobExpected);

        vm.prank(BOB);
        uint256 bobClaim = staking.claimRegent(BOB);
        assertEq(bobClaim, bobExpected);

        assertEq(staking.previewFundedClaimableRegent(ALICE), 0);
        vm.prank(ALICE);
        vm.expectRevert("REWARD_INVENTORY_LOW");
        staking.claimRegent(ALICE);

        _fundRegentRewards(aliceExpected);

        vm.prank(ALICE);
        uint256 aliceClaim = staking.claimRegent(ALICE);
        assertEq(aliceClaim, aliceExpected);
        assertEq(staking.previewClaimableRegent(ALICE), 0);
    }

    function testClaimAndRestakeRegentCompoundsIntoPrincipal() external {
        _stake(ALICE, 100 * REGENT);
        _fundRegentRewards(1000 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);

        vm.warp(block.timestamp + 30 days);

        uint256 expected = _expectedEmission(100 * REGENT, MAX_APR_BPS, 30 days);

        vm.prank(ALICE);
        uint256 compounded = staking.claimAndRestakeRegent();

        assertEq(compounded, expected);
        assertEq(staking.totalClaimedRegent(), expected);
        assertEq(staking.stakedBalance(ALICE), 100 * REGENT + expected);
        assertEq(staking.totalStaked(), 100 * REGENT + expected);
        assertEq(staking.previewClaimableRegent(ALICE), 0);
        assertEq(regent.balanceOf(ALICE), 100 * REGENT);
    }

    function testStakeRevertsWhenCapWouldBeExceeded() external {
        _stake(ALICE, 200 * REGENT);
        _stake(BOB, 300 * REGENT);
        _stake(CAROL, 500 * REGENT);

        regent.mint(address(0xD4), REGENT);

        vm.startPrank(address(0xD4));
        regent.approve(address(staking), type(uint256).max);
        vm.expectRevert("STAKE_CAP_EXCEEDED");
        staking.stake(REGENT, address(0xD4));
        vm.stopPrank();
    }

    function testClaimAndRestakeRegentRevertsWhenCapWouldBeExceeded() external {
        MintableBurnableERC20Mock smallRegent =
            new MintableBurnableERC20Mock("Small Regent", "sREGENT", 18);
        RegentRevenueStaking smallStaking = new RegentRevenueStaking(
            address(smallRegent), address(usdc), TREASURY, 3 * REGENT, OWNER
        );

        address[3] memory stakers = [ALICE, BOB, CAROL];
        for (uint256 i = 0; i < stakers.length; ++i) {
            smallRegent.mint(stakers[i], REGENT);
            vm.startPrank(stakers[i]);
            smallRegent.approve(address(smallStaking), type(uint256).max);
            smallStaking.stake(REGENT, stakers[i]);
            vm.stopPrank();
        }

        smallRegent.mint(FUNDER, 100 * REGENT);
        vm.startPrank(FUNDER);
        smallRegent.approve(address(smallStaking), type(uint256).max);
        smallStaking.fundRegentRewards(100 * REGENT);
        vm.stopPrank();

        vm.prank(OWNER);
        smallStaking.setEmissionAprBps(MAX_APR_BPS);
        vm.warp(block.timestamp + 10 days);

        vm.prank(ALICE);
        vm.expectRevert("STAKE_CAP_EXCEEDED");
        smallStaking.claimAndRestakeRegent();
    }

    function testPauseBlocksFundingStakeAndRestakeButNotClaimsOrUnstake() external {
        _stake(ALICE, 100 * REGENT);
        usdc.mint(address(this), 1000 * USDC);
        usdc.approve(address(staking), 1000 * USDC);
        staking.depositUSDC(1000 * USDC, bytes32("manual"), bytes32("pause"));
        _fundRegentRewards(1000 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);

        vm.warp(block.timestamp + 30 days);

        vm.prank(OWNER);
        staking.setPaused(true);

        vm.prank(ALICE);
        uint256 usdcClaimed = staking.claimUSDC(ALICE);
        assertGt(usdcClaimed, 0);

        vm.prank(ALICE);
        uint256 claimed = staking.claimRegent(ALICE);
        assertGt(claimed, 0);

        vm.expectRevert("PAUSED");
        vm.prank(ALICE);
        staking.claimAndRestakeRegent();

        vm.expectRevert("PAUSED");
        vm.prank(ALICE);
        staking.stake(1 * REGENT, ALICE);

        vm.expectRevert("PAUSED");
        staking.depositUSDC(1 * USDC, bytes32("manual"), bytes32("round-1"));

        vm.expectRevert("PAUSED");
        vm.prank(FUNDER);
        staking.fundRegentRewards(1 * REGENT);

        vm.prank(ALICE);
        staking.unstake(50 * REGENT, ALICE);

        assertEq(staking.stakedBalance(ALICE), 50 * REGENT);
        assertEq(regent.balanceOf(ALICE), 150 * REGENT + claimed);
    }

    function testUnstakeStillWorksWhileRegentClaimsAreUnderfunded() external {
        _stake(ALICE, 100 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);

        vm.warp(block.timestamp + 365 days);

        vm.prank(ALICE);
        staking.unstake(50 * REGENT, ALICE);

        assertEq(staking.stakedBalance(ALICE), 50 * REGENT);
        assertEq(regent.balanceOf(ALICE), 150 * REGENT);
    }

    function testFundingIncreasesAvailableRewardInventoryWithoutChangingStake() external {
        _stake(ALICE, 100 * REGENT);
        uint256 initialInventory = staking.availableRegentRewardInventory();

        _fundRegentRewards(250 * REGENT);

        assertEq(staking.availableRegentRewardInventory(), initialInventory + 250 * REGENT);
        assertEq(staking.stakedBalance(ALICE), 100 * REGENT);
        assertEq(staking.totalFundedRegent(), 250 * REGENT);
    }

    function testDirectRegentTransferBecomesRewardPoolInventory() external {
        _stake(ALICE, 100 * REGENT);

        regent.mint(address(staking), 250 * REGENT);

        assertEq(staking.regentRewardPool(), 250 * REGENT);
        assertEq(staking.availableRegentRewardInventory(), 250 * REGENT);
        assertEq(staking.totalFundedRegent(), 0);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);
        vm.warp(block.timestamp + 30 days);

        uint256 claimable = staking.previewClaimableRegent(ALICE);
        assertGt(claimable, 0);
        assertLe(claimable, 250 * REGENT);

        vm.prank(ALICE);
        uint256 claimed = staking.claimRegent(ALICE);

        assertEq(claimed, claimable);
        assertEq(regent.balanceOf(ALICE), 100 * REGENT + claimable);
    }

    function testOwnerCanRefundRegentRewardPoolWithoutTouchingPrincipal() external {
        _stake(ALICE, 100 * REGENT);
        regent.mint(address(staking), 250 * REGENT);

        vm.prank(OWNER);
        staking.refundRegentRewardPool(75 * REGENT, FUNDER);

        assertEq(regent.balanceOf(FUNDER), 10_075 * REGENT);
        assertEq(staking.totalRewardTokenPoolRefunded(), 75 * REGENT);
        assertEq(staking.regentRewardPool(), 175 * REGENT);
        assertEq(regent.balanceOf(address(staking)), 275 * REGENT);

        vm.prank(ALICE);
        staking.unstake(100 * REGENT, ALICE);

        assertEq(regent.balanceOf(ALICE), 200 * REGENT);
        assertEq(regent.balanceOf(address(staking)), 175 * REGENT);
    }

    function testOwnerCannotRefundMoreThanRegentRewardPool() external {
        _stake(ALICE, 100 * REGENT);
        regent.mint(address(staking), 25 * REGENT);

        vm.prank(OWNER);
        vm.expectRevert("REWARD_POOL_LOW");
        staking.refundRegentRewardPool(26 * REGENT, FUNDER);

        assertEq(staking.regentRewardPool(), 25 * REGENT);
        assertEq(regent.balanceOf(address(staking)), 125 * REGENT);

        vm.prank(ALICE);
        staking.unstake(100 * REGENT, ALICE);

        assertEq(regent.balanceOf(ALICE), 200 * REGENT);
    }

    function testTreasuryCanSweepRegentRewardPoolWithoutTouchingPrincipal() external {
        _stake(ALICE, 100 * REGENT);
        _fundRegentRewards(50 * REGENT);
        regent.mint(address(staking), 25 * REGENT);

        assertEq(staking.regentRewardPool(), 75 * REGENT);
        assertEq(staking.sweepableRegentRewardPool(), 75 * REGENT);

        vm.prank(TREASURY);
        vm.expectRevert("REWARD_POOL_LOW");
        staking.sweepRegentRewardPool(76 * REGENT);

        vm.prank(TREASURY);
        staking.sweepRegentRewardPool(75 * REGENT);

        assertEq(staking.totalRewardTokenPoolSwept(), 75 * REGENT);
        assertEq(regent.balanceOf(TREASURY), 75 * REGENT);
        assertEq(staking.regentRewardPool(), 0);
        assertEq(regent.balanceOf(address(staking)), staking.totalStaked());

        vm.prank(ALICE);
        staking.unstake(100 * REGENT, ALICE);

        assertEq(regent.balanceOf(ALICE), 200 * REGENT);
        assertEq(regent.balanceOf(address(staking)), 0);
    }

    function testRewardPoolWithdrawalsCannotDrainAccruedRegentRewards() external {
        _stake(ALICE, 100 * REGENT);
        _fundRegentRewards(50 * REGENT);
        regent.mint(address(staking), 25 * REGENT);

        vm.prank(OWNER);
        staking.setEmissionAprBps(MAX_APR_BPS);
        vm.warp(block.timestamp + 30 days);

        uint256 owed = staking.previewClaimableRegent(ALICE);
        assertGt(owed, 0);
        assertEq(staking.reservedRegentRewards(), owed);
        assertEq(staking.sweepableRegentRewardPool(), 75 * REGENT - owed);

        vm.prank(TREASURY);
        vm.expectRevert("REWARD_POOL_LOW");
        staking.sweepRegentRewardPool(75 * REGENT);

        vm.prank(TREASURY);
        staking.sweepRegentRewardPool(75 * REGENT - owed);

        assertEq(staking.regentRewardPool(), owed);
        assertEq(staking.sweepableRegentRewardPool(), 0);

        vm.prank(ALICE);
        uint256 claimed = staking.claimRegent(ALICE);

        assertEq(claimed, owed);
        assertEq(regent.balanceOf(ALICE), 100 * REGENT + owed);
    }

    function testRewardPoolWithdrawalsRejectBadCallersAndRecipients() external {
        regent.mint(address(staking), 100 * REGENT);

        vm.prank(ALICE);
        vm.expectRevert("ONLY_TREASURY");
        staking.sweepRegentRewardPool(1 * REGENT);

        vm.prank(OWNER);
        vm.expectRevert("RECIPIENT_ZERO");
        staking.refundRegentRewardPool(1 * REGENT, address(0));

        vm.prank(OWNER);
        vm.expectRevert("RECIPIENT_IS_SELF");
        staking.refundRegentRewardPool(1 * REGENT, address(staking));

        vm.prank(OWNER);
        vm.expectRevert("AMOUNT_ZERO");
        staking.refundRegentRewardPool(0, FUNDER);
    }

    function testSurplusUsdcCanBeSwept() external {
        usdc.mint(address(staking), 100 * USDC);

        assertEq(staking.surplusUsdc(), 100 * USDC);

        vm.prank(TREASURY);
        staking.sweepSurplusUSDC(100 * USDC, TREASURY);

        assertEq(usdc.balanceOf(TREASURY), 100 * USDC);
        assertEq(staking.totalSurplusUsdcSwept(), 100 * USDC);
        assertEq(staking.surplusUsdc(), 0);
    }

    function testSurplusUsdcCanBeRedepositedIntoAccounting() external {
        _stake(ALICE, 200 * REGENT);
        usdc.mint(address(staking), 1000 * USDC);

        vm.prank(OWNER);
        staking.redepositSurplusUSDC(1000 * USDC, bytes32("surplus"), bytes32("manual-redeposit"));

        assertEq(staking.surplusUsdc(), 0);
        assertEq(staking.totalSurplusUsdcRedeposited(), 1000 * USDC);
        assertEq(staking.surplusRedepositUsdc(), 1000 * USDC);
        assertEq(staking.previewClaimableUSDC(ALICE), 200 * USDC);
        assertEq(staking.treasuryResidualUsdc(), 800 * USDC);
        assertEq(staking.reservedUsdc(), usdc.balanceOf(address(staking)));
    }

    function testLiabilityTracksMaterializedRoundedClaims() external {
        MintableBurnableERC20Mock smallRegent =
            new MintableBurnableERC20Mock("Small Regent", "sREGENT", 18);
        RegentRevenueStaking smallStaking = new RegentRevenueStaking(
            address(smallRegent), address(usdc), TREASURY, 3 * REGENT, OWNER
        );

        address[3] memory stakers = [ALICE, BOB, CAROL];
        for (uint256 i = 0; i < stakers.length; ++i) {
            smallRegent.mint(stakers[i], REGENT);
            vm.startPrank(stakers[i]);
            smallRegent.approve(address(smallStaking), type(uint256).max);
            smallStaking.stake(REGENT, stakers[i]);
            vm.stopPrank();
        }

        smallRegent.mint(FUNDER, 100 * REGENT);
        vm.startPrank(FUNDER);
        smallRegent.approve(address(smallStaking), type(uint256).max);
        smallStaking.fundRegentRewards(100 * REGENT);
        vm.stopPrank();

        vm.prank(OWNER);
        smallStaking.setEmissionAprBps(MAX_APR_BPS);
        vm.warp(block.timestamp + 10 days);

        for (uint256 i = 0; i < stakers.length; ++i) {
            smallStaking.sync(stakers[i]);
        }

        uint256 expectedLiability = smallStaking.previewClaimableRegent(ALICE)
            + smallStaking.previewClaimableRegent(BOB) + smallStaking.previewClaimableRegent(CAROL);
        assertEq(smallStaking.unclaimedRegentLiability(), expectedLiability);
    }

    function testClaimWithoutRewardsReturnsZero() external {
        _stake(ALICE, 100 * REGENT);

        vm.prank(ALICE);
        uint256 claimed = staking.claimUSDC(ALICE);

        assertEq(claimed, 0);
    }

    function testOwnerCanRescueUnsupportedAssetsButNotCanonicalOnes() external {
        MintableBurnableERC20Mock junk = new MintableBurnableERC20Mock("Junk", "JUNK", 18);
        junk.mint(address(staking), 4 * REGENT);
        vm.deal(address(staking), 1 ether);

        vm.startPrank(OWNER);
        staking.rescueUnsupportedToken(address(junk), 4 * REGENT, address(0x4444));
        staking.rescueNative(address(0x5555));
        vm.stopPrank();

        assertEq(junk.balanceOf(address(0x4444)), 4 * REGENT);
        assertEq(address(staking).balance, 0);
        assertEq(address(0x5555).balance, 1 ether);

        vm.prank(OWNER);
        vm.expectRevert("PROTECTED_TOKEN");
        staking.rescueUnsupportedToken(address(usdc), 1, TREASURY);
    }

    function _stake(address account, uint256 amount) internal {
        vm.startPrank(account);
        regent.approve(address(staking), type(uint256).max);
        staking.stake(amount, account);
        vm.stopPrank();
    }

    function _fundRegentRewards(uint256 amount) internal {
        vm.startPrank(FUNDER);
        regent.approve(address(staking), type(uint256).max);
        staking.fundRegentRewards(amount);
        vm.stopPrank();
    }

    function _expectedEmission(uint256 amount, uint256 aprBps, uint256 elapsed)
        internal
        pure
        returns (uint256)
    {
        return (amount * aprBps * elapsed) / 10_000 / 365 days;
    }
}
