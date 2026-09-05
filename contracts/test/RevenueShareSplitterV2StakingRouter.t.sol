// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {RegentStakingRevenueRouter} from "src/autolaunch/revenue/RegentStakingRevenueRouter.sol";
import {RevenueIngressAccount} from "src/autolaunch/revenue/RevenueIngressAccount.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {TransferFeeERC20Mock} from "test/mocks/TransferFeeERC20Mock.sol";

contract SubjectFeeVaultHarness {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;

    address public immutable registryContract;
    address public immutable canonicalLaunchToken;
    address public constant canonicalQuoteToken = REGENT;

    constructor(address registryContract_, address launchToken_) {
        registryContract = registryContract_;
        canonicalLaunchToken = launchToken_;
    }

    function fund(RevenueShareSplitterV2 splitter, uint256 amount)
        external
        returns (uint256 received)
    {
        MintableERC20Mock(REGENT).approve(address(splitter), amount);
        received = splitter.fundRegentRewards(amount);
        MintableERC20Mock(REGENT).approve(address(splitter), 0);
    }
}

contract RevenueShareSplitterV2StakingRouterTest is Test {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    bytes32 internal constant SUBJECT_ID = keccak256("v2-subject");
    address internal constant TREASURY = address(0x1111);
    address internal constant STAKER = address(0x3333);
    address internal constant STAKER_TWO = address(0x4444);
    uint256 internal constant SUPPLY_DENOMINATOR = 1000e18;
    uint256 internal constant HUNDRED_USDC = 100e6;
    uint256 internal constant PROTOCOL_SKIM = 2e6;
    // The full post-skim subject lane is staker-eligible under the default 100% share.
    uint256 internal constant SUBJECT_LANE = 98e6;
    uint256 internal constant STAKER_CLAIM = 9800e3;
    uint256 internal constant TREASURY_RESIDUAL = 88_200e3;

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal regent;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    RevenueIngressFactory internal ingressFactory;
    RegentRevenueStaking internal staking;
    RegentStakingRevenueRouter internal router;
    RevenueShareSplitterV2 internal splitter;
    SubjectFeeVaultHarness internal feeVault;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        MintableERC20Mock regentImplementation = new MintableERC20Mock("REGENT", "REGENT");
        vm.etch(REGENT, address(regentImplementation).code);
        regent = MintableERC20Mock(REGENT);
        stakeToken = new MintableERC20Mock("Agent", "AGENT");
        subjectRegistry = new SubjectRegistry(address(this), address(0xA11CE), address(0x600D));
        ingressFactory =
            new RevenueIngressFactory(address(usdc), address(subjectRegistry), address(this));
        staking = new RegentRevenueStaking(
            address(regent), address(usdc), TREASURY, 1_000_000e18, address(this)
        );
        router = new RegentStakingRevenueRouter(
            address(this), address(usdc), address(subjectRegistry), address(staking)
        );
        splitter = new RevenueShareSplitterV2(
            address(stakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            SUBJECT_ID,
            TREASURY,
            address(router),
            SUPPLY_DENOMINATOR,
            "Subject",
            TREASURY
        );
        feeVault = new SubjectFeeVaultHarness(address(0x1004), address(stakeToken));
        _registerWithFeeVault(SUBJECT_ID, address(stakeToken), address(splitter), address(feeVault));
    }

    function testHundredUsdcRoutesProtocolSkimToRegentStaking() external {
        stakeToken.mint(STAKER, SUPPLY_DENOMINATOR / 10);
        vm.prank(STAKER);
        stakeToken.approve(address(splitter), SUPPLY_DENOMINATOR / 10);
        vm.prank(STAKER);
        splitter.stake(SUPPLY_DENOMINATOR / 10, STAKER);

        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(splitter), HUNDRED_USDC);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));

        assertEq(splitter.protocolFeeUsdc(), PROTOCOL_SKIM);
        assertEq(splitter.totalProtocolUsdcDepositedToRegentStaking(), PROTOCOL_SKIM);
        assertEq(splitter.stakerEligibleInflowUsdc(), SUBJECT_LANE);
        assertEq(splitter.previewClaimableUSDC(STAKER), STAKER_CLAIM);
        // Staker holds 100/1000 of the supply denominator, so of the 99 USDC staker-eligible
        // lane only 9.9 backs this staker; the un-backed remainder books as treasury residual.
        assertEq(splitter.treasuryResidualUsdc(), TREASURY_RESIDUAL);
        assertEq(usdc.balanceOf(address(staking)), PROTOCOL_SKIM);
        assertEq(staking.totalUsdcReceived(), PROTOCOL_SKIM);
        assertEq(router.totalUsdcDepositedToRegentStaking(), PROTOCOL_SKIM);
        // Only the protocol skim leaves the splitter; the former buyback lane stays as staker
        // reward inside the splitter and the treasury never receives market-bought REGENT.
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(regent.balanceOf(TREASURY), 0);
    }

    /// @notice The former 10% market-buyback lane now rides with stakers. A fully-staked subject
    ///         credits the entire post-skim subject lane (98 USDC on 100) to stakers via the
    ///         accumulator — strictly more than the 88.2 USDC they received when 9.8 was siphoned
    ///         off to the buyback — and no USDC beyond the protocol skim leaves the splitter.
    function testFormerBuybackLaneNowCreditsStakers() external {
        stakeToken.mint(STAKER, SUPPLY_DENOMINATOR);
        vm.prank(STAKER);
        stakeToken.approve(address(splitter), SUPPLY_DENOMINATOR);
        vm.prank(STAKER);
        splitter.stake(SUPPLY_DENOMINATOR, STAKER);

        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(splitter), HUNDRED_USDC);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));

        // Full post-skim lane is now staker-claimable.
        assertEq(splitter.previewClaimableUSDC(STAKER), SUBJECT_LANE);
        assertGt(SUBJECT_LANE, 88_200e3); // strictly more than the pre-cutover staker outcome
        assertEq(splitter.treasuryResidualUsdc(), 0);

        // Only the 1% protocol skim ever leaves the splitter; nothing is routed for a buyback.
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(usdc.balanceOf(address(staking)), PROTOCOL_SKIM);
        assertEq(regent.balanceOf(TREASURY), 0);

        vm.prank(STAKER);
        uint256 claimed = splitter.claimUSDC(STAKER);
        assertEq(claimed, SUBJECT_LANE);
        assertEq(usdc.balanceOf(STAKER), SUBJECT_LANE);
    }

    function testQuarantineBlocksTreasuryRecipientRotationExecution() external {
        address newSafe = address(0x7777);

        vm.prank(TREASURY);
        splitter.proposeTreasuryRecipientRotation(newSafe);
        vm.prank(TREASURY);
        subjectRegistry.quarantineSubject(SUBJECT_ID);
        vm.warp(block.timestamp + splitter.treasuryRotationDelay());

        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.executeTreasuryRecipientRotation();
        assertEq(splitter.treasuryRecipient(), TREASURY);
        assertEq(splitter.pendingTreasuryRecipient(), newSafe);
    }

    function testActiveTreasuryRotationKeepsDirectAndDefaultIngressRoutingLive() external {
        address newSafe = address(0x7777);

        vm.prank(TREASURY);
        splitter.proposeTreasuryRecipientRotation(newSafe);
        assertEq(splitter.treasuryRotationDelay(), 3 days);
        vm.warp(block.timestamp + 3 days);
        splitter.executeTreasuryRecipientRotation();

        address ingress =
            ingressFactory.createDefaultIngressAccount(SUBJECT_ID, "default-usdc-ingress");

        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(splitter), HUNDRED_USDC);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));

        usdc.mint(ingress, HUNDRED_USDC);
        RevenueIngressAccount(payable(ingress)).sweepUSDC(bytes32("default_ingress"));

        assertEq(splitter.treasuryRecipient(), newSafe);
        assertEq(splitter.directDepositUsdc(), HUNDRED_USDC);
        assertEq(splitter.verifiedIngressUsdc(), HUNDRED_USDC);
        assertEq(splitter.protocolFeeUsdc(), PROTOCOL_SKIM * 2);
        assertEq(splitter.treasuryResidualUsdc(), SUBJECT_LANE * 2);

        vm.prank(newSafe);
        splitter.sweepTreasuryResidualUSDC(SUBJECT_LANE * 2);
        assertEq(usdc.balanceOf(newSafe), SUBJECT_LANE * 2);
        assertEq(usdc.balanceOf(TREASURY), 0);
    }

    function testNoStakerSubjectStillSendsProtocolSkimToRegentStaking() external {
        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(splitter), HUNDRED_USDC);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));

        assertEq(splitter.protocolFeeUsdc(), PROTOCOL_SKIM);
        assertEq(splitter.totalProtocolUsdcDepositedToRegentStaking(), PROTOCOL_SKIM);
        assertEq(splitter.previewClaimableUSDC(STAKER), 0);
        assertEq(splitter.treasuryResidualUsdc(), SUBJECT_LANE);
        assertEq(usdc.balanceOf(address(staking)), PROTOCOL_SKIM);
        assertEq(staking.totalUsdcReceived(), PROTOCOL_SKIM);
        assertEq(regent.balanceOf(TREASURY), 0);
    }

    function testClaimRoundingOverageIsPaidFromUndistributedDust() external {
        bytes32 subjectId = keccak256("v2-rounding-overage");
        MintableERC20Mock dustStakeToken = new MintableERC20Mock("Dust Agent", "DAGENT");
        RevenueShareSplitterV2 dustSplitter = new RevenueShareSplitterV2(
            address(dustStakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            subjectId,
            TREASURY,
            address(router),
            3,
            "Subject",
            TREASURY
        );
        _register(subjectId, address(dustStakeToken), address(dustSplitter));

        // Fully staked subject with a denominator that does not divide ACC_PRECISION:
        // accumulator rounding books the staker entitlement into undistributedDustUsdc
        // while treasuryResidualUsdc stays at zero.
        dustStakeToken.mint(STAKER, 3);
        vm.startPrank(STAKER);
        dustStakeToken.approve(address(dustSplitter), 3);
        dustSplitter.stake(3, STAKER);
        vm.stopPrank();

        usdc.mint(address(this), 2);
        usdc.approve(address(dustSplitter), 2);
        dustSplitter.depositUSDC(1, bytes32("direct"), bytes32("source"));
        dustSplitter.depositUSDC(1, bytes32("direct"), bytes32("source"));

        assertEq(dustSplitter.undistributedDustUsdc(), 2);
        assertEq(dustSplitter.treasuryResidualUsdc(), 0);
        assertEq(dustSplitter.previewClaimableUSDC(STAKER), 1);

        vm.prank(STAKER);
        uint256 claimed = dustSplitter.claimUSDC(STAKER);

        assertEq(claimed, 1);
        assertEq(usdc.balanceOf(STAKER), 1);
        assertEq(dustSplitter.undistributedDustUsdc(), 1);
        assertEq(dustSplitter.treasuryResidualUsdc(), 0);
        assertEq(usdc.balanceOf(address(dustSplitter)), dustSplitter.reservedUsdc());
    }

    function testTreasuryResidualSweepCannotWithdrawRoundingOwedToStakers() external {
        bytes32 subjectId = keccak256("v2-residual-sweep-dos");
        MintableERC20Mock residualStakeToken = new MintableERC20Mock("Residual Agent", "RAGENT");
        RevenueShareSplitterV2 residualSplitter = new RevenueShareSplitterV2(
            address(residualStakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            subjectId,
            TREASURY,
            address(router),
            4,
            "Subject",
            TREASURY
        );
        _register(subjectId, address(residualStakeToken), address(residualSplitter));

        residualStakeToken.mint(STAKER, 1);
        residualStakeToken.mint(STAKER_TWO, 1);
        vm.startPrank(STAKER);
        residualStakeToken.approve(address(residualSplitter), 1);
        residualSplitter.stake(1, STAKER);
        vm.stopPrank();
        vm.startPrank(STAKER_TWO);
        residualStakeToken.approve(address(residualSplitter), 1);
        residualSplitter.stake(1, STAKER_TWO);
        vm.stopPrank();

        usdc.mint(address(this), 4);
        usdc.approve(address(residualSplitter), 4);
        residualSplitter.depositUSDC(1, bytes32("direct"), bytes32("one"));
        residualSplitter.depositUSDC(3, bytes32("direct"), bytes32("three"));

        assertEq(residualSplitter.previewClaimableUSDC(STAKER), 1);
        assertEq(residualSplitter.previewClaimableUSDC(STAKER_TWO), 1);
        assertEq(residualSplitter.totalUsdcCreditedToStakers(), 1);
        assertEq(residualSplitter.undistributedDustUsdc(), 1);
        assertEq(residualSplitter.claimRoundingReserveUsdc(), 1);
        assertEq(usdc.balanceOf(address(residualSplitter)), residualSplitter.reservedUsdc());

        uint256 residualToSweep = residualSplitter.treasuryResidualUsdc();
        vm.prank(TREASURY);
        residualSplitter.sweepTreasuryResidualUSDC(residualToSweep);

        vm.prank(STAKER);
        assertEq(residualSplitter.claimUSDC(STAKER), 1);
        vm.prank(STAKER_TWO);
        assertEq(residualSplitter.claimUSDC(STAKER_TWO), 1);

        assertEq(usdc.balanceOf(STAKER), 1);
        assertEq(usdc.balanceOf(STAKER_TWO), 1);
        assertEq(residualSplitter.undistributedDustUsdc(), 0);
        assertEq(residualSplitter.claimRoundingReserveUsdc(), 0);
        assertEq(usdc.balanceOf(address(residualSplitter)), residualSplitter.reservedUsdc());
    }

    function testTreasuryCannotReassignRoundingDustOwedToStakers() external {
        bytes32 subjectId = keccak256("v2-reassign-rounding-dust");
        MintableERC20Mock residualStakeToken = new MintableERC20Mock("Residual Agent", "RAGENT");
        RevenueShareSplitterV2 residualSplitter = new RevenueShareSplitterV2(
            address(residualStakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            subjectId,
            TREASURY,
            address(router),
            4,
            "Subject",
            TREASURY
        );
        _register(subjectId, address(residualStakeToken), address(residualSplitter));

        residualStakeToken.mint(STAKER, 1);
        residualStakeToken.mint(STAKER_TWO, 1);
        vm.startPrank(STAKER);
        residualStakeToken.approve(address(residualSplitter), 1);
        residualSplitter.stake(1, STAKER);
        vm.stopPrank();
        vm.startPrank(STAKER_TWO);
        residualStakeToken.approve(address(residualSplitter), 1);
        residualSplitter.stake(1, STAKER_TWO);
        vm.stopPrank();

        usdc.mint(address(this), 4);
        usdc.approve(address(residualSplitter), 4);
        residualSplitter.depositUSDC(1, bytes32("direct"), bytes32("one"));
        residualSplitter.depositUSDC(3, bytes32("direct"), bytes32("three"));

        assertEq(residualSplitter.undistributedDustUsdc(), 1);
        assertEq(residualSplitter.claimRoundingReserveUsdc(), 1);

        vm.prank(TREASURY);
        vm.expectRevert("DUST_RESERVED_FOR_STAKERS");
        residualSplitter.reassignUndistributedDustToTreasury(1);
    }

    function testUnstakeRejectsOutboundFeeOnTransferStakeTokenAndKeepsAccounting() external {
        TransferFeeERC20Mock feeToken = new TransferFeeERC20Mock("Fee", "FEE", 18, address(0));
        bytes32 feeSubjectId = keccak256("v2-fee-out-subject");
        RevenueShareSplitterV2 feeSplitter = new RevenueShareSplitterV2(
            address(feeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            feeSubjectId,
            TREASURY,
            address(router),
            100e18,
            "Fee subject",
            TREASURY
        );
        _register(feeSubjectId, address(feeToken), address(feeSplitter));

        feeToken.mint(STAKER, 100e18);
        vm.startPrank(STAKER);
        feeToken.approve(address(feeSplitter), type(uint256).max);
        feeSplitter.stake(100e18, STAKER);
        vm.stopPrank();

        feeToken.setFeeBps(500);
        feeToken.setFeeTriggers(address(feeSplitter), true, false);

        vm.prank(STAKER);
        vm.expectRevert("STAKE_TOKEN_OUT_EXACT");
        feeSplitter.unstake(100e18, STAKER);

        assertEq(feeSplitter.stakedBalance(STAKER), 100e18);
        assertEq(feeSplitter.totalStaked(), 100e18);
        assertEq(feeToken.balanceOf(address(feeSplitter)), 100e18);
        assertEq(feeToken.balanceOf(STAKER), 0);
    }

    function testClaimAndUnstakeCannotRedirectFixedAccountExit() external {
        stakeToken.mint(STAKER, SUPPLY_DENOMINATOR);
        vm.startPrank(STAKER);
        stakeToken.approve(address(splitter), SUPPLY_DENOMINATOR);
        splitter.stake(SUPPLY_DENOMINATOR, STAKER);
        vm.stopPrank();

        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(splitter), HUNDRED_USDC);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));

        vm.startPrank(STAKER);
        vm.expectRevert("RECIPIENT_NOT_ACCOUNT");
        splitter.claimUSDC(STAKER_TWO);
        vm.expectRevert("RECIPIENT_NOT_ACCOUNT");
        splitter.unstake(SUPPLY_DENOMINATOR, STAKER_TWO);
        vm.stopPrank();
    }

    function testDepositRejectsInexactProtocolFeeRouterReturn() external {
        bytes32 subjectId = keccak256("v2-mock-protocol-return");
        MockRegentStakingRevenueRouter mockRouter =
            new MockRegentStakingRevenueRouter(address(usdc), address(staking));
        RevenueShareSplitterV2 mockSplitter = _mockRouterSplitter(subjectId, mockRouter);
        mockRouter.setProcessProtocolFeeReturnOverride(PROTOCOL_SKIM - 1);

        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(mockSplitter), HUNDRED_USDC);

        vm.expectRevert("PROTOCOL_DEPOSIT_INEXACT");
        mockSplitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));
    }

    function testSHARED_USDC_SKIM_GOVERNANCEExistingSplitterReadsCurrentRouterState() external {
        usdc.mint(address(this), HUNDRED_USDC * 2);
        usdc.approve(address(splitter), HUNDRED_USDC * 2);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("before"));

        router.setProtocolSkimBps(0);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("after"));

        assertEq(splitter.protocolFeeUsdc(), PROTOCOL_SKIM);
        assertEq(splitter.stakerEligibleInflowUsdc(), SUBJECT_LANE + HUNDRED_USDC);
        assertEq(usdc.balanceOf(address(staking)), PROTOCOL_SKIM);
    }

    function testSUBJECT_REGENT_OWNERSHIPOnlyRegisteredVaultFundsAndStakerClaimsAll() external {
        stakeToken.mint(STAKER, SUPPLY_DENOMINATOR);
        vm.startPrank(STAKER);
        stakeToken.approve(address(splitter), SUPPLY_DENOMINATOR);
        splitter.stake(SUPPLY_DENOMINATOR, STAKER);
        vm.stopPrank();

        vm.expectRevert(RevenueShareSplitterV2.SubjectFeeVaultUnauthorized.selector);
        splitter.fundRegentRewards(1);

        uint256 amount = 100e18;
        regent.mint(address(feeVault), amount);
        assertEq(feeVault.fund(splitter, amount), amount);
        assertEq(regent.allowance(address(feeVault), address(splitter)), 0);
        assertEq(splitter.previewClaimableRegent(STAKER), amount);
        assertEq(splitter.reservedRegent(), amount);

        vm.prank(STAKER);
        vm.expectRevert("RECIPIENT_NOT_ACCOUNT");
        splitter.claimRegent(STAKER_TWO);
        vm.prank(STAKER);
        assertEq(splitter.claimRegent(STAKER), amount);
        assertEq(regent.balanceOf(STAKER), amount);
        assertEq(splitter.reservedRegent(), 0);
    }

    function testNON_RETROACTIVE_DUAL_ASSET_ACCOUNTINGStakeChangesPreserveBothDebts() external {
        uint256 half = SUPPLY_DENOMINATOR / 2;
        stakeToken.mint(STAKER, half);
        stakeToken.mint(STAKER_TWO, half);
        vm.startPrank(STAKER);
        stakeToken.approve(address(splitter), half);
        splitter.stake(half, STAKER);
        vm.stopPrank();

        usdc.mint(address(this), HUNDRED_USDC * 2);
        usdc.approve(address(splitter), HUNDRED_USDC * 2);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("first"));
        regent.mint(address(feeVault), 200e18);
        feeVault.fund(splitter, 100e18);

        vm.startPrank(STAKER_TWO);
        stakeToken.approve(address(splitter), half);
        splitter.stake(half, STAKER_TWO);
        vm.stopPrank();
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("second"));
        feeVault.fund(splitter, 100e18);

        vm.prank(STAKER);
        splitter.unstake(half, STAKER);
        assertEq(splitter.previewClaimableUSDC(STAKER), 98e6);
        assertEq(splitter.previewClaimableUSDC(STAKER_TWO), 49e6);
        assertEq(splitter.previewClaimableRegent(STAKER), 150e18);
        assertEq(splitter.previewClaimableRegent(STAKER_TWO), 50e18);

        vm.prank(STAKER);
        assertEq(splitter.claimRegent(STAKER), 150e18);
        vm.prank(STAKER_TWO);
        assertEq(splitter.claimRegent(STAKER_TWO), 50e18);
        assertEq(regent.balanceOf(address(splitter)), splitter.reservedRegent());
    }

    function testNON_RETROACTIVE_DUAL_ASSET_ACCOUNTINGZeroStakeAndDustCannotBeCaptured() external {
        bytes32 dustSubjectId = keccak256("regent-dust-subject");
        MintableERC20Mock dustStakeToken = new MintableERC20Mock("Dust", "DUST");
        RevenueShareSplitterV2 dustSplitter = new RevenueShareSplitterV2(
            address(dustStakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            dustSubjectId,
            TREASURY,
            address(router),
            7,
            "Dust subject",
            TREASURY
        );
        SubjectFeeVaultHarness dustVault =
            new SubjectFeeVaultHarness(address(0x1004), address(dustStakeToken));
        _registerWithFeeVault(
            dustSubjectId, address(dustStakeToken), address(dustSplitter), address(dustVault)
        );

        regent.mint(address(dustVault), 6);
        dustVault.fund(dustSplitter, 5);
        dustStakeToken.mint(STAKER, 7);
        vm.startPrank(STAKER);
        dustStakeToken.approve(address(dustSplitter), 7);
        dustSplitter.stake(7, STAKER);
        vm.stopPrank();
        assertEq(dustSplitter.previewClaimableRegent(STAKER), 0);

        dustVault.fund(dustSplitter, 1);
        assertEq(dustSplitter.previewClaimableRegent(STAKER), 0);
        assertEq(dustSplitter.reservedRegent(), 6);
        assertEq(regent.balanceOf(address(dustSplitter)), 6);

        vm.prank(STAKER);
        dustSplitter.unstake(7, STAKER);
        dustStakeToken.mint(STAKER_TWO, 7);
        vm.startPrank(STAKER_TWO);
        dustStakeToken.approve(address(dustSplitter), 7);
        dustSplitter.stake(7, STAKER_TWO);
        vm.stopPrank();
        assertEq(dustSplitter.previewClaimableRegent(STAKER_TWO), 0);

        regent.mint(address(dustSplitter), 3);
        assertEq(dustSplitter.reservedRegent(), 6);
        assertEq(regent.balanceOf(address(dustSplitter)), 9);
    }

    function testPRESERVED_SUBJECT_ECONOMICSQuarantineAllowsRegentSettlementAndClaim() external {
        stakeToken.mint(STAKER, SUPPLY_DENOMINATOR);
        vm.startPrank(STAKER);
        stakeToken.approve(address(splitter), SUPPLY_DENOMINATOR);
        splitter.stake(SUPPLY_DENOMINATOR, STAKER);
        vm.stopPrank();

        vm.prank(TREASURY);
        subjectRegistry.quarantineSubject(SUBJECT_ID);
        uint256 amount = 25e18;
        regent.mint(address(feeVault), amount);
        assertEq(feeVault.fund(splitter, amount), amount);

        vm.prank(STAKER);
        assertEq(splitter.claimRegent(STAKER), amount);
        assertEq(regent.balanceOf(STAKER), amount);
        assertEq(splitter.reservedRegent(), 0);
    }

    function testSUBJECT_REGENT_OWNERSHIPRetirementBlocksFundingWithoutResidue() external {
        vm.prank(address(0x1003));
        subjectRegistry.retireSubject(SUBJECT_ID);
        uint256 amount = 25e18;
        regent.mint(address(feeVault), amount);

        vm.expectRevert(RevenueShareSplitterV2.SubjectBindingMismatch.selector);
        feeVault.fund(splitter, amount);

        assertEq(regent.balanceOf(address(feeVault)), amount);
        assertEq(regent.balanceOf(address(splitter)), 0);
        assertEq(regent.allowance(address(feeVault), address(splitter)), 0);
        assertEq(splitter.reservedRegent(), 0);
    }

    function _mockRouterSplitter(bytes32 subjectId, MockRegentStakingRevenueRouter mockRouter)
        internal
        returns (RevenueShareSplitterV2 mockSplitter)
    {
        MintableERC20Mock mockStakeToken = new MintableERC20Mock("Mock Agent", "MAGENT");
        mockSplitter = new RevenueShareSplitterV2(
            address(mockStakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            subjectId,
            TREASURY,
            address(mockRouter),
            SUPPLY_DENOMINATOR,
            "Subject",
            TREASURY
        );
        _register(subjectId, address(mockStakeToken), address(mockSplitter));
    }

    function _register(bytes32 id, address token, address subjectSplitter) internal {
        _registerWithFeeVault(id, token, subjectSplitter, address(0x1005));
    }

    function _registerWithFeeVault(
        bytes32 id,
        address token,
        address subjectSplitter,
        address subjectFeeVault
    ) internal {
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        subjectRegistry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: id,
                stakeToken: token,
                splitter: subjectSplitter,
                agentSafe: TREASURY,
                ingress: ingressFactory.predictDefaultIngress(id, TREASURY),
                paymentLinkFactory: address(0x1002),
                strategy: address(0x1003),
                launchFeeRegistry: address(0x1004),
                feeVault: subjectFeeVault,
                feeHook: address(0x1006),
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                label: "Subject",
                safeRuntime: address(0x7007)
            })
        );
    }
}
