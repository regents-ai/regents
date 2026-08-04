// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {AuctionParameters} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";
import {LaunchDeploymentController} from "src/autolaunch/LaunchDeploymentController.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {AgentTokenVestingWallet} from "src/autolaunch/AgentTokenVestingWallet.sol";
import {RegentLBPStrategy} from "src/autolaunch/RegentLBPStrategy.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {RevenueIngressAccount} from "src/autolaunch/revenue/RevenueIngressAccount.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {HookMiner} from "src/shared/libraries/HookMiner.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {
    MockContinuousClearingAuctionFactory
} from "test/mocks/MockContinuousClearingAuctionFactory.sol";
import {MockHookPoolManager} from "test/mocks/MockHookPoolManager.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";
import {UERC20Factory} from "@uniswap/uerc20-factory/src/factories/UERC20Factory.sol";
import {UERC20Metadata} from "@uniswap/uerc20-factory/src/libraries/UERC20MetadataLibrary.sol";

interface IUERC20LaunchToken {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function creator() external view returns (address);
    function graffiti() external view returns (bytes32);
    function tokenURI() external view returns (string memory);
}

contract ReentrantLaunchTokenFactory {
    LaunchDeploymentController public immutable controller;
    bytes public addressesData;
    bytes public economicsData;
    bytes public scheduleData;
    bytes public metadataData;
    bool public reentryBlocked;

    constructor(LaunchDeploymentController controller_) {
        controller = controller_;
    }

    function setReentryPayload(
        bytes calldata addressesData_,
        bytes calldata economicsData_,
        bytes calldata scheduleData_,
        bytes calldata metadataData_
    ) external {
        addressesData = addressesData_;
        economicsData = economicsData_;
        scheduleData = scheduleData_;
        metadataData = metadataData_;
    }

    function createToken(
        string calldata name,
        string calldata symbol,
        uint8,
        uint256 totalSupply,
        address owner,
        bytes calldata,
        bytes32
    ) external returns (address token) {
        try controller.prepareLaunch(addressesData, economicsData, scheduleData, metadataData) {
            revert("REENTRY_SUCCEEDED");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256(bytes("REENTRANT")), "REENTRY_REASON");
            reentryBlocked = true;
        }

        MintableERC20Mock mock = new MintableERC20Mock(name, symbol);
        mock.mint(owner, totalSupply);
        return address(mock);
    }
}

