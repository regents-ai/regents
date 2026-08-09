// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";

contract ObservingSplitterDeployer {
    RevenueShareFactory public factory;
    RevenueShareSplitterV2Deployer public immutable realDeployer;
    address public observedStakeTokenMapping;
    address public observedSubjectMapping;
    address public observedInitialOwner;
    address public observedOwnerBeforeReturn;
    address public observedPendingOwnerBeforeReturn;

    constructor(RevenueShareSplitterV2Deployer realDeployer_) {
        realDeployer = realDeployer_;
    }

    function setFactory(RevenueShareFactory factory_) external {
        factory = factory_;
    }

    function deploy(
        address stakeToken,
        address usdc,
        address ingressFactory,
        address subjectRegistry,
        bytes32 subjectId,
        address treasuryRecipient,
        address stakingRevenueRouter,
        uint256 revenueShareSupplyDenominator,
        string calldata label,
        address owner
    ) external returns (address splitter) {
        observedStakeTokenMapping = factory.splitterOfStakeToken(stakeToken);
        observedSubjectMapping = factory.splitterOfSubject(subjectId);
        observedInitialOwner = owner;
        splitter = realDeployer.deploy(
            stakeToken,
            usdc,
            ingressFactory,
            subjectRegistry,
            subjectId,
            treasuryRecipient,
            stakingRevenueRouter,
            revenueShareSupplyDenominator,
            label,
            owner
        );
        observedOwnerBeforeReturn = RevenueShareSplitterV2(splitter).owner();
        observedPendingOwnerBeforeReturn = RevenueShareSplitterV2(splitter).pendingOwner();
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

        RevenueShareSplitterV2 realSplitter = RevenueShareSplitterV2(splitter);
        assertEq(realSplitter.owner(), TREASURY_SAFE);
        assertEq(realSplitter.pendingOwner(), address(0));
        assertEq(realSplitter.stakeToken(), address(stakeToken));
        assertEq(realSplitter.usdc(), USDC);
        assertEq(realSplitter.ingressFactory(), INGRESS_FACTORY);
        assertEq(realSplitter.subjectRegistry(), address(subjectRegistry));
        assertEq(realSplitter.subjectId(), SUBJECT_ID);
        assertEq(realSplitter.treasuryRecipient(), TREASURY_SAFE);
        assertEq(address(realSplitter.stakingRevenueRouter()), address(feeRouter));
        assertEq(realSplitter.revenueShareSupplyDenominator(), 1000 ether);
    }

    function testControllerCanCreateSplitterForZeroIdentityAgentId() external {
        address splitter = factory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY_SAFE,
            address(feeRouter),
            1000 ether,
            "Agent",
            8453,
            address(0x8004),
            0
        );

        assertTrue(splitter != address(0));
        assertEq(factory.splitterOfStakeToken(address(stakeToken)), splitter);
        assertEq(factory.splitterOfSubject(SUBJECT_ID), splitter);
    }

    function testCreateReservesTokenAndSubjectBeforeExternalDeploy() external {
        ObservingSplitterDeployer observingDeployer =
            new ObservingSplitterDeployer(splitterDeployer);
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
        assertEq(observingDeployer.observedInitialOwner(), TREASURY_SAFE);
        assertEq(observingDeployer.observedOwnerBeforeReturn(), TREASURY_SAFE);
        assertEq(observingDeployer.observedPendingOwnerBeforeReturn(), address(0));
        assertEq(observedFactory.splitterOfStakeToken(address(stakeToken)), splitter);
        assertEq(observedFactory.splitterOfSubject(subjectId), splitter);
    }

    function testFactoryHasNoOwnerAuthorityOverCreatedSplitter() external {
        RevenueShareSplitterV2 splitter = RevenueShareSplitterV2(
            factory.createSubjectSplitter(
                SUBJECT_ID,
                address(stakeToken),
                INGRESS_FACTORY,
                TREASURY_SAFE,
                address(feeRouter),
                1000 ether,
                "Agent",
                0,
                address(0),
                0
            )
        );

        vm.prank(address(factory));
        (bool success,) = address(splitter).call(abi.encodeCall(splitter.setPaused, (true)));

        assertFalse(success);
        assertFalse(splitter.paused());
        assertEq(splitter.owner(), TREASURY_SAFE);
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
            0
        );

        vm.expectRevert(RevenueShareFactory.IdentityChainIdZero.selector);
        factory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY_SAFE,
            address(feeRouter),
            1000 ether,
            "Agent",
            0,
            address(0x8004),
            0
        );

        vm.expectRevert(RevenueShareFactory.IdentityChainIdZero.selector);
        factory.createSubjectSplitter(
            SUBJECT_ID,
            address(stakeToken),
            INGRESS_FACTORY,
            TREASURY_SAFE,
            address(feeRouter),
            1000 ether,
            "Agent",
            0,
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
