// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {RegentStakingRevenueRouter} from "src/autolaunch/revenue/RegentStakingRevenueRouter.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

contract NoPullStakingMock {
    address public immutable usdc;

    constructor(address usdc_) {
        usdc = usdc_;
    }

    function depositUSDC(uint256 amount, bytes32, bytes32) external pure returns (uint256) {
        return amount;
    }
}

contract RegentStakingRevenueRouterTest is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("subject");
    address internal constant OWNER = address(0xA11CE);
    address internal constant TREASURY = address(0x1111);
    address internal constant OTHER_TREASURY = address(0x2222);
    address internal constant OTHER_SPLITTER = address(0xDEAD);
    uint256 internal constant USDC_FEE = 100e6;

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal regent;
    SubjectRegistry internal subjectRegistry;
    RegentRevenueStaking internal staking;
    RegentStakingRevenueRouter internal router;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        regent = new MintableERC20Mock("REGENT", "REGENT");
        subjectRegistry = new SubjectRegistry(address(this), OWNER, address(0x600D));
        staking =
            new RegentRevenueStaking(address(regent), address(usdc), TREASURY, 1_000_000e18, OWNER);
        router = new RegentStakingRevenueRouter(
            OWNER, address(usdc), address(subjectRegistry), address(staking)
        );

        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        subjectRegistry.registerSubject(_registration());
    }

    function testRouterAcceptsFeeOnlyFromRegisteredSubjectSplitter() external {
        usdc.mint(address(router), USDC_FEE);

        vm.prank(OTHER_SPLITTER);
        vm.expectRevert("ONLY_SUBJECT_SPLITTER");
        router.processProtocolFee(SUBJECT_ID, USDC_FEE, bytes32("source"));
    }

    function testRouterKeepsUsingImmutableRegisteredTreasury() external {
        usdc.mint(address(router), USDC_FEE);

        vm.prank(OWNER);
        vm.expectRevert("SUBJECT_IMMUTABLE");
        subjectRegistry.updateSubject(SUBJECT_ID, address(this), OTHER_TREASURY, true, "Subject");

        uint256 deposited = router.processProtocolFee(SUBJECT_ID, USDC_FEE, bytes32("source"));

        assertEq(deposited, USDC_FEE);
        assertEq(usdc.balanceOf(address(staking)), USDC_FEE);
    }

    function _registration() internal view returns (ISubjectRegistry.SubjectRegistration memory) {
        return ISubjectRegistry.SubjectRegistration({
            subjectId: SUBJECT_ID,
            stakeToken: address(0xBEEF),
            splitter: address(this),
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
        });
    }

    function testRouterRejectsZeroAmount() external {
        vm.expectRevert("AMOUNT_ZERO");
        router.processProtocolFee(SUBJECT_ID, 0, bytes32("source"));
    }

    function testRouterRejectsSettlementLargerThanMax() external {
        uint256 tooLarge = router.maxUsdcPerSettlement() + 1;
        usdc.mint(address(router), tooLarge);

        vm.expectRevert("SETTLEMENT_TOO_LARGE");
        router.processProtocolFee(SUBJECT_ID, tooLarge, bytes32("source"));
    }

    function testRouterRejectsStakingUsdcMismatch() external {
        MintableERC20Mock otherUsdc = new MintableERC20Mock("Other USD", "oUSD");

        vm.expectRevert("STAKING_USDC_MISMATCH");
        new RegentStakingRevenueRouter(
            OWNER, address(otherUsdc), address(subjectRegistry), address(staking)
        );
    }

    function testRouterDepositsUsdcIntoRegentRevenueStaking() external {
        usdc.mint(address(router), USDC_FEE);

        uint256 deposited = router.processProtocolFee(SUBJECT_ID, USDC_FEE, bytes32("source"));

        assertEq(deposited, USDC_FEE);
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(usdc.balanceOf(address(staking)), USDC_FEE);
        assertEq(staking.totalUsdcReceived(), USDC_FEE);
        assertEq(router.totalUsdcSettled(), USDC_FEE);
        assertEq(router.totalUsdcDepositedToRegentStaking(), USDC_FEE);
        assertEq(usdc.allowance(address(router), address(staking)), 0);
    }

    function testRouterRejectsExactReturnWithoutExactTokenTransfer() external {
        NoPullStakingMock noPullStaking = new NoPullStakingMock(address(usdc));
        RegentStakingRevenueRouter noPullRouter = new RegentStakingRevenueRouter(
            OWNER, address(usdc), address(subjectRegistry), address(noPullStaking)
        );
        usdc.mint(address(noPullRouter), USDC_FEE);

        vm.expectRevert("STAKING_TRANSFER_INEXACT");
        noPullRouter.processProtocolFee(SUBJECT_ID, USDC_FEE, bytes32("source"));

        assertEq(usdc.balanceOf(address(noPullRouter)), USDC_FEE);
        assertEq(usdc.allowance(address(noPullRouter), address(noPullStaking)), 0);
    }

    function testRouterRevertsIfStakingIsPaused() external {
        vm.prank(OWNER);
        staking.setPaused(true);

        usdc.mint(address(router), USDC_FEE);

        vm.expectRevert("PAUSED");
        router.processProtocolFee(SUBJECT_ID, USDC_FEE, bytes32("source"));
    }

    function testRouterUsesFixedProtocolSkim() external view {
        assertEq(router.protocolSkimBps(), 100);
    }

    function testMaxUsdcPerSettlementIsFixedAtTwoThousandTokenUnits() external {
        uint256 fixedCap = 2000e6;
        assertEq(router.maxUsdcPerSettlement(), fixedCap);

        vm.prank(OWNER);
        vm.expectRevert("CAP_IMMUTABLE");
        router.setMaxUsdcPerSettlement(1000e6);
        assertEq(router.maxUsdcPerSettlement(), fixedCap);
    }

    /// @notice The market-buyback surface has been removed by construction: the router no longer
    ///         exposes any buyback record/settle/oracle/adapter selectors, so there is no
    ///         settle-time market price for anyone to manipulate.
    function testNoBuybackSurfaceRemains() external {
        // treasuryBuybackBps() selector removed
        (bool ok,) = address(router).staticcall(abi.encodeWithSignature("treasuryBuybackBps()"));
        assertFalse(ok);
        // pendingTreasuryBuybackUsdc(bytes32) selector removed
        (ok,) = address(router)
            .staticcall(abi.encodeWithSignature("pendingTreasuryBuybackUsdc(bytes32)", SUBJECT_ID));
        assertFalse(ok);
        // buybackAdapter() selector removed
        (ok,) = address(router).staticcall(abi.encodeWithSignature("buybackAdapter()"));
        assertFalse(ok);
        // settleTreasuryBuyback(...) selector removed
        (ok,) = address(router)
            .call(
                abi.encodeWithSignature(
                    "settleTreasuryBuyback(bytes32,uint256,uint256,bytes32)",
                    SUBJECT_ID,
                    USDC_FEE,
                    uint256(1),
                    bytes32("x")
                )
            );
        assertFalse(ok);
        // recordTreasuryBuyback(...) selector removed
        (ok,) = address(router)
            .call(
                abi.encodeWithSignature(
                    "recordTreasuryBuyback(bytes32,uint256,bytes32)",
                    SUBJECT_ID,
                    USDC_FEE,
                    bytes32("x")
                )
            );
        assertFalse(ok);
    }
}
