// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {LiveStakeFeePoolSplitter} from "src/autolaunch/revenue/LiveStakeFeePoolSplitter.sol";
import {PaymentLinkFactory} from "src/autolaunch/revenue/PaymentLinkFactory.sol";
import {PaymentLinkReceiver} from "src/autolaunch/revenue/PaymentLinkReceiver.sol";
import {RevenueIngressAccount} from "src/autolaunch/revenue/RevenueIngressAccount.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";

/// @notice Regression test for FIX A (regent-bemd): a DEACTIVATED receiver holding USDC must
///         still be able to sweep its balance to the subject's canonical splitter. Deactivation
///         only blocks NEW deposits; it must never strand held USDC. Covers both receiver types
///         and the splitter-side `_isKnownIngress` acceptance of a deactivated ingress.
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
        subjectRegistry = new SubjectRegistry(address(this));
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
        subjectRegistry.createPermissionlessSubject(
            SUBJECT_ID,
            address(stakeToken),
            address(splitter),
            TREASURY,
            CREATOR,
            true,
            "Fix A subject"
        );
        paymentFactory =
            new PaymentLinkFactory(address(this), address(usdc), address(subjectRegistry));
    }

    function testDeactivatedIngressCanStillSweepHeldUsdc() external {
        vm.prank(TREASURY);
        RevenueIngressAccount ingress = RevenueIngressAccount(
            payable(ingressFactory.createIngressAccount(SUBJECT_ID, "ingress", true))
        );

        // USDC arrives (e.g. a raw ERC20 transfer to the ingress address).
        usdc.mint(address(ingress), 100e18);

        // The subject manager deactivates the ingress while it still holds funds.
        vm.prank(TREASURY);
        ingressFactory.setIngressReceiverState(SUBJECT_ID, address(ingress), false, address(0));
        assertFalse(ingress.isReceiverActive(), "ingress should be deactivated");

        // New deposits are blocked...
        usdc.mint(PAYER, 1e18);
        vm.prank(PAYER);
        usdc.approve(address(ingress), 1e18);
        vm.prank(PAYER);
        vm.expectRevert("RECEIVER_INACTIVE");
        ingress.depositUSDC(1e18, bytes32("blocked"));

        // ...but the held balance can still be swept to the canonical splitter (FIX A).
        (uint256 balance, uint256 recognized) = ingress.sweepUSDC(bytes32("rescue-sweep"));
        assertEq(balance, 100e18, "full held balance forwarded");
        assertEq(recognized, 100e18, "splitter recognized the swept USDC");
        assertEq(usdc.balanceOf(address(ingress)), 0, "no USDC stranded in the ingress");
        assertEq(splitter.verifiedIngressUsdc(), 100e18, "credited as verified ingress revenue");
    }

    function testDeactivatedPaymentLinkReceiverCanStillSweepHeldUsdc() external {
        vm.prank(CREATOR);
        PaymentLinkReceiver receiver = PaymentLinkReceiver(
            payable(paymentFactory.createPaymentLink(SUBJECT_ID, "link", bytes32("salt1")))
        );

        // USDC arrives via a raw ERC20 transfer to the link address.
        usdc.mint(address(receiver), 100e18);

        // Deactivate the receiver while it holds funds.
        paymentFactory.setPaymentLinkReceiverState(address(receiver), false, address(0));
        assertFalse(receiver.isReceiverActive(), "receiver should be deactivated");

        // New deposits are blocked...
        usdc.mint(PAYER, 1e18);
        vm.prank(PAYER);
        usdc.approve(address(receiver), 1e18);
        vm.prank(PAYER);
        vm.expectRevert("RECEIVER_INACTIVE");
        receiver.depositUSDC(1e18, bytes32("blocked"));

        // ...but the held balance can still be swept to the canonical splitter (FIX A).
        (uint256 balance, uint256 recognized) = receiver.sweepUSDC(bytes32("rescue-sweep"));
        assertEq(balance, 100e18, "full held balance forwarded");
        assertEq(recognized, 100e18, "splitter recognized the swept USDC");
        assertEq(usdc.balanceOf(address(receiver)), 0, "no USDC stranded in the receiver");
        assertEq(splitter.directDepositUsdc(), 100e18, "credited as direct deposit revenue");
    }
}
