// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {LiveStakeFeePoolSplitter} from "src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol";
import {PaymentLinkFactory} from "src/autolaunch/revenue/PaymentLinkFactory.sol";
import {PaymentLinkReceiver} from "src/autolaunch/revenue/PaymentLinkReceiver.sol";
import {RevenueIngressAccount} from "src/autolaunch/revenue/RevenueIngressAccount.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";

/// @notice Regression proof that receiver redirection is disabled and subject quarantine blocks
///         both new deposits and held-balance sweeps before any transfer side effect.
contract PoCReceiverDeactivationSweep is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("fixA-subject");
    address internal constant TREASURY = address(0x1111);
    address internal constant CREATOR = address(0x2222);
    address internal constant PAYER = address(0x5555);

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    RevenueIngressFactory internal ingressFactory;
    PaymentLinkFactory internal paymentFactory;
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
            1000,
            "Fix A subject",
            TREASURY
        );
        paymentFactory =
            new PaymentLinkFactory(address(this), address(usdc), address(subjectRegistry));
        address predictedIngress = ingressFactory.predictDefaultIngress(SUBJECT_ID, TREASURY);
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        subjectRegistry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: SUBJECT_ID,
                stakeToken: address(stakeToken),
                splitter: address(splitter),
                agentSafe: TREASURY,
                ingress: predictedIngress,
                paymentLinkFactory: address(paymentFactory),
                strategy: address(0x1003),
                launchFeeRegistry: address(0x1004),
                feeVault: address(0x1005),
                feeHook: address(0x1006),
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                label: "Fix A subject",
                safeRuntime: address(0x7007)
            })
        );
    }

    function testQuarantinedIngressCannotSweepHeldUsdc() external {
        RevenueIngressAccount ingress = RevenueIngressAccount(
            payable(ingressFactory.createDefaultIngressAccount(SUBJECT_ID, "default-usdc-ingress"))
        );

        // USDC arrives (e.g. a raw ERC20 transfer to the ingress address).
        usdc.mint(address(ingress), 100e18);

        vm.expectRevert("INGRESS_IMMUTABLE");
        ingressFactory.setIngressReceiverState(SUBJECT_ID, address(ingress), false, address(0));
        assertTrue(ingress.isReceiverActive(), "ingress state is immutable");

        vm.prank(TREASURY);
        subjectRegistry.quarantineSubject(SUBJECT_ID);

        // New deposits are blocked...
        usdc.mint(PAYER, 1e18);
        vm.prank(PAYER);
        usdc.approve(address(ingress), 1e18);
        vm.prank(PAYER);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        ingress.depositUSDC(1e18, bytes32("blocked"));

        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        ingress.sweepUSDC(bytes32("blocked-sweep"));
        assertEq(usdc.balanceOf(address(ingress)), 100e18, "quarantine blocks the transfer");
        assertEq(splitter.verifiedIngressUsdc(), 0);
    }

    function testQuarantinedPaymentLinkCannotSweepHeldUsdc() external {
        vm.prank(CREATOR);
        PaymentLinkReceiver receiver = PaymentLinkReceiver(
            payable(paymentFactory.createPaymentLink(SUBJECT_ID, "link", bytes32("salt1")))
        );

        // USDC arrives via a raw ERC20 transfer to the link address.
        usdc.mint(address(receiver), 100e18);

        vm.expectRevert("PAYMENT_LINK_IMMUTABLE");
        paymentFactory.setPaymentLinkReceiverState(address(receiver), false, address(0));
        assertTrue(receiver.isReceiverActive(), "receiver state is immutable");

        vm.prank(TREASURY);
        subjectRegistry.quarantineSubject(SUBJECT_ID);

        // New deposits are blocked...
        usdc.mint(PAYER, 1e18);
        vm.prank(PAYER);
        usdc.approve(address(receiver), 1e18);
        vm.prank(PAYER);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        receiver.depositUSDC(1e18, bytes32("blocked"));

        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        receiver.sweepUSDC(bytes32("blocked-sweep"));
        assertEq(usdc.balanceOf(address(receiver)), 100e18, "quarantine blocks the transfer");
        assertEq(splitter.directDepositUsdc(), 0);
    }
}
