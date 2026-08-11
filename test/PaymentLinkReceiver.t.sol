// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {PaymentLinkFactory} from "src/autolaunch/revenue/PaymentLinkFactory.sol";
import {PaymentLinkReceiver} from "src/autolaunch/revenue/PaymentLinkReceiver.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";

contract PaymentLinkReceiverTest is Test {
    address internal constant GOVERNANCE = address(0xA11CE);
    address internal constant LAUNCH_CONTROLLER = address(0xB0B);
    address internal constant PAYER = address(0xCAFE);
    address internal constant CALLER = address(0xC011);
    address internal constant BENEFICIARY = address(0xBEEF);
    address internal constant AGENT_SAFE = address(0x1234);
    address internal constant INGRESS_FACTORY = address(0x3333);
    bytes32 internal constant SUBJECT_ID = keccak256("payment-link-receiver-subject");

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    MockRegentStakingRevenueRouter internal feeRouter;
    PaymentLinkFactory internal paymentLinkFactory;
    RevenueShareSplitterV2 internal splitter;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        stakeToken = new MintableERC20Mock("Agent", "AGENT");
        subjectRegistry = new SubjectRegistry(LAUNCH_CONTROLLER, GOVERNANCE, address(0x600D));
        feeRouter = new MockRegentStakingRevenueRouter(address(usdc), address(0x8888));
        RevenueShareFactory revenueFactory = new RevenueShareFactory(
            GOVERNANCE,
            address(usdc),
            subjectRegistry,
            address(feeRouter),
            address(new RevenueShareSplitterV2Deployer())
        );
        paymentLinkFactory =
            new PaymentLinkFactory(GOVERNANCE, address(usdc), address(subjectRegistry));

        vm.prank(LAUNCH_CONTROLLER);
        splitter = RevenueShareSplitterV2(
            revenueFactory.createSubjectSplitter(
                SUBJECT_ID,
                address(stakeToken),
                INGRESS_FACTORY,
                AGENT_SAFE,
                address(feeRouter),
                1_000_000e18,
                "Agent",
                0,
                address(0),
                0
            )
        );
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        vm.prank(LAUNCH_CONTROLLER);
        subjectRegistry.registerSubject(_registration());
    }

    function testGrossFirstReferralMathAndPreservedDownstreamProtocolPercent() external {
        PaymentLinkReceiver receiver = _create(BENEFICIARY, 250, "Gross first", "gross-first");
        uint256 gross = 100_000_003;
        uint256 referral = (gross * 250) / 10_000;
        uint256 net = gross - referral;
        uint256 protocolShare =
            (net * feeRouter.protocolSkimBps()) / splitter.BPS_DENOMINATOR();
        uint256 subjectShare = net - protocolShare;

        usdc.mint(address(receiver), gross);
        vm.prank(CALLER);
        (uint256 swept, uint256 recognized) = receiver.sweepUSDC(keccak256("payment"));

        assertEq(swept, gross);
        assertEq(recognized, net);
        assertEq(usdc.balanceOf(BENEFICIARY), referral);
        assertEq(usdc.balanceOf(address(receiver)), 0);
        assertEq(splitter.directDepositUsdc(), net);
        assertEq(usdc.balanceOf(address(splitter)), subjectShare);
        assertEq(feeRouter.totalUsdcProcessed(), protocolShare);
        assertEq(referral + subjectShare + protocolShare, gross);
    }

    function testProductPauseBlocksDepositButNotAlreadyHeldSweep() external {
        PaymentLinkReceiver receiver = _create(BENEFICIARY, 100, "Pause", "pause");

        vm.prank(PAYER);
        vm.expectRevert("ONLY_CONTROLLER");
        receiver.setProductPaused(true);

        vm.prank(LAUNCH_CONTROLLER);
        receiver.setProductPaused(true);
        assertTrue(receiver.productPaused());

        usdc.mint(PAYER, 10e6);
        vm.startPrank(PAYER);
        usdc.approve(address(receiver), 10e6);
        vm.expectRevert("PRODUCT_PAUSED");
        receiver.depositUSDC(10e6, keccak256("blocked-deposit"));
        assertEq(usdc.balanceOf(PAYER), 10e6);
        usdc.transfer(address(receiver), 10e6);
        vm.stopPrank();

        vm.prank(CALLER);
        receiver.sweepUSDC(keccak256("held-sweep"));
        assertEq(usdc.balanceOf(address(receiver)), 0);
        assertEq(usdc.balanceOf(BENEFICIARY), 100_000);
        assertEq(splitter.directDepositUsdc(), 9_900_000);
    }

    function testQuarantineHoldsFullBalance() external {
        PaymentLinkReceiver quarantined = _create(BENEFICIARY, 250, "Quarantine", "quarantine");
        usdc.mint(address(quarantined), 20e6);

        vm.prank(AGENT_SAFE);
        subjectRegistry.quarantineSubject(SUBJECT_ID);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        quarantined.sweepUSDC(keccak256("quarantined"));
        assertEq(usdc.balanceOf(address(quarantined)), 20e6);
        assertEq(usdc.balanceOf(BENEFICIARY), 0);
    }

    function testProtocolPauseHoldsFullBalance() external {
        PaymentLinkReceiver protocolPaused =
            _create(BENEFICIARY, 250, "Protocol pause", "protocol-pause");
        usdc.mint(address(protocolPaused), 30e6);
        vm.prank(splitter.owner());
        splitter.setPaused(true);

        vm.expectRevert("PAUSED");
        protocolPaused.sweepUSDC(keccak256("protocol-paused"));
        assertEq(usdc.balanceOf(address(protocolPaused)), 30e6);
        assertEq(usdc.balanceOf(BENEFICIARY), 0);
    }

    function testSweepRollbackWhenBeneficiaryRejectsAndOtherLinkStillSweeps() external {
        PaymentLinkReceiver failing = _create(BENEFICIARY, 250, "Failing", "failing-beneficiary");
        PaymentLinkReceiver healthy =
            _create(address(0xF00D), 250, "Healthy", "healthy-beneficiary");
        uint256 gross = 40e6;
        uint256 referral = (gross * 250) / 10_000;
        usdc.mint(address(failing), gross);
        usdc.mint(address(healthy), gross);

        vm.mockCallRevert(
            address(usdc),
            abi.encodeWithSignature("transfer(address,uint256)", BENEFICIARY, referral),
            "BENEFICIARY_REJECTED"
        );
        vm.expectRevert("TRANSFER_FAILED");
        failing.sweepUSDC(keccak256("failing"));

        assertEq(usdc.balanceOf(address(failing)), gross);
        assertEq(usdc.balanceOf(BENEFICIARY), 0);
        healthy.sweepUSDC(keccak256("healthy"));
        assertEq(usdc.balanceOf(address(healthy)), 0);
        assertEq(usdc.balanceOf(address(0xF00D)), referral);
    }

    function testSweepRollbackWhenSplitterRejectsAndFailureIsIsolatedPerLink() external {
        PaymentLinkReceiver failing = _create(BENEFICIARY, 0, "Failing", "failing-splitter");
        PaymentLinkReceiver healthy = _create(BENEFICIARY, 0, "Healthy", "healthy-splitter");
        uint256 gross = 50e6;
        usdc.mint(address(failing), gross);
        usdc.mint(address(healthy), gross);

        vm.mockCallRevert(
            address(usdc),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", address(failing), address(splitter), gross
            ),
            "SPLITTER_TRANSFER_REJECTED"
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        failing.sweepUSDC(keccak256("failing"));

        assertEq(usdc.balanceOf(address(failing)), gross);
        healthy.sweepUSDC(keccak256("healthy"));
        assertEq(usdc.balanceOf(address(healthy)), 0);
        assertEq(splitter.directDepositUsdc(), gross);
    }

    function testControllerCanOnlyChangeMetadataAndProductPause() external {
        PaymentLinkReceiver receiver = _create(BENEFICIARY, 250, "Original", "authority");

        vm.prank(LAUNCH_CONTROLLER);
        receiver.setLabel("Updated");
        vm.prank(LAUNCH_CONTROLLER);
        receiver.setProductPaused(true);
        assertEq(receiver.label(), "Updated");
        assertTrue(receiver.productPaused());

        vm.prank(LAUNCH_CONTROLLER);
        vm.expectRevert("PAYMENT_LINK_IMMUTABLE");
        receiver.setReceiverState(false, LAUNCH_CONTROLLER);

        bytes[] memory forbidden = new bytes[](4);
        forbidden[0] = abi.encodeWithSignature("setBeneficiary(address)", LAUNCH_CONTROLLER);
        forbidden[1] = abi.encodeWithSignature("setDestination(address)", LAUNCH_CONTROLLER);
        forbidden[2] = abi.encodeWithSignature("withdraw(address,uint256)", LAUNCH_CONTROLLER, 1);
        forbidden[3] = abi.encodeWithSignature(
            "rescueUnsupportedToken(address,uint256,address)", address(usdc), 1, LAUNCH_CONTROLLER
        );
        for (uint256 i; i < forbidden.length; ++i) {
            vm.prank(LAUNCH_CONTROLLER);
            (bool success,) = address(receiver).call(forbidden[i]);
            assertFalse(success);
        }

        assertEq(receiver.beneficiary(), BENEFICIARY);
        assertEq(receiver.referralBps(), 250);
        assertEq(receiver.destination(), address(splitter));
    }

    function _create(
        address beneficiary,
        uint16 referralBps,
        string memory label,
        string memory salt
    ) internal returns (PaymentLinkReceiver receiver) {
        vm.prank(LAUNCH_CONTROLLER);
        receiver = PaymentLinkReceiver(
            payable(paymentLinkFactory.createPaymentLink(
                    SUBJECT_ID, beneficiary, referralBps, label, keccak256(bytes(salt))
                ))
        );
    }

    function _registration() internal view returns (ISubjectRegistry.SubjectRegistration memory) {
        return ISubjectRegistry.SubjectRegistration({
            subjectId: SUBJECT_ID,
            stakeToken: address(stakeToken),
            splitter: address(splitter),
            agentSafe: AGENT_SAFE,
            ingress: INGRESS_FACTORY,
            paymentLinkFactory: address(paymentLinkFactory),
            strategy: address(0x1003),
            launchFeeRegistry: address(0x1004),
            feeVault: address(0x1005),
            feeHook: address(0x1006),
            identityChainId: 0,
            identityRegistry: address(0),
            identityAgentId: 0,
            label: "Agent",
            safeRuntime: address(0x7007)
        });
    }
}
