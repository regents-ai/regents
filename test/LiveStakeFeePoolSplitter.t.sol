// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {LiveStakeFeePoolSplitter} from "src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol";
import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {RegentStakingRevenueRouter} from "src/autolaunch/revenue/RegentStakingRevenueRouter.sol";
import {RevenueIngressAccount} from "src/autolaunch/revenue/RevenueIngressAccount.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";
import {TransferFeeERC20Mock} from "test/mocks/TransferFeeERC20Mock.sol";

contract LiveStakeFeePoolSplitterTest is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("live-subject");
    address internal constant TREASURY = address(0x1111);
    address internal constant CREATOR = address(0x2222);
    address internal constant STAKER_ONE = address(0x3333);
    address internal constant STAKER_TWO = address(0x4444);
    uint256 internal constant HUNDRED_USDC = 100e18;
    uint256 internal constant PROTOCOL_SKIM = 1e18;
    // The former 10% market-buyback lane is gone: net-after-skim is the full agent lane, split
    // between the staker pool (stakerPoolBps) and treasury.
    uint256 internal constant SUBJECT_LANE = 99e18;
    uint256 internal constant STAKER_POOL = 99e17;
    uint256 internal constant TREASURY_LANE = 891e17;

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    RevenueIngressFactory internal ingressFactory;
    MockRegentStakingRevenueRouter internal feeRouter;
    LiveStakeFeePoolSplitter internal splitter;
    RevenueIngressAccount internal ingress;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        stakeToken = new MintableERC20Mock("Agent", "AGENT");
        subjectRegistry = new SubjectRegistry(address(this), address(0xA11CE), address(0x600D));
        ingressFactory =
            new RevenueIngressFactory(address(usdc), address(subjectRegistry), address(this));
        feeRouter = new MockRegentStakingRevenueRouter(address(usdc), address(0x8888));
        splitter = new LiveStakeFeePoolSplitter(
            address(stakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            SUBJECT_ID,
            TREASURY,
            address(feeRouter),
            1000,
            "Live subject",
            TREASURY
        );

        address predictedIngress = ingressFactory.predictDefaultIngress(SUBJECT_ID, TREASURY);
        _register(SUBJECT_ID, address(stakeToken), address(splitter), predictedIngress);

        ingress = RevenueIngressAccount(
            payable(ingressFactory.createDefaultIngressAccount(SUBJECT_ID, "default-usdc-ingress"))
        );
    }

    function testHundredUsdcRoutesProtocolStakerPoolAndTreasury() external {
        _stake(STAKER_ONE, 10e18);

        _depositUsdc(address(this), 100e18);

        assertEq(splitter.protocolFeeUsdc(), PROTOCOL_SKIM);
        assertEq(splitter.netAgentLaneUsdc(), SUBJECT_LANE);
        assertEq(splitter.stakerPoolInflowUsdc(), STAKER_POOL);
        assertEq(splitter.treasuryReservedUsdc(), TREASURY_LANE);
        assertEq(splitter.previewClaimableUSDC(STAKER_ONE), STAKER_POOL);
        // Only the protocol skim leaves the splitter for the fee router; the former buyback lane
        // stays inside the splitter and is distributed to stakers.
        assertEq(usdc.balanceOf(address(feeRouter)), PROTOCOL_SKIM);
        assertEq(feeRouter.totalUsdcProcessed(), PROTOCOL_SKIM);
        assertEq(feeRouter.totalUsdcDepositedToRegentStaking(), PROTOCOL_SKIM);
    }

    function testDepositRejectsInexactProtocolFeeRouterReturn() external {
        _stake(STAKER_ONE, 10e18);
        feeRouter.setProcessProtocolFeeReturnOverride(PROTOCOL_SKIM - 1);

        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(splitter), HUNDRED_USDC);

        vm.expectRevert("PROTOCOL_DEPOSIT_INEXACT");
        splitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));
    }

    function testHundredUsdcDepositsProtocolSkimIntoRegentStaking() external {
        bytes32 liveSubjectId = keccak256("live-subject-real-router");
        MintableERC20Mock liveStakeToken = new MintableERC20Mock("Live Agent", "LIVE");
        MintableERC20Mock regent = new MintableERC20Mock("REGENT", "REGENT");
        RegentRevenueStaking staking = new RegentRevenueStaking(
            address(regent), address(usdc), TREASURY, 1_000_000e18, address(this)
        );
        RegentStakingRevenueRouter router = new RegentStakingRevenueRouter(
            address(this), address(usdc), address(subjectRegistry), address(staking)
        );
        router.setMaxUsdcPerSettlement(1000e18);
        LiveStakeFeePoolSplitter realRouterSplitter = new LiveStakeFeePoolSplitter(
            address(liveStakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            liveSubjectId,
            TREASURY,
            address(router),
            1000,
            "Live subject",
            TREASURY
        );
        _register(liveSubjectId, address(liveStakeToken), address(realRouterSplitter), address(1));

        liveStakeToken.mint(STAKER_ONE, 1000e18);
        vm.prank(STAKER_ONE);
        liveStakeToken.approve(address(realRouterSplitter), 10e18);
        vm.prank(STAKER_ONE);
        realRouterSplitter.stake(10e18, STAKER_ONE);

        usdc.mint(address(this), HUNDRED_USDC);
        usdc.approve(address(realRouterSplitter), HUNDRED_USDC);
        realRouterSplitter.depositUSDC(HUNDRED_USDC, bytes32("direct"), bytes32("source"));

        assertEq(realRouterSplitter.protocolFeeUsdc(), PROTOCOL_SKIM);
        assertEq(realRouterSplitter.netAgentLaneUsdc(), SUBJECT_LANE);
        assertEq(realRouterSplitter.stakerPoolInflowUsdc(), STAKER_POOL);
        assertEq(realRouterSplitter.treasuryReservedUsdc(), TREASURY_LANE);
        assertEq(realRouterSplitter.previewClaimableUSDC(STAKER_ONE), STAKER_POOL);
        assertEq(usdc.balanceOf(address(staking)), PROTOCOL_SKIM);
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(staking.totalUsdcReceived(), PROTOCOL_SKIM);
        assertEq(router.totalUsdcDepositedToRegentStaking(), PROTOCOL_SKIM);
        assertEq(regent.balanceOf(TREASURY), 0);
    }

    function testTwoLiveStakersSplitPoolByCurrentStakeOnly() external {
        _stake(STAKER_ONE, 20e18);
        _stake(STAKER_TWO, 10e18);

        _depositUsdc(address(this), 100e18);

        assertEq(splitter.previewClaimableUSDC(STAKER_ONE), 66e17);
        assertEq(splitter.previewClaimableUSDC(STAKER_TWO), 33e17);

        vm.prank(STAKER_ONE);
        splitter.claimUSDC(STAKER_ONE);
        vm.prank(STAKER_TWO);
        splitter.claimUSDC(STAKER_TWO);

        assertEq(usdc.balanceOf(STAKER_ONE), 66e17);
        assertEq(usdc.balanceOf(STAKER_TWO), 33e17);
    }

    function testNoStakersRoutesStakerPoolToTreasuryAndLateStakeGetsNothing() external {
        _depositUsdc(address(this), 100e18);

        assertEq(splitter.treasuryReservedUsdc(), SUBJECT_LANE);
        assertEq(splitter.noStakerPoolRoutedToTreasuryUsdc(), STAKER_POOL);

        _stake(STAKER_ONE, 10e18);

        assertEq(splitter.previewClaimableUSDC(STAKER_ONE), 0);
    }

    function testTinyStakerPoolAgainstHugeStakeRoutesToTreasuryInsteadOfReverting() external {
        // A huge stake makes the per-token accumulator delta round to zero for a tiny
        // staker pool. The deposit must still succeed and send those funds to treasury
        // rather than reverting and stranding revenue recognition.
        uint256 hugeStake = 1e28;
        stakeToken.mint(STAKER_ONE, hugeStake);
        vm.prank(STAKER_ONE);
        stakeToken.approve(address(splitter), hugeStake);
        vm.prank(STAKER_ONE);
        splitter.stake(hugeStake, STAKER_ONE);

        // 100 wei USDC -> protocol 1, net 99, staker pool 9, treasury 90.
        // deltaAcc = mulDiv(9, 1e27, 1e28) == 0, so the 9-wei staker pool falls to treasury.
        _depositUsdc(address(this), 100);

        assertEq(splitter.stakerPoolInflowUsdc(), 9);
        assertEq(splitter.noStakerPoolRoutedToTreasuryUsdc(), 9);
        assertEq(splitter.treasuryReservedUsdc(), 99);
        assertEq(splitter.accRewardPerTokenUsdc(), 0);
        assertEq(splitter.undistributedDustUsdc(), 0);
        assertEq(splitter.previewClaimableUSDC(STAKER_ONE), 0);
    }

    function testUnstakeSyncsBeforeReducingBalance() external {
        _stake(STAKER_ONE, 10e18);
        _depositUsdc(address(this), 100e18);

        vm.prank(STAKER_ONE);
        splitter.unstake(5e18, STAKER_ONE);

        assertEq(splitter.previewClaimableUSDC(STAKER_ONE), STAKER_POOL);
        assertEq(stakeToken.balanceOf(STAKER_ONE), 995e18);
    }

    function testFeeOnTransferStakeTokenFailsExactTransferCheck() external {
        TransferFeeERC20Mock feeToken = new TransferFeeERC20Mock("Fee", "FEE", 18, address(0x9999));
        bytes32 feeSubjectId = keccak256("fee-subject");
        LiveStakeFeePoolSplitter feeSplitter = new LiveStakeFeePoolSplitter(
            address(feeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            feeSubjectId,
            TREASURY,
            address(feeRouter),
            1000,
            "Fee subject",
            TREASURY
        );
        _register(feeSubjectId, address(feeToken), address(feeSplitter), address(1));

        feeToken.mint(STAKER_ONE, 100e18);
        feeToken.setFeeBps(100);
        feeToken.setFeeTriggers(address(feeSplitter), false, true);

        vm.prank(STAKER_ONE);
        feeToken.approve(address(feeSplitter), 100e18);

        vm.prank(STAKER_ONE);
        vm.expectRevert("STAKE_TOKEN_IN_EXACT");
        feeSplitter.stake(100e18, STAKER_ONE);
    }

    function testUnstakeRejectsOutboundFeeOnTransferStakeTokenAndKeepsAccounting() external {
        TransferFeeERC20Mock feeToken = new TransferFeeERC20Mock("Fee", "FEE", 18, address(0));
        bytes32 feeSubjectId = keccak256("fee-out-subject");
        LiveStakeFeePoolSplitter feeSplitter = new LiveStakeFeePoolSplitter(
            address(feeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            feeSubjectId,
            TREASURY,
            address(feeRouter),
            1000,
            "Fee subject",
            TREASURY
        );
        _register(feeSubjectId, address(feeToken), address(feeSplitter), address(1));

        feeToken.mint(STAKER_ONE, 100e18);
        vm.startPrank(STAKER_ONE);
        feeToken.approve(address(feeSplitter), type(uint256).max);
        feeSplitter.stake(100e18, STAKER_ONE);
        vm.stopPrank();

        feeToken.setFeeBps(500);
        feeToken.setFeeTriggers(address(feeSplitter), true, false);

        vm.prank(STAKER_ONE);
        vm.expectRevert("STAKE_TOKEN_OUT_EXACT");
        feeSplitter.unstake(100e18, STAKER_ONE);

        assertEq(feeSplitter.stakedBalance(STAKER_ONE), 100e18);
        assertEq(feeSplitter.totalStaked(), 100e18);
        assertEq(feeToken.balanceOf(address(feeSplitter)), 100e18);
        assertEq(feeToken.balanceOf(STAKER_ONE), 0);
    }

    function testIngressSweepRequiresKnownIngressForSameSubject() external {
        vm.expectRevert("ONLY_INGRESS_ACCOUNT");
        splitter.recordIngressSweep(100e18, bytes32("not-ingress"));

        usdc.mint(address(ingress), 100e18);
        ingress.sweepUSDC(bytes32("sweep"));

        assertEq(feeRouter.totalUsdcProcessed(), PROTOCOL_SKIM);
        assertEq(splitter.verifiedIngressUsdc(), 100e18);
    }

    function testIngressSweepPullsAndCreditsMeasuredDelta() external {
        _stake(STAKER_ONE, 10e18);
        usdc.mint(address(ingress), 100e18);

        (uint256 balance, uint256 recognized) = ingress.sweepUSDC(bytes32("sweep"));

        assertEq(balance, 100e18);
        assertEq(recognized, 100e18);
        assertEq(splitter.verifiedIngressUsdc(), 100e18);
        assertEq(splitter.totalUsdcReceived(), 100e18);
        assertEq(splitter.previewClaimableUSDC(STAKER_ONE), STAKER_POOL);
        assertEq(usdc.balanceOf(address(ingress)), 0);
        assertEq(usdc.allowance(address(ingress), address(splitter)), 0);
    }

    function testIngressOverReportWithoutFundsCannotCredit() external {
        // A known ingress claiming an amount it never made available reverts on the pull.
        vm.prank(address(ingress));
        vm.expectRevert("TRANSFER_FROM_FAILED");
        splitter.recordIngressSweep(100e18, bytes32("phantom"));

        assertEq(splitter.verifiedIngressUsdc(), 0);
        assertEq(splitter.totalUsdcReceived(), 0);
    }

    function testIngressOverReportBeyondHeldBalanceCannotCredit() external {
        // The ingress holds and approves less than it claims; the pull reverts and
        // nothing is credited.
        usdc.mint(address(ingress), 50e18);
        vm.prank(address(ingress));
        usdc.approve(address(splitter), 100e18);

        vm.prank(address(ingress));
        vm.expectRevert("TRANSFER_FROM_FAILED");
        splitter.recordIngressSweep(100e18, bytes32("over-report"));

        assertEq(splitter.verifiedIngressUsdc(), 0);
        assertEq(splitter.totalUsdcReceived(), 0);
        assertEq(usdc.balanceOf(address(ingress)), 50e18);
    }

    function testIngressSweepOneWeiIsRecognizedExactly() external {
        _stake(STAKER_ONE, 10e18);
        usdc.mint(address(ingress), 1);

        (uint256 balance, uint256 recognized) = ingress.sweepUSDC(bytes32("one-wei"));

        assertEq(balance, 1);
        assertEq(recognized, 1);
        assertEq(splitter.verifiedIngressUsdc(), 1);
        // Protocol and staker-pool floors both round to zero at 1 wei, so the full wei lands
        // in the treasury lane and solvency holds.
        assertEq(splitter.treasuryReservedUsdc(), 1);
        assertEq(usdc.balanceOf(address(splitter)), 1);
        assertEq(splitter.reservedUsdc(), 1);
    }

    function testIngressSweepCannotDoubleCreditTheSameFunds() external {
        usdc.mint(address(ingress), 100e18);
        ingress.sweepUSDC(bytes32("sweep"));
        assertEq(splitter.verifiedIngressUsdc(), 100e18);

        // Nothing new arrived: the ingress has nothing left to sweep...
        vm.expectRevert("NOTHING_TO_SWEEP");
        ingress.sweepUSDC(bytes32("sweep-again"));

        // ...and replaying the record call directly cannot re-credit without a new pull.
        vm.prank(address(ingress));
        vm.expectRevert("TRANSFER_FROM_FAILED");
        splitter.recordIngressSweep(100e18, bytes32("replay"));

        assertEq(splitter.verifiedIngressUsdc(), 100e18);
        assertEq(splitter.totalUsdcReceived(), 100e18);
    }

    function testDirectDepositAndIngressSweepBothCallRouterSynchronously() external {
        _depositUsdc(address(this), 100e18);
        usdc.mint(address(ingress), 50e18);
        ingress.sweepUSDC(bytes32("sweep"));

        // Protocol skim on 100 + 50 = 1.5 USDC processed by the router.
        assertEq(feeRouter.totalUsdcProcessed(), 1500e15);
    }

    function testRouterRevertLeavesDirectDepositAndSweepAccountingUnchanged() external {
        feeRouter.setShouldRevert(true);

        usdc.mint(address(this), 100e18);
        usdc.approve(address(splitter), 100e18);

        vm.expectRevert("MOCK_ROUTER_REVERT");
        splitter.depositUSDC(100e18, bytes32("direct"), bytes32("source"));

        assertEq(usdc.balanceOf(address(this)), 100e18);
        assertEq(splitter.totalUsdcReceived(), 0);

        usdc.mint(address(ingress), 100e18);

        vm.expectRevert("MOCK_ROUTER_REVERT");
        ingress.sweepUSDC(bytes32("sweep"));

        assertEq(usdc.balanceOf(address(ingress)), 100e18);
        assertEq(splitter.totalUsdcReceived(), 0);
    }

    function testOwnerReassignsUndistributedDustToTreasuryAndTreasuryWithdrawsIt() external {
        // 7e18 staked against a 99e17 staker pool leaves 1 wei of accumulator rounding dust.
        _stake(STAKER_ONE, 7e18);
        _depositUsdc(address(this), 100e18);

        uint256 dust = splitter.undistributedDustUsdc();
        assertEq(dust, 1);
        assertEq(splitter.previewClaimableUSDC(STAKER_ONE), STAKER_POOL - dust);

        uint256 reservedBefore = splitter.reservedUsdc();
        uint256 surplusBefore = splitter.surplusUsdc();

        vm.expectEmit(true, true, true, true, address(splitter));
        emit LiveStakeFeePoolSplitter.USDCDustReassigned(dust, TREASURY);
        vm.prank(TREASURY);
        splitter.reassignUndistributedDustToTreasury(dust);

        assertEq(splitter.undistributedDustUsdc(), 0);
        assertEq(splitter.treasuryReservedUsdc(), TREASURY_LANE + dust);
        assertEq(splitter.reservedUsdc(), reservedBefore);
        assertEq(splitter.surplusUsdc(), surplusBefore);

        vm.prank(TREASURY);
        splitter.sweepTreasuryUSDC(TREASURY_LANE + dust);

        assertEq(usdc.balanceOf(TREASURY), TREASURY_LANE + dust);
        assertEq(splitter.treasuryReservedUsdc(), 0);
    }

    function testDustReassignmentRevertsOnZeroExcessAndNonOwner() external {
        _stake(STAKER_ONE, 7e18);
        _depositUsdc(address(this), 100e18);
        assertEq(splitter.undistributedDustUsdc(), 1);

        vm.prank(TREASURY);
        vm.expectRevert("AMOUNT_ZERO");
        splitter.reassignUndistributedDustToTreasury(0);

        vm.prank(TREASURY);
        vm.expectRevert("DUST_BALANCE_LOW");
        splitter.reassignUndistributedDustToTreasury(2);

        vm.prank(STAKER_ONE);
        vm.expectRevert("ONLY_OWNER");
        splitter.reassignUndistributedDustToTreasury(1);
    }

    function testRegistryTreasuryIsImmutableAndRevenueKeepsFlowing() external {
        bytes32 liveSubjectId = keccak256("live-subject-rotation");
        address newSafe = address(0x7777);
        MintableERC20Mock rotationStakeToken = new MintableERC20Mock("Rotation Agent", "ROT");
        MintableERC20Mock regent = new MintableERC20Mock("REGENT", "REGENT");
        RegentRevenueStaking staking = new RegentRevenueStaking(
            address(regent), address(usdc), TREASURY, 1_000_000e18, address(this)
        );
        RegentStakingRevenueRouter router = new RegentStakingRevenueRouter(
            address(this), address(usdc), address(subjectRegistry), address(staking)
        );
        router.setMaxUsdcPerSettlement(1000e18);
        LiveStakeFeePoolSplitter rotationSplitter = new LiveStakeFeePoolSplitter(
            address(rotationStakeToken),
            address(usdc),
            address(ingressFactory),
            address(subjectRegistry),
            liveSubjectId,
            TREASURY,
            address(router),
            1000,
            "Live subject",
            TREASURY
        );
        address predictedIngress = ingressFactory.predictDefaultIngress(liveSubjectId, TREASURY);
        _register(
            liveSubjectId, address(rotationStakeToken), address(rotationSplitter), predictedIngress
        );
        RevenueIngressAccount rotationIngress = RevenueIngressAccount(
            payable(ingressFactory.createDefaultIngressAccount(
                    liveSubjectId, "default-usdc-ingress"
                ))
        );

        // Protocol skim accrued BEFORE the registry treasury rotation.
        usdc.mint(address(this), 100e18);
        usdc.approve(address(rotationSplitter), 100e18);
        rotationSplitter.depositUSDC(100e18, bytes32("direct"), bytes32("pre-rotation"));
        assertEq(usdc.balanceOf(address(staking)), PROTOCOL_SKIM);

        // The registered Agent Safe and splitter are immutable.
        vm.expectRevert("SUBJECT_IMMUTABLE");
        subjectRegistry.updateSubject(
            liveSubjectId, address(rotationSplitter), newSafe, true, "Live subject"
        );

        // Deposits and ingress sweeps still succeed after the rotation.
        usdc.mint(address(this), 100e18);
        usdc.approve(address(rotationSplitter), 100e18);
        rotationSplitter.depositUSDC(100e18, bytes32("direct"), bytes32("post-rotation"));

        usdc.mint(address(rotationIngress), 50e18);
        rotationIngress.sweepUSDC(bytes32("post-rotation-sweep"));

        // Protocol fee accrued into Regent staking on 100 + 100 + 50 = 250 USDC -> 2.5 skim.
        assertEq(usdc.balanceOf(address(staking)), 25e17);
        assertEq(staking.totalUsdcReceived(), 25e17);
        // No market-bought REGENT reaches any treasury under the direct-distribution model.
        assertEq(regent.balanceOf(newSafe), 0);
        assertEq(regent.balanceOf(TREASURY), 0);
    }

    function _stake(address account, uint256 amount) internal {
        stakeToken.mint(account, 1000e18);
        vm.prank(account);
        stakeToken.approve(address(splitter), amount);
        vm.prank(account);
        splitter.stake(amount, account);
    }

    function _register(bytes32 id, address token, address subjectSplitter, address subjectIngress)
        internal
    {
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        subjectRegistry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: id,
                stakeToken: token,
                splitter: subjectSplitter,
                agentSafe: TREASURY,
                ingress: subjectIngress,
                paymentLinkFactory: address(0x1002),
                strategy: address(0x1003),
                launchFeeRegistry: address(0x1004),
                feeVault: address(0x1005),
                feeHook: address(0x1006),
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                label: "Live subject",
                safeRuntime: address(0x7007)
            })
        );
    }

    function _depositUsdc(address depositor, uint256 amount) internal {
        usdc.mint(depositor, amount);
        vm.prank(depositor);
        usdc.approve(address(splitter), amount);
        vm.prank(depositor);
        splitter.depositUSDC(amount, bytes32("direct"), bytes32("source"));
    }
}