contract LaunchDeploymentControllerTest is Test {
    address internal constant AGENT_SAFE = address(0xABCD);
    address internal constant IDENTITY_REGISTRY = address(0x8004);
    address internal constant REGENT_RECIPIENT = address(0x9FA1);
    address internal constant STRATEGY_OPERATOR = address(0xBEEF);
    uint96 internal constant IDENTITY_AGENT_ID = 42;
    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint256 internal constant AUCTION_TICK_SPACING = 79_228_162_514_264_337_593_543_950;
    uint256 internal constant AUCTION_FLOOR_PRICE = AUCTION_TICK_SPACING * 100;
    address internal constant BASE_MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant BASE_MAINNET_REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant BASE_MAINNET_POOL_MANAGER =
        0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant BASE_MAINNET_POSITION_MANAGER =
        0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    uint160 internal constant REQUIRED_HOOK_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG
        | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
    bytes32 internal constant LAUNCH_STACK_DEPLOYED_TOPIC0 =
        keccak256("LaunchStackDeployed(address,bytes32,address,address,address,bytes32,address)");

    LaunchDeploymentController internal controller;
    MockContinuousClearingAuctionFactory internal auctionFactory;
    MockHookPoolManager internal poolManager;
    UERC20Factory internal tokenFactory;
    LaunchFeeInfraDeployer internal feeInfraDeployer;
    SubjectRegistry internal subjectRegistry;
    RevenueShareFactory internal revenueShareFactory;
    RevenueShareSplitterV2Deployer internal splitterDeployer;
    RevenueIngressFactory internal revenueIngressFactory;
    RegentLBPStrategyFactory internal strategyFactory;
    MintableERC20Mock internal usdc;
    MintableERC20Mock internal regent;
    MockRegentStakingRevenueRouter internal feeRouter;
    LaunchDeploymentController.DeploymentConfig private launchCfg;

    function setUp() external {
        vm.chainId(8453);
        controller = new LaunchDeploymentController();
        feeInfraDeployer = new LaunchFeeInfraDeployer();
        auctionFactory = new MockContinuousClearingAuctionFactory();
        poolManager = new MockHookPoolManager();
        tokenFactory = new UERC20Factory();
        strategyFactory = new RegentLBPStrategyFactory(address(this));
        usdc = _installCanonicalUsdcMock();
        regent = _installCanonicalRegentMock();
        subjectRegistry = new SubjectRegistry(address(this));
        feeRouter = new MockRegentStakingRevenueRouter(address(usdc), address(0x8888));
        splitterDeployer = new RevenueShareSplitterV2Deployer();
        revenueShareFactory = new RevenueShareFactory(
            address(this),
            address(usdc),
            subjectRegistry,
            address(feeRouter),
            address(splitterDeployer)
        );
        revenueIngressFactory =
            new RevenueIngressFactory(address(usdc), address(subjectRegistry), address(this));
        subjectRegistry.setAuthorizedRegistrar(address(revenueShareFactory), true);
        revenueShareFactory.setAuthorizedCreator(address(controller), true);
        revenueIngressFactory.setAuthorizedCreator(address(controller), true);
        strategyFactory.setAuthorizedCreator(address(controller), true);
        _setDefaultConfig();
    }

    function testRejectsMissingRevenueIngressFactory() external {
        launchCfg.addresses.revenueIngressFactory = address(0);

        vm.expectRevert("REVENUE_INGRESS_FACTORY_ZERO");
        _deploy();
    }

    function testRejectsBadMigrationTiming() external {
        launchCfg.schedule.migrationBlock = launchCfg.schedule.endBlock;

        vm.expectRevert("MIGRATION_BEFORE_END");
        _deploy();
    }

    function testRejectsUnauthorizedDeployCaller() external {
        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_OWNER");
        _deploy();
    }

    function testRejectsNonCanonicalUsdc() external {
        launchCfg.addresses.revenueUsdcToken = address(0xC0FFEE);

        vm.expectRevert("USDC_NOT_CANONICAL");
        _deploy();
    }

    function testRejectsNonCanonicalRegentQuoteToken() external {
        launchCfg.addresses.auctionQuoteToken = address(usdc);

        vm.expectRevert("REGENT_NOT_CANONICAL");
        _deploy();
    }

    function testRejectsDeployWhenSubjectRegistryOwnershipNotAccepted() external {
        SubjectRegistry localSubjectRegistry = new SubjectRegistry(address(this));
        RevenueShareFactory localRevenueShareFactory = new RevenueShareFactory(
            address(this),
            address(usdc),
            localSubjectRegistry,
            address(feeRouter),
            address(splitterDeployer)
        );
        RevenueIngressFactory localRevenueIngressFactory =
            new RevenueIngressFactory(address(usdc), address(localSubjectRegistry), address(this));

        localRevenueShareFactory.setAuthorizedCreator(address(controller), true);
        localRevenueIngressFactory.setAuthorizedCreator(address(controller), true);

        launchCfg.addresses.revenueShareFactory = address(localRevenueShareFactory);
        launchCfg.addresses.revenueIngressFactory = address(localRevenueIngressFactory);

        vm.expectRevert("REVENUE_SHARE_FACTORY_NOT_REGISTRAR");
        _deploy();
    }

    function testRejectsRevenueShareUsdcMismatch() external {
        MintableERC20Mock otherUsdc = new MintableERC20Mock("Other USD", "oUSD");
        MockRegentStakingRevenueRouter otherRouter =
            new MockRegentStakingRevenueRouter(address(otherUsdc), address(0x8888));
        RevenueShareFactory mismatchedRevenueShareFactory = new RevenueShareFactory(
            address(this),
            address(otherUsdc),
            subjectRegistry,
            address(otherRouter),
            address(splitterDeployer)
        );

        launchCfg.addresses.revenueShareFactory = address(mismatchedRevenueShareFactory);

        vm.expectRevert("REVENUE_SHARE_USDC_MISMATCH");
        _deploy();
    }

    function testRejectsRevenueIngressUsdcMismatch() external {
        MintableERC20Mock otherUsdc = new MintableERC20Mock("Other USD", "oUSD");
        RevenueIngressFactory mismatchedRevenueIngressFactory =
            new RevenueIngressFactory(address(otherUsdc), address(subjectRegistry), address(this));

        launchCfg.addresses.revenueIngressFactory = address(mismatchedRevenueIngressFactory);

        vm.expectRevert("REVENUE_INGRESS_USDC_MISMATCH");
        _deploy();
    }

    function testDeploysModelBLaunchStack() external {
        LaunchDeploymentController.DeploymentResult memory result = _deployAndRead();

        _assertCoreAddressesWereCreated(result);
        assertTrue(result.subjectId != bytes32(0));
        assertTrue(result.poolId != bytes32(0));

        (uint256 auctionAmount, uint256 reserveAmount, uint256 vestingAmount) =
            _expectedTokenAmounts();
        _assertLaunchToken(result, auctionAmount, reserveAmount, vestingAmount);
        _assertStrategy(result, auctionAmount, reserveAmount);
        _assertAuction(result, auctionAmount);
        _assertFeeInfra(result);
        _assertRevenueSubject(result);
    }

    function testDeploysModelBLaunchStackInStages() external {
        bytes32 launchId = _prepareLaunch();
        LaunchDeploymentController.DeploymentResult memory prepared = _readResult(launchId);

        assertEq(prepared.subjectId, launchId);
        assertTrue(prepared.tokenAddress != address(0));
        assertTrue(prepared.vestingWalletAddress != address(0));
        assertTrue(prepared.subjectRegistryAddress != address(0));
        assertTrue(prepared.revenueShareSplitterAddress != address(0));
        assertTrue(prepared.defaultIngressAddress != address(0));
        assertEq(prepared.strategyAddress, address(0));
        assertEq(prepared.auctionAddress, address(0));
        assertEq(prepared.hookAddress, address(0));

        _deployLaunchFeeInfra(launchId);
        LaunchDeploymentController.DeploymentResult memory withFeeInfra = _readResult(launchId);

        assertTrue(withFeeInfra.hookAddress != address(0));
        assertTrue(withFeeInfra.feeVaultAddress != address(0));
        assertTrue(withFeeInfra.launchFeeRegistryAddress != address(0));
        assertEq(withFeeInfra.strategyAddress, address(0));
        assertEq(withFeeInfra.auctionAddress, address(0));

        _finalizeLaunch(launchId);
        LaunchDeploymentController.DeploymentResult memory result = _readResult(launchId);

        _assertCoreAddressesWereCreated(result);
        assertEq(result.subjectId, launchId);
        assertTrue(result.poolId != bytes32(0));

        (uint256 auctionAmount, uint256 reserveAmount, uint256 vestingAmount) =
            _expectedTokenAmounts();
        _assertLaunchTokenBalances(result, auctionAmount, reserveAmount, vestingAmount);
        _assertStagedStrategy(result);
        _assertRegisteredPool(result);
        _assertStoredResult(launchId, result);
    }

    function testRecoverFailedAuctionBurnsSupplyAndKillsSubjectAcrossTheStack() external {
        // Full-stack failed-launch unwind: auction misses its minimum raise, the operator runs
        // recoverFailedAuction, and the ENTIRE token supply (auction 10% + LP reserve 5% +
        // vesting 85%) burns to the dead address while the subject is killed everywhere.
        address deadAddress = 0x000000000000000000000000000000000000dEaD;
        launchCfg.economics.requiredCurrencyRaised = 1e18;

        LaunchDeploymentController.DeploymentResult memory result = _deployAndRead();
        RegentLBPStrategy strategy = RegentLBPStrategy(result.strategyAddress);
        RevenueShareSplitterV2 splitter = RevenueShareSplitterV2(result.revenueShareSplitterAddress);
        RevenueIngressAccount ingress = RevenueIngressAccount(payable(result.defaultIngressAddress));
        IUERC20LaunchToken token = IUERC20LaunchToken(result.tokenAddress);

        // No bids: the auction raised 0 REGENT and does not graduate.
        vm.roll(303);
        vm.prank(STRATEGY_OPERATOR);
        strategy.recoverFailedAuction();

        // The whole supply burned; the agent got nothing.
        assertEq(token.balanceOf(deadAddress), TOTAL_SUPPLY);
        assertEq(token.balanceOf(result.strategyAddress), 0);
        assertEq(token.balanceOf(result.auctionAddress), 0);
        assertEq(token.balanceOf(result.vestingWalletAddress), 0);
        assertEq(token.balanceOf(AGENT_SAFE), 0);

        // The vesting wallet can never release anything again.
        AgentTokenVestingWallet vestingWallet = AgentTokenVestingWallet(result.vestingWalletAddress);
        assertTrue(vestingWallet.burnedOnFailedLaunch());
        vm.warp(uint256(launchCfg.schedule.vestingStartTimestamp) + 730 days);
        assertEq(vestingWallet.releasableLaunchToken(), 0);

        // The subject is dead in the registry and the splitter is permanently retired.
        assertTrue(subjectRegistry.subjectDead(result.subjectId));
        assertFalse(subjectRegistry.getSubject(result.subjectId).active);
        assertTrue(splitter.subjectLifecycleRetired());

        // Nothing can be staked or deposited on the dead subject's rev-share stack.
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.stake(1, address(this));
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.depositUSDC(1, bytes32("tag"), bytes32("ref"));
        vm.expectRevert("SUBJECT_INACTIVE");
        ingress.depositUSDC(1, bytes32("tag"));

        // The subject cannot be reactivated — not even by its treasury safe or the owner.
        vm.prank(AGENT_SAFE);
        vm.expectRevert("SUBJECT_DEAD");
        subjectRegistry.updateSubject(
            result.subjectId, result.revenueShareSplitterAddress, AGENT_SAFE, true, "Agent Coin"
        );
        vm.expectRevert("SUBJECT_DEAD");
        subjectRegistry.updateSubject(
            result.subjectId, result.revenueShareSplitterAddress, AGENT_SAFE, true, "Agent Coin"
        );

        // And no new ingress accounts can be created for it.
        vm.prank(AGENT_SAFE);
        vm.expectRevert("SUBJECT_INACTIVE");
        revenueIngressFactory.createIngressAccount(result.subjectId, "late-ingress", false);
    }

    function testRejectsChangedConfigBetweenStagedLaunchSteps() external {
        bytes32 launchId = _prepareLaunch();

        launchCfg.metadata.tokenName = "Changed Agent Coin";

        vm.expectRevert("LAUNCH_CONFIG_CHANGED");
        _deployLaunchFeeInfra(launchId);
    }

    function testDeployBlocksConfiguredFactoryReentry() external {
        ReentrantLaunchTokenFactory reentrantFactory = new ReentrantLaunchTokenFactory(controller);
        launchCfg.addresses.tokenFactory = address(reentrantFactory);
        reentrantFactory.setReentryPayload(
            _encodedAddresses(), _encodedEconomics(), _encodedSchedule(), _encodedMetadata()
        );

        LaunchDeploymentController.DeploymentResult memory result = _deployAndRead();

        assertTrue(reentrantFactory.reentryBlocked());
        _assertCoreAddressesWereCreated(result);
    }

    function testDeploysWithoutIdentityLink() external {
        launchCfg.addresses.identityRegistry = address(0);
        launchCfg.economics.identityAgentId = 0;

        LaunchDeploymentController.DeploymentResult memory result = _deployAndRead();

        _assertCoreAddressesWereCreated(result);
        assertEq(
            subjectRegistry.subjectForIdentity(block.chainid, IDENTITY_REGISTRY, IDENTITY_AGENT_ID),
            bytes32(0)
        );
    }

    function testRejectsPartialIdentityLink() external {
        launchCfg.economics.identityAgentId = 0;

        vm.expectRevert("AGENT_ID_ZERO");
        _deploy();

        _setDefaultConfig();
        launchCfg.addresses.identityRegistry = address(0);

        vm.expectRevert("IDENTITY_REGISTRY_ZERO");
        _deploy();
    }

    function testRejectsEmptyAuctionSteps() external {
        launchCfg.metadata.auctionStepsData = bytes("");

        vm.expectRevert("AUCTION_STEPS_EMPTY");
        _deploy();
    }

    function testRejectsAuctionStepsThatDoNotCoverDuration() external {
        launchCfg.metadata.auctionStepsData = _singleAuctionStep(10_000_000, 1);

        vm.expectRevert("AUCTION_STEPS_BLOCKS");
        _deploy();
    }

    function testAcceptsConvexAuctionScheduleFixture() external {
        launchCfg.schedule.endBlock = 86_402;
        launchCfg.schedule.claimBlock = 86_402;
        launchCfg.schedule.migrationBlock = 86_530;
        launchCfg.schedule.sweepBlock = 86_786;
        launchCfg.metadata.auctionStepsData = _convexAuctionStepsFixture();

        LaunchDeploymentController.DeploymentResult memory result = _deployAndRead();
        _assertCoreAddressesWereCreated(result);

        AuctionParameters memory parameters =
            abi.decode(auctionFactory.lastConfigData(), (AuctionParameters));
        assertEq(parameters.endBlock - parameters.startBlock, 86_401);
        assertEq(parameters.auctionStepsData, launchCfg.metadata.auctionStepsData);
    }

    function testEmitsLaunchStackDeployedEvent() external {
        vm.recordLogs();
        LaunchDeploymentController.DeploymentResult memory result = _deployAndRead();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool found;

        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].emitter == address(controller) && entries[i].topics.length == 4
                    && entries[i].topics[0] == LAUNCH_STACK_DEPLOYED_TOPIC0
            ) {
                found = true;
                assertEq(address(uint160(uint256(entries[i].topics[1]))), address(this));
                assertEq(entries[i].topics[2], result.subjectId);
                assertEq(address(uint160(uint256(entries[i].topics[3]))), result.tokenAddress);

                (
                    address auctionAddress,
                    address strategyAddress,
                    bytes32 poolId,
                    address agentSafe
                ) = abi.decode(entries[i].data, (address, address, bytes32, address));

                assertEq(auctionAddress, result.auctionAddress);
                assertEq(strategyAddress, result.strategyAddress);
                assertEq(poolId, result.poolId);
                assertEq(agentSafe, AGENT_SAFE);
                break;
            }
        }

        assertTrue(found);
    }

    function _setDefaultConfig() internal {
        launchCfg.addresses.agentSafe = AGENT_SAFE;
        launchCfg.addresses.feeInfraDeployer = address(feeInfraDeployer);
        launchCfg.addresses.revenueShareFactory = address(revenueShareFactory);
        launchCfg.addresses.revenueIngressFactory = address(revenueIngressFactory);
        launchCfg.addresses.identityRegistry = IDENTITY_REGISTRY;
        launchCfg.addresses.tokenFactory = address(tokenFactory);
        launchCfg.addresses.strategyFactory = address(strategyFactory);
        launchCfg.addresses.auctionInitializerFactory = address(auctionFactory);
        launchCfg.addresses.poolManager = BASE_MAINNET_POOL_MANAGER;
        launchCfg.addresses.positionManager = BASE_MAINNET_POSITION_MANAGER;
        launchCfg.addresses.strategyOperator = STRATEGY_OPERATOR;
        launchCfg.addresses.auctionQuoteToken = address(regent);
        launchCfg.addresses.revenueUsdcToken = address(usdc);
        launchCfg.addresses.regentRecipient = REGENT_RECIPIENT;
        launchCfg.addresses.validationHook = address(0);
        launchCfg.economics.identityAgentId = IDENTITY_AGENT_ID;
        launchCfg.economics.totalSupply = TOTAL_SUPPLY;
        launchCfg.economics.officialPoolFee = 0;
        launchCfg.economics.officialPoolTickSpacing = 60;
        launchCfg.economics.auctionTickSpacing = AUCTION_TICK_SPACING;
        launchCfg.economics.floorPrice = AUCTION_FLOOR_PRICE;
        launchCfg.economics.requiredCurrencyRaised = 0;
        launchCfg.schedule.startBlock = 1;
        launchCfg.schedule.endBlock = 101;
        launchCfg.schedule.claimBlock = 101;
        launchCfg.schedule.migrationBlock = 202;
        launchCfg.schedule.sweepBlock = 303;
        launchCfg.schedule.vestingStartTimestamp = 1_700_000_000;
        launchCfg.schedule.vestingDurationSeconds = 365 days;
        launchCfg.metadata.auctionStepsData = _singleAuctionStep(100_000, 100);
        launchCfg.metadata.tokenName = "Agent Coin";
        launchCfg.metadata.tokenSymbol = "AGENT";
        launchCfg.metadata.subjectLabel = "Agent Coin";
        launchCfg.metadata.tokenFactoryData =
            abi.encode(UERC20Metadata({description: "", website: "", image: ""}));
        launchCfg.metadata.tokenFactoryGraffiti = keccak256(abi.encode(AGENT_SAFE));
        launchCfg.metadata.launchFeeHookSalt =
            _launchFeeHookSalt(address(feeInfraDeployer), BASE_MAINNET_POOL_MANAGER);
    }

    function _deploy() internal returns (bytes32 launchId) {
        return controller.deploy(
            _encodedAddresses(), _encodedEconomics(), _encodedSchedule(), _encodedMetadata()
        );
    }

    function _prepareLaunch() internal returns (bytes32 launchId) {
        return controller.prepareLaunch(
            _encodedAddresses(), _encodedEconomics(), _encodedSchedule(), _encodedMetadata()
        );
    }

    function _deployLaunchFeeInfra(bytes32 launchId) internal {
        controller.deployLaunchFeeInfra(
            launchId,
            _encodedAddresses(),
            _encodedEconomics(),
            _encodedSchedule(),
            _encodedMetadata()
        );
    }

    function _finalizeLaunch(bytes32 launchId) internal {
        controller.finalizeLaunch(
            launchId,
            _encodedAddresses(),
            _encodedEconomics(),
            _encodedSchedule(),
            _encodedMetadata()
        );
    }

    function _encodedAddresses() internal view returns (bytes memory) {
        return abi.encode(launchCfg.addresses);
    }

    function _encodedEconomics() internal view returns (bytes memory) {
        return abi.encode(launchCfg.economics);
    }

    function _encodedSchedule() internal view returns (bytes memory) {
        return abi.encode(launchCfg.schedule);
    }

    function _encodedMetadata() internal view returns (bytes memory) {
        return abi.encode(launchCfg.metadata);
    }

    function _deployAndRead()
        internal
        returns (LaunchDeploymentController.DeploymentResult memory result)
    {
        bytes32 launchId = _deploy();
        result = _readResult(launchId);
    }

    function _readResult(bytes32 launchId)
        internal
        view
        returns (LaunchDeploymentController.DeploymentResult memory result)
    {
        bool feeInfraDeployed;
        bool finalized;
        (
            result.tokenAddress,
            result.auctionAddress,
            result.strategyAddress,
            result.vestingWalletAddress
        ) = controller.stagedLaunchCore(launchId);
        (
            result.hookAddress,
            result.feeVaultAddress,
            result.launchFeeRegistryAddress,
            result.poolId
        ) = controller.stagedLaunchInfra(launchId);
        (
            result.subjectRegistryAddress,
            result.revenueShareSplitterAddress,
            result.defaultIngressAddress,
            feeInfraDeployed,
            finalized
        ) = controller.stagedLaunchRevenue(launchId);
        feeInfraDeployed;
        finalized;
        result.subjectId = launchId;
    }

    function _assertCoreAddressesWereCreated(
        LaunchDeploymentController.DeploymentResult memory result
    ) internal pure {
        assertTrue(result.tokenAddress != address(0));
        assertTrue(result.auctionAddress != address(0));
        assertTrue(result.strategyAddress != address(0));
        assertTrue(result.vestingWalletAddress != address(0));
        assertTrue(result.hookAddress != address(0));
        assertTrue(result.feeVaultAddress != address(0));
        assertTrue(result.launchFeeRegistryAddress != address(0));
        assertTrue(result.subjectRegistryAddress != address(0));
        assertTrue(result.revenueShareSplitterAddress != address(0));
        assertTrue(result.defaultIngressAddress != address(0));
    }

    function _expectedTokenAmounts()
        internal
        pure
        returns (uint256 auctionAmount, uint256 reserveAmount, uint256 vestingAmount)
    {
        auctionAmount = TOTAL_SUPPLY / 10;
        reserveAmount = (TOTAL_SUPPLY * 500) / 10_000;
        vestingAmount = TOTAL_SUPPLY - auctionAmount - reserveAmount;
    }

    function _assertLaunchToken(
        LaunchDeploymentController.DeploymentResult memory result,
        uint256 auctionAmount,
        uint256 reserveAmount,
        uint256 vestingAmount
    ) internal view {
        _assertLaunchTokenBalances(result, auctionAmount, reserveAmount, vestingAmount);
        IUERC20LaunchToken token = IUERC20LaunchToken(result.tokenAddress);
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.creator(), address(controller));
        assertEq(token.graffiti(), keccak256(abi.encode(AGENT_SAFE)));
        assertTrue(bytes(token.tokenURI()).length > 0);
    }

    function _assertLaunchTokenBalances(
        LaunchDeploymentController.DeploymentResult memory result,
        uint256 auctionAmount,
        uint256 reserveAmount,
        uint256 vestingAmount
    ) internal view {
        IUERC20LaunchToken token = IUERC20LaunchToken(result.tokenAddress);
        assertEq(token.balanceOf(result.auctionAddress), auctionAmount);
        assertEq(token.balanceOf(result.strategyAddress), reserveAmount);
        assertEq(token.balanceOf(result.vestingWalletAddress), vestingAmount);
    }

    function _assertStrategy(
        LaunchDeploymentController.DeploymentResult memory result,
        uint256 auctionAmount,
        uint256 reserveAmount
    ) internal view {
        _assertStagedStrategy(result);
        RegentLBPStrategy strategy = RegentLBPStrategy(result.strategyAddress);
        assertEq(strategy.totalStrategySupply(), auctionAmount + reserveAmount);
        assertEq(strategy.auctionTokenAmount(), auctionAmount);
        assertEq(strategy.reserveTokenAmount(), reserveAmount);
        assertEq(strategy.tokenSplitToAuctionMps(), 6_666_666);
        assertEq(strategy.positionManager(), BASE_MAINNET_POSITION_MANAGER);
        assertEq(strategy.poolManager(), BASE_MAINNET_POOL_MANAGER);
        assertEq(strategy.subjectRegistry(), address(subjectRegistry));
        assertEq(strategy.subjectId(), result.subjectId);
        assertEq(strategy.LP_CURRENCY_BPS(), 4000);
        assertEq(strategy.officialPoolFee(), 0);
        assertEq(strategy.officialPoolTickSpacing(), 60);
        assertEq(
            subjectRegistry.subjectLifecycleAuthority(result.subjectId), result.strategyAddress
        );
        assertEq(
            AgentTokenVestingWallet(result.vestingWalletAddress).strategy(), result.strategyAddress
        );
    }

    function _assertStagedStrategy(LaunchDeploymentController.DeploymentResult memory result)
        internal
        view
    {
        RegentLBPStrategy strategy = RegentLBPStrategy(result.strategyAddress);
        assertEq(strategy.auctionCreator(), address(controller));
        assertEq(strategy.auctionAddress(), result.auctionAddress);
    }

    function _assertAuction(
        LaunchDeploymentController.DeploymentResult memory result,
        uint256 auctionAmount
    ) internal view {
        AuctionParameters memory parameters =
            abi.decode(auctionFactory.lastConfigData(), (AuctionParameters));
        assertEq(parameters.currency, address(regent));
        assertEq(parameters.tokensRecipient, result.strategyAddress);
        assertEq(parameters.fundsRecipient, result.strategyAddress);
        assertEq(parameters.auctionStepsData, _singleAuctionStep(100_000, 100));
        assertEq(auctionFactory.lastAmount(), auctionAmount);
    }

    function _assertFeeInfra(LaunchDeploymentController.DeploymentResult memory result)
        internal
        view
    {
        _assertRegisteredPool(result);
        LaunchFeeRegistry registry = LaunchFeeRegistry(result.launchFeeRegistryAddress);
        assertEq(registry.owner(), address(controller));
        assertEq(registry.pendingOwner(), AGENT_SAFE);

        LaunchFeeVault feeVault = LaunchFeeVault(payable(result.feeVaultAddress));
        assertEq(feeVault.owner(), address(controller));
        assertEq(feeVault.pendingOwner(), AGENT_SAFE);
        assertEq(feeVault.canonicalLaunchToken(), result.tokenAddress);
        assertEq(feeVault.canonicalQuoteToken(), address(regent));

        LaunchPoolFeeHook hook = LaunchPoolFeeHook(result.hookAddress);
        assertEq(hook.owner(), address(controller));
        assertEq(hook.pendingOwner(), AGENT_SAFE);

        AgentTokenVestingWallet vestingWallet = AgentTokenVestingWallet(result.vestingWalletAddress);
        assertEq(vestingWallet.beneficiary(), AGENT_SAFE);
    }

    function _assertRegisteredPool(LaunchDeploymentController.DeploymentResult memory result)
        internal
        view
    {
        LaunchFeeRegistry registry = LaunchFeeRegistry(result.launchFeeRegistryAddress);
        LaunchFeeRegistry.PoolConfig memory poolConfig = registry.getPoolConfig(result.poolId);
        assertEq(poolConfig.launchToken, result.tokenAddress);
        assertEq(poolConfig.quoteToken, address(regent));
        assertEq(poolConfig.treasury, AGENT_SAFE);
        assertEq(poolConfig.regentRecipient, REGENT_RECIPIENT);
    }

    function _assertRevenueSubject(LaunchDeploymentController.DeploymentResult memory result)
        internal
        view
    {
        RevenueShareSplitterV2 splitter = RevenueShareSplitterV2(result.revenueShareSplitterAddress);
        assertEq(splitter.stakeToken(), result.tokenAddress);
        assertEq(splitter.usdc(), address(usdc));
        assertEq(splitter.owner(), address(revenueShareFactory));
        assertEq(splitter.pendingOwner(), AGENT_SAFE);
        assertEq(splitter.treasuryRecipient(), AGENT_SAFE);
        assertEq(splitter.protocolRecipient(), address(feeRouter));

        SubjectRegistry.SubjectConfig memory subject = subjectRegistry.getSubject(result.subjectId);
        assertEq(subject.stakeToken, result.tokenAddress);
        assertEq(subject.splitter, result.revenueShareSplitterAddress);
        assertEq(subject.treasurySafe, AGENT_SAFE);
        assertTrue(subject.active);
        assertTrue(subjectRegistry.subjectManagers(result.subjectId, AGENT_SAFE));

        bytes32 expectedSubjectId = keccak256(abi.encode(block.chainid, result.tokenAddress));
        assertEq(result.subjectId, expectedSubjectId);
        assertEq(subjectRegistry.subjectOfStakeToken(result.tokenAddress), expectedSubjectId);
        assertEq(
            subjectRegistry.subjectForIdentity(block.chainid, IDENTITY_REGISTRY, IDENTITY_AGENT_ID),
            expectedSubjectId
        );
        assertEq(
            revenueIngressFactory.defaultIngressOfSubject(result.subjectId),
            result.defaultIngressAddress
        );
        assertEq(revenueIngressFactory.ingressAccountCount(result.subjectId), 1);
    }

    function _assertStoredResult(
        bytes32 launchId,
        LaunchDeploymentController.DeploymentResult memory result
    ) internal view {
        LaunchDeploymentController.DeploymentResult memory stored = _readResult(launchId);
        assertEq(stored.tokenAddress, result.tokenAddress);
        assertEq(stored.auctionAddress, result.auctionAddress);
        assertEq(stored.strategyAddress, result.strategyAddress);
        assertEq(stored.poolId, result.poolId);
    }

    function _singleAuctionStep(uint24 mps, uint40 blockDelta)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(mps, blockDelta);
    }

    function _convexAuctionStepsFixture() internal pure returns (bytes memory) {
        return hex"0000360000002a8e000044000000214500004b0000001e7b00004f0000001ccd0000530000001b9c0000550000001ab300005800000019f700005a000000195a00005c00000018d400005e000000185e00005f00000017f8000061000000179b2d97e60000000001";
    }

    function _installCanonicalUsdcMock() internal returns (MintableERC20Mock mock) {
        MintableERC20Mock implementation = new MintableERC20Mock("USD Coin", "USDC");
        vm.etch(BASE_MAINNET_USDC, address(implementation).code);
        mock = MintableERC20Mock(BASE_MAINNET_USDC);
    }

    function _installCanonicalRegentMock() internal returns (MintableERC20Mock mock) {
        MintableERC20Mock implementation = new MintableERC20Mock("REGENT", "REGENT");
        vm.etch(BASE_MAINNET_REGENT, address(implementation).code);
        mock = MintableERC20Mock(BASE_MAINNET_REGENT);
    }

    function _launchFeeHookSalt(address feeInfraDeployer_, address poolManager_)
        internal
        pure
        returns (bytes32 hookSalt)
    {
        address launchFeeRegistry = vm.computeCreateAddress(feeInfraDeployer_, 1);
        address feeVault = vm.computeCreateAddress(feeInfraDeployer_, 2);

        (hookSalt,) = HookMiner.find(
            feeInfraDeployer_,
            REQUIRED_HOOK_FLAGS,
            type(LaunchPoolFeeHook).creationCode,
            abi.encode(feeInfraDeployer_, poolManager_, launchFeeRegistry, feeVault)
        );
    }
}
