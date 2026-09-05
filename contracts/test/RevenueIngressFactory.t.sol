// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RevenueIngressAccount} from "src/autolaunch/revenue/RevenueIngressAccount.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";

contract RevenueIngressFactoryTest is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("subject");
    address internal constant TREASURY_SAFE = address(0x1111);
    address internal constant AGENT_TREASURY = address(0x2222);
    address internal constant REGENT_RECIPIENT = address(0x3333);

    MintableERC20Mock internal usdc;
    SubjectRegistry internal subjectRegistry;
    RevenueShareFactory internal revenueShareFactory;
    RevenueShareSplitterV2Deployer internal splitterDeployer;
    RevenueIngressFactory internal ingressFactory;
    MockRegentStakingRevenueRouter internal feeRouter;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        subjectRegistry = new SubjectRegistry(address(this), address(0xA11CE), address(0x600D));
        feeRouter = new MockRegentStakingRevenueRouter(address(usdc), address(0x8888));
        splitterDeployer = new RevenueShareSplitterV2Deployer();
        revenueShareFactory = new RevenueShareFactory(
            address(this),
            address(usdc),
            subjectRegistry,
            address(feeRouter),
            address(splitterDeployer)
        );
        ingressFactory =
            new RevenueIngressFactory(address(usdc), address(subjectRegistry), address(this));
        address splitter = revenueShareFactory.createSubjectSplitter(
            SUBJECT_ID,
            address(0xB0B),
            address(ingressFactory),
            TREASURY_SAFE,
            address(feeRouter),
            1000e18,
            "Subject",
            block.chainid,
            address(0x8004),
            42
        );
        address predicted = ingressFactory.predictDefaultIngress(SUBJECT_ID, TREASURY_SAFE);
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        subjectRegistry.registerSubject(_registration(splitter, predicted));
    }

    function testSubjectManagerCreatesDefaultIngress() external {
        address ingress =
            ingressFactory.createDefaultIngressAccount(SUBJECT_ID, "default-usdc-ingress");

        assertEq(ingressFactory.defaultIngressOfSubject(SUBJECT_ID), ingress);
        assertEq(ingressFactory.ingressAccountCount(SUBJECT_ID), 1);
        assertTrue(ingressFactory.isIngressAccount(ingress));
        assertEq(RevenueIngressAccount(payable(ingress)).owner(), TREASURY_SAFE);
        assertEq(RevenueIngressAccount(payable(ingress)).subjectId(), SUBJECT_ID);
    }

    function testQuarantinedSubjectBlocksAdditionalIngressAndDefaultMutation() external {
        address ingressA =
            ingressFactory.createDefaultIngressAccount(SUBJECT_ID, "default-usdc-ingress");

        vm.prank(TREASURY_SAFE);
        subjectRegistry.quarantineSubject(SUBJECT_ID);

        assertEq(ingressFactory.defaultIngressOfSubject(SUBJECT_ID), ingressA);

        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        ingressFactory.createDefaultIngressAccount(SUBJECT_ID, "default-usdc-ingress");

        vm.expectRevert("INGRESS_IMMUTABLE");
        ingressFactory.setDefaultIngress(SUBJECT_ID, address(0xBEEF));
    }

    function _registration(address splitter, address ingress)
        internal
        view
        returns (ISubjectRegistry.SubjectRegistration memory)
    {
        return ISubjectRegistry.SubjectRegistration({
            subjectId: SUBJECT_ID,
            stakeToken: address(0xB0B),
            splitter: splitter,
            agentSafe: TREASURY_SAFE,
            ingress: ingress,
            paymentLinkFactory: address(0x1002),
            strategy: address(0x1003),
            launchFeeRegistry: address(0x1004),
            feeVault: address(0x1005),
            feeHook: address(0x1006),
            identityChainId: block.chainid,
            identityRegistry: address(0x8004),
            identityAgentId: 42,
            label: "Subject",
            safeRuntime: address(0x7007)
        });
    }
}
