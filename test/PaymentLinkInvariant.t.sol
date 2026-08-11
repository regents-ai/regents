// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
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

contract PaymentLinkHandler {
    MintableERC20Mock internal immutable usdc;
    PaymentLinkReceiver internal immutable receiver;

    uint256 public totalGross;
    uint256 public totalReferral;
    uint256 public totalNet;
    uint256 public totalProtocol;
    uint256 private sequence;

    constructor(MintableERC20Mock usdc_, PaymentLinkReceiver receiver_) {
        usdc = usdc_;
        receiver = receiver_;
    }

    function fundAndSweep(uint96 rawAmount) external {
        uint256 gross = (uint256(rawAmount) % 1_000_000_000) + 1;
        uint256 referral = (gross * receiver.referralBps()) / 10_000;
        uint256 net = gross - referral;

        usdc.mint(address(receiver), gross);
        receiver.sweepUSDC(keccak256(abi.encode(sequence++)));

        totalGross += gross;
        totalReferral += referral;
        totalNet += net;
        RevenueShareSplitterV2 splitter = RevenueShareSplitterV2(receiver.destination());
        totalProtocol +=
            (net * splitter.stakingRevenueRouter().protocolSkimBps()) / splitter.BPS_DENOMINATOR();
    }
}

contract PaymentLinkInvariant is StdInvariant, Test {
    address internal constant GOVERNANCE = address(0xA11CE);
    address internal constant LAUNCH_CONTROLLER = address(0xB0B);
    address internal constant BENEFICIARY = address(0xBEEF);
    address internal constant AGENT_SAFE = address(0x1234);
    address internal constant INGRESS_FACTORY = address(0x3333);
    bytes32 internal constant SUBJECT_ID = keccak256("payment-link-invariant-subject");
    uint16 internal constant REFERRAL_BPS = 137;

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    MockRegentStakingRevenueRouter internal feeRouter;
    PaymentLinkFactory internal paymentLinkFactory;
    PaymentLinkReceiver internal receiver;
    RevenueShareSplitterV2 internal splitter;
    PaymentLinkHandler internal handler;

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

        vm.prank(LAUNCH_CONTROLLER);
        receiver = PaymentLinkReceiver(
            payable(paymentLinkFactory.createPaymentLink(
                    SUBJECT_ID, BENEFICIARY, REFERRAL_BPS, "Invariant", keccak256("invariant")
                ))
        );
        handler = new PaymentLinkHandler(usdc, receiver);
        targetContract(address(handler));
    }

    function invariantImmutableRoutesAndAuthorityNeverChange() external view {
        assertEq(receiver.subjectId(), SUBJECT_ID);
        assertEq(receiver.usdc(), address(usdc));
        assertEq(receiver.agentSafe(), AGENT_SAFE);
        assertEq(receiver.controller(), LAUNCH_CONTROLLER);
        assertEq(receiver.creator(), LAUNCH_CONTROLLER);
        assertEq(receiver.beneficiary(), BENEFICIARY);
        assertEq(receiver.referralBps(), REFERRAL_BPS);
        assertEq(receiver.destination(), address(splitter));
        assertFalse(receiver.canonical());
    }

    function invariantGrossAlwaysEqualsReferralPlusFrozenSplitterNet() external view {
        assertEq(handler.totalGross(), handler.totalReferral() + handler.totalNet());
        assertEq(usdc.balanceOf(address(receiver)), 0);
        assertEq(usdc.balanceOf(BENEFICIARY), handler.totalReferral());
        assertEq(splitter.directDepositUsdc(), handler.totalNet());
        assertEq(feeRouter.totalUsdcProcessed(), handler.totalProtocol());
        assertEq(
            usdc.balanceOf(address(splitter)) + handler.totalProtocol(), handler.totalNet()
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
