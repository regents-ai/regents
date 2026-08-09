// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";

contract FakeOwnedSplitter {
    address public pendingOwner;

    function transferOwnership(address newOwner) external {
        pendingOwner = newOwner;
    }
}

contract ObservingSplitterDeployer {
    RevenueShareFactory public factory;
    address public observedStakeTokenMapping;
    address public observedSubjectMapping;
    address public deployedSplitter;

    function setFactory(RevenueShareFactory factory_) external {
        factory = factory_;
    }

    function deploy(
        address stakeToken,
        address,
        address,
        address,
        bytes32 subjectId,
        address,
        address,
        uint256,
        string calldata,
        address
    ) external returns (address splitter) {
        observedStakeTokenMapping = factory.splitterOfStakeToken(stakeToken);
        observedSubjectMapping = factory.splitterOfSubject(subjectId);
        splitter = address(new FakeOwnedSplitter());
        deployedSplitter = splitter;
    }
}

contract RevenueShareFactoryTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant CREATOR = address(0xB0B);
    address internal constant ATTACKER = address(0xBAD);
    address internal constant USDC = address(0x2222);
    address internal constant INGRESS_FACTORY = address(0x3333);
    address internal constant TREASURY_SAFE = address(0xCAFE);
    bytes32 internal constant SUBJECT_ID = keccak256("factory-subject");

    SubjectRegistry internal subjectRegistry;
    RevenueShareFactory internal factory;
    RevenueShareSplitterV2Deployer internal splitterDeployer;
    MintableBurnableERC20Mock internal stakeToken;
    MockRegentStakingRevenueRouter internal feeRouter;

    function setUp() external {
        subjectRegistry = new SubjectRegistry(address(this), OWNER, address(0x600D));
        feeRouter = new MockRegentStakingRevenueRouter(USDC, address(0x8888));
        splitterDeployer = new RevenueShareSplitterV2Deployer();
        factory = new RevenueShareFactory(
            OWNER, USDC, subjectRegistry, address(feeRouter), address(splitterDeployer)
        );
        stakeToken = new MintableBurnableERC20Mock("Agent", "AGENT", 18);
        stakeToken.mint(address(this), 1000 ether);
    }

    function testRejectsUnauthorizedSplitterCreation() external {
        vm.prank(ATTACKER);
        vm.expectRevert(RevenueShareFactory.OnlyController.selector);
        factory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY_SAFE,
            address(feeRouter),
            1000 ether,
            "Agent",
            1,
            address(0x8004),
            42
        );
    }

    function testControllerCanCreateSplitterWithoutRegisteringSubject() external {
        vm.prank(OWNER);
        vm.expectRevert(RevenueShareFactory.OnlyController.selector);
        factory.setAuthorizedCreator(CREATOR, true);

        address splitter = factory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY_SAFE,
            address(feeRouter),
            1000 ether,
            "Agent",
            1,
            address(0x8004),
            42
        );

        assertTrue(splitter != address(0));
        assertEq(factory.splitterOfSubject(SUBJECT_ID), splitter);
        assertEq(subjectRegistry.subjectOfStakeToken(address(stakeToken)), bytes32(0));
        assertEq(subjectRegistry.subjectForIdentity(1, address(0x8004), 42), bytes32(0));
    }

    function testCreateReservesTokenAndSubjectBeforeExternalDeploy() external {
        ObservingSplitterDeployer observingDeployer = new ObservingSplitterDeployer();
        RevenueShareFactory observedFactory = new RevenueShareFactory(
            OWNER, USDC, subjectRegistry, address(feeRouter), address(observingDeployer)
        );
        observingDeployer.setFactory(observedFactory);

        bytes32 subjectId = keccak256("observed-reservation");
        address splitter = observedFactory.createSubjectSplitter(
            subjectId,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY_SAFE,
            address(feeRouter),
            1000 ether,
            "Agent",
            0,
            address(0),
            0
        );

        assertTrue(observingDeployer.observedStakeTokenMapping() != address(0));
        assertEq(
            observingDeployer.observedStakeTokenMapping(),
            observingDeployer.observedSubjectMapping()
        );
        assertTrue(observingDeployer.observedStakeTokenMapping() != splitter);
        assertEq(observedFactory.splitterOfStakeToken(address(stakeToken)), splitter);
        assertEq(observedFactory.splitterOfSubject(subjectId), splitter);
    }

    function testRejectsMalformedIdentityLinkInputs() external {
        vm.expectRevert(RevenueShareFactory.IdentityRegistryZero.selector);
        factory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY_SAFE,
            address(feeRouter),
            1000 ether,
            "Agent",
            1,
            address(0),
            42
        );
    }

    function testRejectsZeroRecipients() external {
        vm.expectRevert(RevenueShareFactory.AgentSafeZero.selector);
        factory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            address(0),
            address(feeRouter),
            1000 ether,
            "Agent",
            0,
            address(0),
            0
        );

        vm.expectRevert(RevenueShareFactory.StakingRevenueRouterMismatch.selector);
        factory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY_SAFE,
            address(0),
            1000 ether,
            "Agent",
            0,
            address(0),
            0
        );
    }
}
