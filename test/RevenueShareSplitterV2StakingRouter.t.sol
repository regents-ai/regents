// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {RegentStakingRevenueRouter} from "src/autolaunch/revenue/RegentStakingRevenueRouter.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {TransferFeeERC20Mock} from "test/mocks/TransferFeeERC20Mock.sol";

contract RevenueShareSplitterV2StakingRouterTest is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("v2-subject");
    address internal constant TREASURY = address(0x1111);
    address internal constant STAKER = address(0x3333);
    address internal constant STAKER_TWO = address(0x4444);
    uint256 internal constant SUPPLY_DENOMINATOR = 1000e18;
    uint256 internal constant HUNDRED_USDC = 100e18;
    uint256 internal constant PROTOCOL_SKIM = 1e18;
    // The former 10% market-buyback lane now rides with stakers: the full post-skim subject
    // lane (99 USDC on a 100 USDC deposit) is staker-eligible under the default 100% share.
    uint256 internal constant SUBJECT_LANE = 99e18;
    uint256 internal constant STAKER_CLAIM = 9900e15;
    uint256 internal constant TREASURY_RESIDUAL = 89_100e15;

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal regent;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    RevenueIngressFactory internal ingressFactory;
    RegentRevenueStaking internal staking;
    RegentStakingRevenueRouter internal router;
    RevenueShareSplitterV2 internal splitter;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        regent = new MintableERC20Mock("REGENT", "REGENT");
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
        router.setMaxUsdcPerSettlement(1000e18);
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
        _register(SUBJECT_ID, address(stakeToken), address(splitter));
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
    ///         credits the entire post-skim subject lane (99 USDC on 100) to stakers via the
    ///         accumulator — strictly more than the 89.1 USDC they received when 9.9 was siphoned
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

        // Full post-skim lane (99 USDC, incl. the old 9.9 buyback slice) is now staker-claimable.
        assertEq(splitter.previewClaimableUSDC(STAKER), SUBJECT_LANE);
        assertGt(SUBJECT_LANE, 89_100e15); // strictly more than the pre-cutover staker outcome
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

    function testTreasuryDivergenceBetweenSplitterAndRegistryDoesNotBrickDeposits() external {
        address newSafe = address(0x7777);

        // Rotate the V2 splitter's OWN treasuryRecipient without touching the registry.
        vm.startPrank(TREASURY);
        splitter.proposeTreasuryRecipientRotation(newSafe);
        vm.warp(block.timestamp + splitter.treasuryRotationDelay());
        splitter.executeTreasuryRecipientRotation();
        vm.stopPrank();
        assertEq(splitter.treasuryRecipient(), newSafe);

        // Revenue intake keeps working even though splitter and registry treasuries diverge.
        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(splitter), HUNDRED_USDC);
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));

        assertEq(splitter.protocolFeeUsdc(), PROTOCOL_SKIM);
        assertEq(usdc.balanceOf(address(staking)), PROTOCOL_SKIM);
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
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        subjectRegistry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: id,
                stakeToken: token,
                splitter: subjectSplitter,
                agentSafe: TREASURY,
                ingress: address(0x1001),
                paymentLinkFactory: address(0x1002),
                strategy: address(0x1003),
                launchFeeRegistry: address(0x1004),
                feeVault: address(0x1005),
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
