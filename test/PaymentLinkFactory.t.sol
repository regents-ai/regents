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

contract PaymentLinkFactoryTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant CREATOR = address(0xB0B);
    address internal constant PAYER = address(0xCAFE);
    address internal constant TREASURY = address(0x1234);
    address internal constant INGRESS_FACTORY = address(0x3333);
    bytes32 internal constant SUBJECT_ID = keccak256("payment-link-subject");

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    RevenueShareFactory internal revenueShareFactory;
    RevenueShareSplitterV2Deployer internal splitterDeployer;
    MockRegentStakingRevenueRouter internal feeRouter;
    PaymentLinkFactory internal paymentLinkFactory;
    address internal splitter;

    event PaymentLinkCreated(
        bytes32 indexed subjectId,
        address indexed receiver,
        address indexed creator,
        address controller,
        address beneficiary,
        uint16 referralBps,
        address splitter,
        string label,
        bool canonical
    );

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        stakeToken = new MintableERC20Mock("Agent", "AGENT");
        subjectRegistry = new SubjectRegistry(CREATOR, OWNER, address(0x600D));
        feeRouter = new MockRegentStakingRevenueRouter(address(usdc), address(0x8888));
        splitterDeployer = new RevenueShareSplitterV2Deployer();
        revenueShareFactory = new RevenueShareFactory(
            OWNER, address(usdc), subjectRegistry, address(feeRouter), address(splitterDeployer)
        );
        paymentLinkFactory = new PaymentLinkFactory(OWNER, address(usdc), address(subjectRegistry));

        vm.prank(CREATOR);
        splitter = revenueShareFactory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY,
            address(feeRouter),
            1_000_000e18,
            "Agent",
            0,
            address(0),
            0
        );
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        vm.prank(CREATOR);
        subjectRegistry.registerSubject(_registration());
    }

    function testCreatesReceiverAndSweepsSimpleTransfers() external {
        vm.prank(CREATOR);
        address receiverAddress =
            paymentLinkFactory.createPaymentLink(SUBJECT_ID, "Sponsor", keccak256("sponsor"));

        PaymentLinkReceiver receiver = PaymentLinkReceiver(payable(receiverAddress));
        assertEq(receiver.destination(), splitter);
        assertEq(receiver.creator(), CREATOR);
        assertEq(receiver.controller(), CREATOR);
        assertEq(receiver.beneficiary(), CREATOR);
        assertEq(receiver.referralBps(), 0);
        assertTrue(paymentLinkFactory.isPaymentLink(receiverAddress));
        assertEq(paymentLinkFactory.canonicalPaymentLinkCountForSubject(SUBJECT_ID), 0);
        assertEq(paymentLinkFactory.paymentLinkForCreatorAt(CREATOR, 0), receiverAddress);

        usdc.mint(PAYER, 100e6);
        vm.prank(PAYER);
        usdc.transfer(receiverAddress, 100e6);

        receiver.sweepUSDC(bytes32("payment-ref"));

        assertEq(usdc.balanceOf(receiverAddress), 0);
        assertEq(RevenueShareSplitterV2(splitter).directDepositUsdc(), 100e6);
    }

    function testDepositUSDCRecordsMetadataAndForwardsFullBalance() external {
        vm.prank(CREATOR);
        PaymentLinkReceiver receiver = PaymentLinkReceiver(
            payable(paymentLinkFactory.createPaymentLink(
                    SUBJECT_ID, "Invoice", keccak256("invoice")
                ))
        );

        usdc.mint(PAYER, 25e6);
        vm.startPrank(PAYER);
        usdc.approve(address(receiver), 25e6);
        (uint256 received, uint256 recognized) = receiver.depositUSDC(25e6, keccak256("ref-1"));
        vm.stopPrank();

        assertEq(received, 25e6);
        assertEq(recognized, 25e6);
        assertEq(usdc.balanceOf(address(receiver)), 0);
        assertEq(RevenueShareSplitterV2(splitter).directDepositUsdc(), 25e6);
    }

    function testControllerCreatesCanonicalPaymentLink() external {
        address predicted = _predictedReceiver(
            CREATOR, TREASURY, TREASURY, 0, "Displayed", keccak256("displayed"), true
        );

        vm.expectEmit(true, true, true, true, address(paymentLinkFactory));
        emit PaymentLinkCreated(
            SUBJECT_ID, predicted, CREATOR, TREASURY, TREASURY, 0, splitter, "Displayed", true
        );
        vm.prank(CREATOR);
        address receiverAddress = paymentLinkFactory.createCanonicalPaymentLink(
            SUBJECT_ID, "Displayed", keccak256("displayed")
        );

        PaymentLinkReceiver receiver = PaymentLinkReceiver(payable(receiverAddress));
        assertEq(receiverAddress, predicted);
        assertEq(receiver.creator(), paymentLinkFactory.controller());
        assertEq(receiver.controller(), TREASURY);
        assertEq(receiver.agentSafe(), TREASURY);
        assertEq(receiver.beneficiary(), TREASURY);
        assertEq(receiver.referralBps(), 0);
        assertTrue(receiver.canonical());
        assertEq(receiver.destination(), splitter);
        assertEq(paymentLinkFactory.canonicalPaymentLinkCountForSubject(SUBJECT_ID), 1);
        assertEq(
            paymentLinkFactory.canonicalPaymentLinkForSubjectAt(SUBJECT_ID, 0), receiverAddress
        );

        vm.prank(CREATOR);
        vm.expectRevert("CANONICAL_LINK_EXISTS");
        paymentLinkFactory.createCanonicalPaymentLink(
            SUBJECT_ID, "Duplicate", keccak256("duplicate")
        );

        vm.prank(PAYER);
        vm.expectRevert("ONLY_CONTROLLER");
        paymentLinkFactory.createCanonicalPaymentLink(
            SUBJECT_ID, "Arbitrary", keccak256("arbitrary")
        );
    }

    function testPermissionlessCreatorAndControllerIdentityWithPassiveEoaBeneficiary() external {
        address predicted = _predictedReceiver(
            PAYER, PAYER, CREATOR, 250, "Referral", keccak256("referral"), false
        );
        vm.expectEmit(true, true, true, true, address(paymentLinkFactory));
        emit PaymentLinkCreated(
            SUBJECT_ID, predicted, PAYER, PAYER, CREATOR, 250, splitter, "Referral", false
        );
        vm.prank(PAYER);
        PaymentLinkReceiver receiver = PaymentLinkReceiver(
            payable(paymentLinkFactory.createPaymentLink(
                    SUBJECT_ID, CREATOR, 250, "Referral", keccak256("referral")
                ))
        );

        assertEq(address(receiver), predicted);
        assertEq(receiver.creator(), PAYER);
        assertEq(receiver.controller(), PAYER);
        assertEq(receiver.agentSafe(), TREASURY);
        assertEq(receiver.beneficiary(), CREATOR);
        assertEq(receiver.referralBps(), 250);
        assertFalse(receiver.canonical());
        assertEq(receiver.destination(), splitter);
    }

    function testReferralBoundsAreInclusive() external {
        vm.startPrank(PAYER);
        PaymentLinkReceiver zero = PaymentLinkReceiver(
            payable(paymentLinkFactory.createPaymentLink(
                    SUBJECT_ID, CREATOR, 0, "Zero", keccak256("zero")
                ))
        );
        PaymentLinkReceiver max = PaymentLinkReceiver(
            payable(paymentLinkFactory.createPaymentLink(
                    SUBJECT_ID, CREATOR, 250, "Max", keccak256("max")
                ))
        );
        assertEq(zero.referralBps(), 0);
        assertEq(max.referralBps(), 250);

        vm.expectRevert("REFERRAL_BPS_TOO_HIGH");
        paymentLinkFactory.createPaymentLink(
            SUBJECT_ID, CREATOR, 251, "Too high", keccak256("too-high")
        );
        vm.expectRevert("BENEFICIARY_ZERO");
        paymentLinkFactory.createPaymentLink(
            SUBJECT_ID, address(0), 1, "Zero beneficiary", keccak256("zero-beneficiary")
        );
        vm.stopPrank();
    }

    function testReceiverKeepsImmutableRegisteredSplitter() external {
        vm.prank(CREATOR);
        PaymentLinkReceiver receiver = PaymentLinkReceiver(
            payable(paymentLinkFactory.createPaymentLink(
                    SUBJECT_ID, "Rotating", keccak256("rotating")
                ))
        );

        RevenueShareSplitterV2 nextSplitter = new RevenueShareSplitterV2(
            address(stakeToken),
            address(usdc),
            INGRESS_FACTORY,
            address(subjectRegistry),
            SUBJECT_ID,
            TREASURY,
            address(feeRouter),
            1_000_000e18,
            "Agent v2",
            TREASURY
        );

        vm.prank(TREASURY);
        vm.expectRevert("SUBJECT_IMMUTABLE");
        subjectRegistry.updateSubject(SUBJECT_ID, address(nextSplitter), TREASURY, true, "Agent v2");

        assertEq(receiver.destination(), splitter);

        usdc.mint(PAYER, 10e6);
        vm.startPrank(PAYER);
        usdc.approve(address(receiver), 10e6);
        receiver.depositUSDC(10e6, keccak256("ref-2"));
        vm.stopPrank();

        assertEq(RevenueShareSplitterV2(splitter).directDepositUsdc(), 10e6);
        assertEq(nextSplitter.directDepositUsdc(), 0);
    }

    function testRejectsEthAndHasNoRecoverySurface() external {
        vm.prank(CREATOR);
        PaymentLinkReceiver receiver = PaymentLinkReceiver(
            payable(paymentLinkFactory.createPaymentLink(SUBJECT_ID, "No ETH", keccak256("no-eth")))
        );

        vm.deal(PAYER, 1 ether);
        vm.prank(PAYER);
        (bool success,) = address(receiver).call{value: 1 ether}("");
        assertFalse(success);

        usdc.mint(address(receiver), 1e6);
        (success,) = address(receiver)
            .call(
                abi.encodeWithSignature(
                    "rescueUnsupportedToken(address,uint256,address)", address(usdc), 1e6, CREATOR
                )
            );
        assertFalse(success);
        assertEq(usdc.balanceOf(address(receiver)), 1e6);
    }

    function testRejectsLongLabels() external {
        vm.expectRevert("LABEL_TOO_LONG");
        paymentLinkFactory.createPaymentLink(SUBJECT_ID, _longLabel(), keccak256("long"));
    }

    function _longLabel() internal pure returns (string memory) {
        return "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    }

    function _predictedReceiver(
        address creator,
        address linkController,
        address beneficiary,
        uint16 referralBps,
        string memory label,
        bytes32 salt,
        bool canonical
    ) internal view returns (address) {
        bytes32 deploymentSalt = keccak256(
            abi.encode(
                creator, linkController, beneficiary, referralBps, SUBJECT_ID, salt, canonical
            )
        );
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(PaymentLinkReceiver).creationCode,
                abi.encode(
                    address(usdc),
                    address(subjectRegistry),
                    SUBJECT_ID,
                    splitter,
                    TREASURY,
                    creator,
                    linkController,
                    beneficiary,
                    referralBps,
                    canonical,
                    label
                )
            )
        );
        return vm.computeCreate2Address(deploymentSalt, initCodeHash, address(paymentLinkFactory));
    }

    function _registration() internal view returns (ISubjectRegistry.SubjectRegistration memory) {
        return ISubjectRegistry.SubjectRegistration({
            subjectId: SUBJECT_ID,
            stakeToken: address(stakeToken),
            splitter: splitter,
            agentSafe: TREASURY,
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
