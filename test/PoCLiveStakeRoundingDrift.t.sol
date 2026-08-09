// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {LiveStakeFeePoolSplitter} from "src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";

/// @notice Regression test for FIX B (regent-zfkn): LiveStakeFeePoolSplitter now ports
///         RevenueShareSplitterV2's `claimRoundingReserveUsdc` mechanism. This is the same
///         scenario that previously broke the accounting invariant (a staker's `_sync` floors
///         once over the SUM of several deposits' accumulator deltas, exceeding the per-deposit
///         `creditedByAccumulator` floors). After the fix:
///           - cumulative claims never exceed `totalUsdcCreditedToStakers`;
///           - `reservedUsdc()` / `surplusUsdc()` / `previewTreasuryBalances()` do not revert;
///           - the rounding carry is reserved for stakers, so the treasury cannot reassign it;
///           - after a legitimate treasury sweep the contract stays solvent.
contract PoCLiveStakeRoundingDrift is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("poc-subject");
    address internal constant TREASURY = address(0x1111);
    address internal constant CREATOR = address(0x2222);
    address internal constant STAKER = address(0x3333);

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    RevenueIngressFactory internal ingressFactory;
    MockRegentStakingRevenueRouter internal feeRouter;
    LiveStakeFeePoolSplitter internal splitter;

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
            1000, // stakerPoolBps = 10%
            "PoC subject",
            TREASURY
        );
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        subjectRegistry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: SUBJECT_ID,
                stakeToken: address(stakeToken),
                splitter: address(splitter),
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
                label: "PoC subject",
                safeRuntime: address(0x7007)
            })
        );
    }

    function _stake(uint256 amount) internal {
        stakeToken.mint(STAKER, amount);
        vm.prank(STAKER);
        stakeToken.approve(address(splitter), amount);
        vm.prank(STAKER);
        splitter.stake(amount, STAKER);
    }

    function _deposit(uint256 amount) internal {
        usdc.mint(address(this), amount);
        usdc.approve(address(splitter), amount);
        splitter.depositUSDC(amount, bytes32("direct"), bytes32("src"));
    }

    function testCumulativeClaimNeverExceedsCreditedAndStaysSolvent() external {
        // 7e18 staked makes each 100e18 deposit leave exactly 1 wei of accumulator dust and
        // reserve exactly the rounding carry a merged sync would otherwise over-claim.
        _stake(7e18);

        // TWO deposits WITHOUT the staker syncing in between: the later single sync floors over
        // the SUM of both accumulator deltas — the exact trigger for the old overage.
        _deposit(100e18);
        _deposit(100e18);

        // The staker claims. With the reserve in place, the claim is honored from dust-backed
        // reserve and totalClaimedUsdc cannot push past the tracked credit.
        vm.prank(STAKER);
        uint256 claimed = splitter.claimUSDC(STAKER);
        assertGt(claimed, 0, "staker should be able to claim");

        // INVARIANT RESTORED: cumulative claims never exceed tracked staker credit.
        assertLe(
            splitter.totalClaimedUsdc(),
            splitter.totalUsdcCreditedToStakers(),
            "totalClaimedUsdc must never exceed totalUsdcCreditedToStakers"
        );

        // Views no longer revert (previously underflowed on credited - claimed).
        uint256 reserved = splitter.reservedUsdc();
        uint256 surplus = splitter.surplusUsdc();
        splitter.previewTreasuryBalances();

        // Contract remains solvent: physical balance covers all reserved obligations.
        uint256 balance = usdc.balanceOf(address(splitter));
        assertGe(balance, reserved, "balance must cover reserved obligations");
        assertEq(balance, reserved + surplus, "balance equals reserved + surplus");

        // The rounding carry is reserved for stakers: the treasury cannot reassign the reserved
        // portion of dust.
        uint256 dust = splitter.undistributedDustUsdc();
        uint256 stakerReserve = splitter.claimRoundingReserveUsdc();
        if (stakerReserve > 0) {
            vm.prank(TREASURY);
            vm.expectRevert("DUST_RESERVED_FOR_STAKERS");
            splitter.reassignUndistributedDustToTreasury(dust);
        }

        // The treasury can still sweep everything it legitimately owns, and the contract stays
        // solvent (no revert on the final sweep).
        uint256 treasuryReserved = splitter.treasuryReservedUsdc();
        vm.prank(TREASURY);
        splitter.sweepTreasuryUSDC(treasuryReserved);
        assertEq(splitter.treasuryReservedUsdc(), 0, "treasury swept fully without insolvency");

        // Any remaining reserved dust is still held for stakers (no funds lost).
        assertEq(splitter.undistributedDustUsdc(), dust, "unreassigned dust remains for stakers");
    }
}
