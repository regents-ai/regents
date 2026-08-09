// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AuctionParameters} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {AgentTokenVestingWallet} from "src/autolaunch/AgentTokenVestingWallet.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {ISubjectLifecycleSync} from "src/autolaunch/revenue/interfaces/ISubjectLifecycleSync.sol";
import {MockHookDeployer} from "test/mocks/MockHookDeployer.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {
    MockContinuousClearingAuctionFactory,
    MockDistributionContract
} from "test/mocks/MockContinuousClearingAuctionFactory.sol";
import {RealPoolManagerHarness} from "test/LaunchPoolFeeHook.t.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {Position} from "@uniswap/v4-core/src/libraries/Position.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {PositionDescriptor} from "@uniswap/v4-periphery/src/PositionDescriptor.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IERC721Permit_v4} from "@uniswap/v4-periphery/src/interfaces/IERC721Permit_v4.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {RegentLBPStrategy} from "src/autolaunch/RegentLBPStrategy.sol";
import {
    IContinuousClearingAuctionFactory
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuctionFactory.sol";
import {
    IDistributionContract
} from "src/autolaunch/cca/interfaces/external/IDistributionContract.sol";

contract LifecycleSplitterMock is ISubjectLifecycleSync {
    bool public lastActive = true;
    bool public retired;

    function syncSubjectLifecycle(bool active_, bool retiring_) external {
        lastActive = active_;
        if (retiring_) {
            retired = true;
        }
    }
}

contract TestDistributionContract is IDistributionContract {
    bool public received;

    function onTokensReceived() external {
        received = true;
    }
}

contract MismatchAuctionFactory is IContinuousClearingAuctionFactory {
    function create(address, uint256, bytes calldata, bytes32)
        external
        returns (IDistributionContract distributionContract)
    {
        return new TestDistributionContract();
    }

    function getAddress(address, uint256, bytes calldata, bytes32, address)
        external
        pure
        returns (IDistributionContract)
    {
        return IDistributionContract(address(0xCAFE));
    }

    function protocolFeeController() external pure returns (address) {
        return address(0xCAFE200);
    }
}

contract RegentLBPStrategyTest is Test {
    address internal constant AGENT_TREASURY = address(0x1234);
    address internal constant OPERATOR = address(0x9ABC);
    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint128 internal constant AUCTION_AMOUNT = 100e18;
    uint128 internal constant RESERVE_AMOUNT = 50e18;
    uint128 internal constant VESTING_AMOUNT = 850e18;
    uint64 internal constant VESTING_START = 1_700_000_000;
    uint24 internal constant OFFICIAL_POOL_FEE = 0;
    int24 internal constant OFFICIAL_POOL_TICK_SPACING = 60;

    MintableERC20Mock internal token;
    MintableERC20Mock internal quoteToken;
    MockContinuousClearingAuctionFactory internal auctionFactory;
    RegentLBPStrategy internal strategy;
    PoolManager internal poolManager;
    PositionManager internal positionManager;
    WETH internal weth;
    PositionDescriptor internal positionDescriptor;
    MockHookDeployer internal hookDeployer;
    LaunchPoolFeeHook internal hook;
    LaunchFeeRegistry internal registry;
    LaunchFeeVault internal vault;
    MismatchAuctionFactory internal mismatchAuctionFactory;
    SubjectRegistry internal subjectRegistry;
    LifecycleSplitterMock internal lifecycleSplitter;
    AgentTokenVestingWallet internal vestingWallet;
    bytes32 internal subjectId;

    function setUp() external {
        token = new MintableERC20Mock("Launch Token", "LT");
        MintableERC20Mock quoteImplementation = new MintableERC20Mock("REGENT", "REGENT");
        vm.etch(0x6f89bcA4eA5931EdFCB09786267b251DeE752b07, address(quoteImplementation).code);
        quoteToken = MintableERC20Mock(0x6f89bcA4eA5931EdFCB09786267b251DeE752b07);
        auctionFactory = new MockContinuousClearingAuctionFactory();
        poolManager = new PoolManager(address(this));
        weth = new WETH();
        positionDescriptor = new PositionDescriptor(poolManager, address(weth), bytes32("ETH"));
        positionManager = new PositionManager(
            poolManager,
            IAllowanceTransfer(address(0xBEEF)),
            100_000,
            positionDescriptor,
            IWETH9(address(weth))
        );
        hookDeployer = new MockHookDeployer();
        // The fee hook's beforeInitialize guard reads pool config from a real registry, so the
        // hook must point at a real LaunchFeeRegistry whose canonical quote token matches.
        subjectRegistry = new SubjectRegistry(address(this), address(0xA11CE), address(0x600D));
        lifecycleSplitter = new LifecycleSplitterMock();
        subjectId = keccak256(abi.encode(block.chainid, address(token)));
        registry = new LaunchFeeRegistry(
            AGENT_TREASURY, address(this), address(subjectRegistry), subjectId, address(quoteToken)
        );
        vault = new LaunchFeeVault(address(registry));
        hook = hookDeployer.deploy(address(poolManager), address(registry), address(vault));
        vault.setHook(address(hook));
        mismatchAuctionFactory = new MismatchAuctionFactory();
        vestingWallet =
            new AgentTokenVestingWallet(AGENT_TREASURY, VESTING_START, 365 days, address(token));

        strategy = new RegentLBPStrategy(_strategyConfig(0));

        token.mint(address(strategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
    }

    /// @dev Wires the failed-launch unwind atomically around the final strategy identity.
    function _wireFailureUnwind(RegentLBPStrategy failedStrategy) internal {
        vestingWallet.bindStrategy(address(failedStrategy));
        _registerStrategySubject(failedStrategy);
    }

    function _registerStrategySubject(RegentLBPStrategy registeredStrategy) internal {
        subjectRegistry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: subjectId,
                stakeToken: address(token),
                splitter: address(lifecycleSplitter),
                agentSafe: AGENT_TREASURY,
                ingress: address(0x1111),
                paymentLinkFactory: address(0x2222),
                strategy: address(registeredStrategy),
                launchFeeRegistry: address(registry),
                feeVault: address(vault),
                feeHook: address(hook),
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                label: "Launch Token",
                safeRuntime: OPERATOR
            })
        );
    }

    /// @dev Registers the official launch pool authorizing `initializer` (the migrating strategy)
    /// so the fee hook's beforeInitialize guard permits its direct poolManager.initialize call.
    function _registerOfficialPool(address initializer) internal {
        registry.registerPool(
            LaunchFeeRegistry.PoolRegistration({
                launchToken: address(token),
                quoteToken: address(quoteToken),
                poolFee: OFFICIAL_POOL_FEE,
                tickSpacing: OFFICIAL_POOL_TICK_SPACING,
                poolManager: address(poolManager),
                hook: address(hook),
                authorizedInitializer: initializer
            })
        );
        vault.setCanonicalTokens(
            registry.computePoolId(
                address(token),
                address(quoteToken),
                OFFICIAL_POOL_FEE,
                OFFICIAL_POOL_TICK_SPACING,
                address(hook)
            )
        );
    }

    function testOnTokensReceivedCreatesV2AuctionRecipients() external {
        strategy.onTokensReceived();

        assertTrue(strategy.auctionAddress() != address(0));
        assertEq(token.balanceOf(strategy.auctionAddress()), AUCTION_AMOUNT);
        assertEq(token.balanceOf(address(strategy)), RESERVE_AMOUNT);
        assertEq(auctionFactory.lastAmount(), AUCTION_AMOUNT);
        assertEq(strategy.officialPoolFee(), OFFICIAL_POOL_FEE);
        assertEq(strategy.officialPoolTickSpacing(), OFFICIAL_POOL_TICK_SPACING);

        AuctionParameters memory params =
            abi.decode(auctionFactory.lastConfigData(), (AuctionParameters));
        assertEq(params.tokensRecipient, address(strategy));
        assertEq(params.fundsRecipient, address(strategy));
    }

    function testOnTokensReceivedCannotRunTwice() external {
        strategy.onTokensReceived();

        vm.expectRevert("AUCTION_ALREADY_CREATED");
        strategy.onTokensReceived();
    }

    function testOnTokensReceivedRequiresPredictedAuctionMatch() external {
        RegentLBPStrategy.StrategyConfig memory cfg = _strategyConfig(0);
        cfg.auctionInitializerFactory = address(mismatchAuctionFactory);
        RegentLBPStrategy mismatchStrategy = new RegentLBPStrategy(cfg);
        token.mint(address(mismatchStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);

        vm.expectRevert("AUCTION_ADDRESS_MISMATCH");
        mismatchStrategy.onTokensReceived();
    }

    function testMigrateRequiresAuctionCreation() external {
        _registerStrategySubject(strategy);
        quoteToken.mint(address(strategy), 200e18);

        vm.roll(202);
        vm.prank(OPERATOR);
        vm.expectRevert("AUCTION_NOT_CREATED");
        strategy.migrate();
    }

    function testMigrateRequiresGraduatedAuctionEvenWhenStrategyHoldsQuoteToken() external {
        RegentLBPStrategy failedStrategy = new RegentLBPStrategy(_strategyConfig(100e18));
        _registerStrategySubject(failedStrategy);
        token.mint(address(failedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        failedStrategy.onTokensReceived();
        quoteToken.mint(address(failedStrategy), 200e18);

        vm.roll(202);
        vm.prank(OPERATOR);
        vm.expectRevert("AUCTION_NOT_GRADUATED");
        failedStrategy.migrate();
    }

    function testConstructorRejectsCriticalZeroAddresses() external {
        RegentLBPStrategy.StrategyConfig memory cfg = _strategyConfig(0);

        vm.expectRevert("HOOK_ZERO");
        cfg.officialPoolHook = address(0);
        new RegentLBPStrategy(cfg);

        vm.expectRevert("POSITION_MANAGER_ZERO");
        cfg = _strategyConfig(0);
        cfg.positionManager = address(0);
        new RegentLBPStrategy(cfg);

        vm.expectRevert("POOL_MANAGER_ZERO");
        cfg = _strategyConfig(0);
        cfg.poolManager = address(0);
        new RegentLBPStrategy(cfg);
    }

    function testMigrateCreatesRealV4PositionAndSweepsRemainders() external {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        _registerOfficialPool(address(strategy));
        quoteToken.mint(strategy.auctionAddress(), 201e18);

        uint256 expectedPositionId = positionManager.nextTokenId();
        PoolKey memory expectedPoolKey = _expectedPoolKey();
        bytes32 expectedPoolId = PoolId.unwrap(expectedPoolKey.toId());
        int24 lowerTick = TickMath.minUsableTick(OFFICIAL_POOL_TICK_SPACING);
        int24 upperTick = TickMath.maxUsableTick(OFFICIAL_POOL_TICK_SPACING);

        vm.roll(202);
        vm.prank(OPERATOR);
        strategy.migrate();

        assertTrue(strategy.migrated());
        assertEq(strategy.migratedPoolId(), expectedPoolId);
        assertEq(strategy.migratedPositionId(), expectedPositionId);
        // Fixed protocol preset: exactly 40% of the raised REGENT seeds the LP.
        assertEq(strategy.migratedQuoteTokenForLP(), (201e18 * 4000) / 10_000);
        assertEq(strategy.migratedTokenForLP(), RESERVE_AMOUNT);
        assertTrue(strategy.migratedLiquidity() != 0);

        // The LP position NFT is minted straight to the canonical dead address.
        assertEq(positionManager.ownerOf(expectedPositionId), DEAD_ADDRESS);
        assertEq(
            positionManager.getPositionLiquidity(expectedPositionId), strategy.migratedLiquidity()
        );

        (PoolKey memory actualPoolKey,) = positionManager.getPoolAndPositionInfo(expectedPositionId);
        assertEq(
            Currency.unwrap(actualPoolKey.currency0), Currency.unwrap(expectedPoolKey.currency0)
        );
        assertEq(
            Currency.unwrap(actualPoolKey.currency1), Currency.unwrap(expectedPoolKey.currency1)
        );
        assertEq(actualPoolKey.fee, expectedPoolKey.fee);
        assertEq(actualPoolKey.tickSpacing, expectedPoolKey.tickSpacing);
        assertEq(address(actualPoolKey.hooks), address(expectedPoolKey.hooks));

        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, PoolId.wrap(expectedPoolId));
        assertTrue(sqrtPriceX96 != 0);
        assertTrue(StateLibrary.getLiquidity(poolManager, PoolId.wrap(expectedPoolId)) != 0);

        bytes32 positionKey = Position.calculatePositionKey(
            address(positionManager), lowerTick, upperTick, bytes32(expectedPositionId)
        );
        assertEq(
            StateLibrary.getPositionLiquidity(
                poolManager, PoolId.wrap(expectedPoolId), positionKey
            ),
            strategy.migratedLiquidity()
        );

        uint256 treasuryBefore = quoteToken.balanceOf(AGENT_TREASURY);
        uint256 vestingBefore = token.balanceOf(address(vestingWallet));

        token.mint(address(strategy), 12e18);
        quoteToken.mint(address(strategy), 11e18);

        uint256 currencyToSweep = quoteToken.balanceOf(address(strategy));
        // sweepToken also pulls the unsold auction tokens back into the strategy first: the
        // strategy is the auction's tokens recipient, and everything routes to vesting.
        uint256 tokenToSweep =
            token.balanceOf(address(strategy)) + token.balanceOf(strategy.auctionAddress());

        vm.roll(303);
        vm.prank(OPERATOR);
        strategy.sweepQuoteToken();
        vm.prank(OPERATOR);
        strategy.sweepToken();

        assertEq(quoteToken.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(strategy.auctionAddress()), 0);
        assertEq(quoteToken.balanceOf(AGENT_TREASURY), treasuryBefore + currencyToSweep);
        assertEq(token.balanceOf(address(vestingWallet)), vestingBefore + tokenToSweep);
    }

    function testRegistryRejectsInitializerThatIsNotTheBoundStrategy() external {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        vm.expectRevert("STRATEGY_MISMATCH");
        registry.registerPool(
            LaunchFeeRegistry.PoolRegistration({
                launchToken: address(token),
                quoteToken: address(quoteToken),
                poolFee: OFFICIAL_POOL_FEE,
                tickSpacing: OFFICIAL_POOL_TICK_SPACING,
                poolManager: address(poolManager),
                hook: address(hook),
                authorizedInitializer: address(0xBEEF)
            })
        );
        assertFalse(strategy.migrated());
    }

    function testMigrateRevertsWhenPoolNotRegistered() external {
        // Without a registry entry the hook's beforeInitialize guard reverts POOL_NOT_REGISTERED,
        // so a graduated strategy cannot initialize an unregistered pool.
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        quoteToken.mint(strategy.auctionAddress(), 200e18);

        vm.roll(202);
        vm.prank(OPERATOR);
        vm.expectRevert(_wrappedInitializeRevert("POOL_NOT_REGISTERED"));
        strategy.migrate();

        assertFalse(strategy.migrated());
    }

    function testFrontRunPoolInitializationByAttackerEOAReverts() external {
        // Adversarial: attacker directly calls poolManager.initialize before migrate(). The shared
        // hook authorizes only the registered strategy, so the front-run reverts and migrate()
        // remains reachable (no permanent freeze).
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        _registerOfficialPool(address(strategy));
        quoteToken.mint(strategy.auctionAddress(), 200e18);

        PoolKey memory poolKey = _expectedPoolKey();
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);

        vm.roll(202);
        vm.prank(address(0xA77ACC));
        vm.expectRevert(_wrappedInitializeRevert("UNAUTHORIZED_INITIALIZER"));
        poolManager.initialize(poolKey, sqrtPriceX96);

        // The legitimate migrate still succeeds end-to-end after the failed front-run.
        vm.prank(OPERATOR);
        strategy.migrate();
        assertTrue(strategy.migrated());
    }

    function testFrontRunPoolInitializationRoutedThroughPositionManagerCannotCreatePool() external {
        // Adversarial: attacker routes pool creation through the shared PositionManager (the path
        // migrate() historically used). v4 gives beforeInitialize sender = the PositionManager, which
        // is not the authorized strategy, so the hook reverts. PositionManager.initializePool catches
        // that revert and returns the sentinel tick WITHOUT creating the pool, so the attacker cannot
        // pre-create the pool and migrate() still succeeds end-to-end (no permanent freeze).
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        _registerOfficialPool(address(strategy));
        quoteToken.mint(strategy.auctionAddress(), 200e18);

        PoolKey memory poolKey = _expectedPoolKey();
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);

        vm.roll(202);
        vm.prank(address(0xA77ACC));
        int24 attackerTick = positionManager.initializePool(poolKey, sqrtPriceX96);

        // Sentinel returned and the pool was NOT initialized by the attacker.
        assertEq(attackerTick, type(int24).max);
        (uint160 attackerSqrtPrice,,,) = StateLibrary.getSlot0(poolManager, PoolId.wrap(poolId));
        assertEq(attackerSqrtPrice, 0);

        // The legitimate migrate still succeeds end-to-end after the failed front-run.
        vm.prank(OPERATOR);
        strategy.migrate();
        assertTrue(strategy.migrated());
        (uint160 migratedSqrtPrice,,,) = StateLibrary.getSlot0(poolManager, PoolId.wrap(poolId));
        assertTrue(migratedSqrtPrice != 0);
    }

    function testGraduatedAuctionSurvivesFrontRunAttemptAndMigratesAndSweeps() external {
        // Full money-path integration: a graduated auction whose pool an attacker tries to freeze by
        // front-running initialization both ways. Both attempts fail to pre-create the pool, migrate()
        // still succeeds, and the post-migration sweeps move funds — proving the freeze is gone.
        RegentLBPStrategy graduatedStrategy = new RegentLBPStrategy(_strategyConfig(100e18));
        _registerStrategySubject(graduatedStrategy);
        token.mint(address(graduatedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        graduatedStrategy.onTokensReceived();
        _registerOfficialPool(address(graduatedStrategy));

        MockDistributionContract auction =
            MockDistributionContract(graduatedStrategy.auctionAddress());
        quoteToken.mint(address(auction), 200e18);

        vm.roll(102);
        PoolKey memory poolKey = _expectedPoolKey();
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);

        vm.roll(202);

        // Attack 1: direct poolManager.initialize by an attacker EOA -> reverts (sender != strategy).
        vm.prank(address(0xA77ACC));
        vm.expectRevert(_wrappedInitializeRevert("UNAUTHORIZED_INITIALIZER"));
        poolManager.initialize(poolKey, sqrtPriceX96);

        // Attack 2: routed through the shared PositionManager -> swallowed, pool not created.
        vm.prank(address(0xA77ACC));
        int24 attackerTick = positionManager.initializePool(poolKey, sqrtPriceX96);
        assertEq(attackerTick, type(int24).max);
        (uint160 preMigrateSqrtPrice,,,) = StateLibrary.getSlot0(poolManager, PoolId.wrap(poolId));
        assertEq(preMigrateSqrtPrice, 0);

        // Legitimate migrate succeeds.
        vm.prank(OPERATOR);
        graduatedStrategy.migrate();
        assertTrue(graduatedStrategy.migrated());
        (uint160 migratedSqrtPrice,,,) = StateLibrary.getSlot0(poolManager, PoolId.wrap(poolId));
        assertTrue(migratedSqrtPrice != 0);

        // Sweeps work after migration (funds are not frozen).
        uint256 treasuryBefore = quoteToken.balanceOf(AGENT_TREASURY);
        uint256 vestingBefore = token.balanceOf(address(vestingWallet));
        uint256 quoteResidual = quoteToken.balanceOf(address(graduatedStrategy));
        uint256 tokenResidual = token.balanceOf(address(graduatedStrategy))
            + token.balanceOf(graduatedStrategy.auctionAddress());

        vm.roll(303);
        vm.prank(OPERATOR);
        graduatedStrategy.sweepQuoteToken();
        vm.prank(OPERATOR);
        graduatedStrategy.sweepToken();

        assertEq(quoteToken.balanceOf(AGENT_TREASURY), treasuryBefore + quoteResidual);
        assertEq(token.balanceOf(address(vestingWallet)), vestingBefore + tokenResidual);
    }

    /// @dev Runs a graduated migration and returns the locked position id.
    function _migrateWithRaise(uint256 raised) internal returns (uint256 positionId) {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        _registerOfficialPool(address(strategy));
        quoteToken.mint(strategy.auctionAddress(), raised);

        vm.roll(202);
        vm.prank(OPERATOR);
        strategy.migrate();
        positionId = strategy.migratedPositionId();
    }

    function _decreaseLiquidityCall(uint256 positionId, uint128 liquidity, address recipient)
        internal
        view
        returns (bytes memory)
    {
        PoolKey memory poolKey = _expectedPoolKey();
        bytes memory actions =
            abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, liquidity, 0, 0, bytes(""));
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, recipient);
        return abi.encode(actions, params);
    }

    function testMigratedPositionIsPermanentlyLockedAgainstEveryone() external {
        // Adversarial: nobody — agent safe, operator, strategy, or a random attacker — can pull
        // liquidity out of the migrated position. It is owned by the dead address with no
        // approvals, so PositionManager's owner gate is unreachable forever.
        uint256 positionId = _migrateWithRaise(200e18);
        uint128 liquidity = strategy.migratedLiquidity();

        assertEq(positionManager.ownerOf(positionId), DEAD_ADDRESS);
        assertEq(positionManager.getApproved(positionId), address(0));

        address[4] memory attackers =
            [AGENT_TREASURY, OPERATOR, address(strategy), address(0xA77ACC)];
        for (uint256 i = 0; i < attackers.length; ++i) {
            address attacker = attackers[i];
            bytes memory decreaseCall = _decreaseLiquidityCall(positionId, liquidity, attacker);
            vm.prank(attacker);
            vm.expectRevert(abi.encodeWithSelector(IPositionManager.NotApproved.selector, attacker));
            positionManager.modifyLiquidities(decreaseCall, block.timestamp);
        }

        // Burning the position (the other liquidity-removal path) is gated identically.
        bytes memory burnActions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory burnParams = new bytes[](1);
        burnParams[0] = abi.encode(positionId, 0, 0, bytes(""));
        vm.prank(AGENT_TREASURY);
        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.NotApproved.selector, AGENT_TREASURY)
        );
        positionManager.modifyLiquidities(abi.encode(burnActions, burnParams), block.timestamp);

        // Nobody can grant themselves approval either.
        vm.prank(AGENT_TREASURY);
        vm.expectRevert(IERC721Permit_v4.Unauthorized.selector);
        positionManager.approve(AGENT_TREASURY, positionId);

        // And the NFT itself cannot be moved off the dead address.
        vm.prank(AGENT_TREASURY);
        vm.expectRevert("NOT_AUTHORIZED");
        positionManager.transferFrom(DEAD_ADDRESS, AGENT_TREASURY, positionId);

        // The pool's liquidity is fully intact after all attempts.
        assertEq(positionManager.getPositionLiquidity(positionId), liquidity);
    }

    function testPoolTradeFeeStillAccruesAndCollectsAfterLock() external {
        // The 2% pool trade fee (1% agent / 1% Regent) is charged by the hook during swaps and
        // routed to the LaunchFeeVault — position ownership is irrelevant, so locking the LP
        // forever does not touch the agent/Regent fee income path.
        _migrateWithRaise(200e18);
        bytes32 poolId = strategy.migratedPoolId();

        RealPoolManagerHarness swapper =
            new RealPoolManagerHarness(IPoolManager(address(poolManager)));
        uint256 swapAmount = 10e18;
        quoteToken.mint(address(swapper), swapAmount);

        PoolKey memory poolKey = _expectedPoolKey();
        bool quoteIsCurrency0 = Currency.unwrap(poolKey.currency0) == address(quoteToken);
        swapper.swap(
            poolKey,
            SwapParams({
                zeroForOne: quoteIsCurrency0,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: quoteIsCurrency0
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        uint256 expectedFee = (swapAmount * 200) / 10_000;
        assertEq(quoteToken.balanceOf(address(vault)), expectedFee);
        assertEq(vault.treasuryAccrued(poolId, address(quoteToken)), expectedFee / 2);
        assertEq(vault.regentAccrued(poolId, address(quoteToken)), expectedFee / 2);

        // The agent treasury can actually collect its half.
        vault.withdrawTreasury(poolId);
        assertEq(quoteToken.balanceOf(AGENT_TREASURY), expectedFee / 2);
    }

    function _wrappedInitializeRevert(string memory reason) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hook),
            IHooks.beforeInitialize.selector,
            abi.encodeWithSignature("Error(string)", reason),
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }

    function testOnTokensReceivedRequiresAuctionCreator() external {
        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_AUCTION_CREATOR");
        strategy.onTokensReceived();
    }

    function testSweepsRequireMigrationToFinish() external {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        token.mint(address(strategy), 12e18);
        quoteToken.mint(address(strategy), 11e18);

        vm.roll(303);
        vm.prank(OPERATOR);
        vm.expectRevert("MIGRATION_REQUIRED");
        strategy.sweepQuoteToken();

        vm.prank(OPERATOR);
        vm.expectRevert("MIGRATION_REQUIRED");
        strategy.sweepToken();
    }

    function testQuarantineBlocksMigrationSweepsAndRetirementBeforeEffects() external {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        _registerOfficialPool(address(strategy));
        quoteToken.mint(strategy.auctionAddress(), 200e18);
        token.mint(address(strategy), 12e18);
        quoteToken.mint(address(strategy), 11e18);

        vm.prank(AGENT_TREASURY);
        subjectRegistry.quarantineSubject(subjectId);

        vm.roll(303);
        vm.startPrank(OPERATOR);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        strategy.migrate();
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        strategy.sweepToken();
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        strategy.sweepQuoteToken();
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        strategy.recoverFailedAuction();
        vm.stopPrank();

        assertFalse(strategy.migrated());
        assertFalse(strategy.failedAuctionRecovered());
        assertEq(
            uint256(subjectRegistry.lifecycleOf(subjectId)),
            uint256(ISubjectRegistry.Lifecycle.Quarantined)
        );
    }

    function testBoundedFinalizationRemainsPendingUntilEndCheckpoint() external {
        auctionFactory.configureFinalization(2);
        RegentLBPStrategy pendingStrategy = new RegentLBPStrategy(_strategyConfig(1));
        token.mint(address(pendingStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        pendingStrategy.onTokensReceived();
        _wireFailureUnwind(pendingStrategy);

        MockDistributionContract auction =
            MockDistributionContract(pendingStrategy.auctionAddress());
        vm.roll(202);

        vm.prank(OPERATOR);
        vm.expectRevert("AUCTION_FINALIZATION_PENDING");
        pendingStrategy.migrate();

        vm.prank(OPERATOR);
        assertFalse(pendingStrategy.progressFinalization(2000));
        assertEq(auction.pendingFinalizationSteps(), 1);
        assertEq(auction.lastCheckpointedBlock(), 0);
        assertFalse(pendingStrategy.failedAuctionRecovered());

        vm.prank(OPERATOR);
        assertTrue(pendingStrategy.progressFinalization(3000));
        assertEq(auction.lastCheckpointedBlock(), auction.endBlock());

        vm.roll(303);
        vm.prank(OPERATOR);
        pendingStrategy.recoverFailedAuction();
        assertTrue(pendingStrategy.failedAuctionRecovered());
    }

    function testBidExitAndClaimSelectorsRemainCallable() external {
        strategy.onTokensReceived();
        MockDistributionContract auction = MockDistributionContract(strategy.auctionAddress());

        uint256 hintedBid = auction.submitBid(2000, 1e18, address(this), 1000, bytes("hinted"));
        uint256 simpleBid = auction.submitBid(3000, 2e18, address(this), bytes("simple"));
        auction.exitBid(hintedBid);
        auction.exitPartiallyFilledBid(simpleBid, 10, 20);
        auction.claimTokens(hintedBid);
        uint256[] memory bidIds = new uint256[](1);
        bidIds[0] = simpleBid;
        auction.claimTokensBatch(address(this), bidIds);

        assertTrue(auction.bidExited(hintedBid));
        assertTrue(auction.bidExited(simpleBid));
        assertTrue(auction.bidClaimed(hintedBid));
        assertTrue(auction.bidClaimed(simpleBid));
    }

    function testMaxFinalizationBoundRevertsWithoutLifecycleProgress() external {
        auctionFactory.configureFinalization(2);
        RegentLBPStrategy pendingStrategy = new RegentLBPStrategy(_strategyConfig(1));
        token.mint(address(pendingStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        pendingStrategy.onTokensReceived();
        _wireFailureUnwind(pendingStrategy);

        MockDistributionContract auction =
            MockDistributionContract(pendingStrategy.auctionAddress());
        vm.roll(202);

        vm.prank(OPERATOR);
        vm.expectRevert("FINALIZATION_BOUND_MAX");
        pendingStrategy.progressFinalization(type(uint256).max);

        assertEq(auction.pendingFinalizationSteps(), 2);
        assertEq(auction.lastCheckpointedBlock(), 0);
        assertFalse(pendingStrategy.migrated());
        assertFalse(pendingStrategy.failedAuctionRecovered());
    }

    function testRecoverFailedAuctionBurnsEntireSupplyAndMarksSubjectDead() external {
        RegentLBPStrategy failedStrategy = new RegentLBPStrategy(_strategyConfig(1));
        token.mint(address(failedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        token.mint(address(vestingWallet), VESTING_AMOUNT);
        failedStrategy.onTokensReceived();
        _wireFailureUnwind(failedStrategy);

        MockDistributionContract auction = MockDistributionContract(failedStrategy.auctionAddress());
        uint256 deadBefore = token.balanceOf(DEAD_ADDRESS);

        vm.roll(303);
        vm.prank(OPERATOR);
        failedStrategy.recoverFailedAuction();

        // The whole launch-stack supply burns: unsold auction tokens + LP reserve + vesting.
        assertEq(
            token.balanceOf(DEAD_ADDRESS),
            deadBefore + AUCTION_AMOUNT + RESERVE_AMOUNT + VESTING_AMOUNT
        );
        assertEq(token.balanceOf(address(failedStrategy)), 0);
        assertEq(token.balanceOf(address(auction)), 0);
        assertEq(token.balanceOf(address(vestingWallet)), 0);
        // The agent got nothing.
        assertEq(token.balanceOf(AGENT_TREASURY), 0);
        assertTrue(failedStrategy.failedAuctionRecovered());

        // The subject is terminally retired directly in the registry. No splitter callback runs.
        assertEq(
            uint256(subjectRegistry.lifecycleOf(subjectId)),
            uint256(ISubjectRegistry.Lifecycle.Retired)
        );
        assertFalse(lifecycleSplitter.retired());
        assertTrue(lifecycleSplitter.lastActive());

        // The vesting wallet has nothing left to release, ever. The launch never graduated, so
        // release is gated shut on top of the burn having emptied the balance.
        assertTrue(vestingWallet.burnedOnFailedLaunch());
        assertFalse(vestingWallet.launchGraduated());
        vm.warp(VESTING_START + 730 days);
        assertEq(vestingWallet.releasableLaunchToken(), 0);
        vm.expectRevert("LAUNCH_NOT_GRADUATED");
        vestingWallet.releaseLaunchToken();
    }

    function testRecoverFailedAuctionCannotRunTwice() external {
        RegentLBPStrategy failedStrategy = new RegentLBPStrategy(_strategyConfig(1));
        token.mint(address(failedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        failedStrategy.onTokensReceived();
        _wireFailureUnwind(failedStrategy);

        vm.roll(303);
        vm.prank(OPERATOR);
        failedStrategy.recoverFailedAuction();

        vm.prank(OPERATOR);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        failedStrategy.recoverFailedAuction();
    }

    function testAgentCannotPullUnsoldTokensFromFailedAuction() external {
        // Adversarial: the agent safe is no longer the auction's tokens recipient, so it cannot
        // extract the 10% auction allocation from a failed launch.
        RegentLBPStrategy failedStrategy = new RegentLBPStrategy(_strategyConfig(1));
        token.mint(address(failedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        failedStrategy.onTokensReceived();

        MockDistributionContract auction = MockDistributionContract(failedStrategy.auctionAddress());

        vm.roll(303);
        vm.prank(AGENT_TREASURY);
        vm.expectRevert("ONLY_TOKENS_RECIPIENT");
        auction.sweepUnsoldTokens();
    }

    function testRecoverFailedAuctionRequiresOperator() external {
        RegentLBPStrategy failedStrategy = new RegentLBPStrategy(_strategyConfig(1));
        token.mint(address(failedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        failedStrategy.onTokensReceived();
        _wireFailureUnwind(failedStrategy);

        vm.roll(303);
        vm.prank(AGENT_TREASURY);
        vm.expectRevert("NOT_OPERATOR");
        failedStrategy.recoverFailedAuction();
    }

    function testRetirementPreservesFailedAuctionBidderRefundInventory() external {
        RegentLBPStrategy failedStrategy = new RegentLBPStrategy(_strategyConfig(100e18));
        token.mint(address(failedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        failedStrategy.onTokensReceived();
        _wireFailureUnwind(failedStrategy);

        MockDistributionContract auction = MockDistributionContract(failedStrategy.auctionAddress());
        quoteToken.mint(address(auction), 5e18);

        vm.roll(303);
        vm.prank(OPERATOR);
        failedStrategy.recoverFailedAuction();

        assertEq(quoteToken.balanceOf(address(auction)), 5e18);
        assertEq(quoteToken.balanceOf(AGENT_TREASURY), 0);
    }

    function testSoldOutFailedAuctionBurnsAllLaunchTokensAndPreservesRefunds() external {
        RegentLBPStrategy failedStrategy = new RegentLBPStrategy(_strategyConfig(100e18));
        token.mint(address(failedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        token.mint(address(vestingWallet), VESTING_AMOUNT);
        failedStrategy.onTokensReceived();
        _wireFailureUnwind(failedStrategy);

        MockDistributionContract auction = MockDistributionContract(failedStrategy.auctionAddress());
        auction.setSoldOut(true);
        quoteToken.mint(address(auction), 5e18);
        assertEq(auction.remainingSupply(), 0);
        assertEq(token.balanceOf(address(auction)), AUCTION_AMOUNT);

        uint256 deadBefore = token.balanceOf(DEAD_ADDRESS);
        vm.roll(303);
        vm.prank(OPERATOR);
        failedStrategy.recoverFailedAuction();

        assertEq(
            token.balanceOf(DEAD_ADDRESS),
            deadBefore + AUCTION_AMOUNT + RESERVE_AMOUNT + VESTING_AMOUNT
        );
        assertEq(token.balanceOf(address(auction)), 0);
        assertEq(quoteToken.balanceOf(address(auction)), 5e18);
        assertEq(quoteToken.balanceOf(AGENT_TREASURY), 0);
    }

    function testGraduatedAuctionSweepsFundsAfterEndAndMigrationUsesSweptCurrency() external {
        RegentLBPStrategy graduatedStrategy = new RegentLBPStrategy(_strategyConfig(100e18));
        _registerStrategySubject(graduatedStrategy);
        token.mint(address(graduatedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        graduatedStrategy.onTokensReceived();
        _registerOfficialPool(address(graduatedStrategy));

        MockDistributionContract auction =
            MockDistributionContract(graduatedStrategy.auctionAddress());
        quoteToken.mint(address(auction), 200e18);

        vm.expectRevert("AUCTION_NOT_ENDED");
        auction.sweepCurrency();

        vm.roll(102);
        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_FUNDS_RECIPIENT");
        auction.sweepCurrency();

        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_TOKENS_RECIPIENT");
        auction.sweepUnsoldTokens();

        // The agent safe is not the tokens recipient either — only the strategy is.
        vm.prank(AGENT_TREASURY);
        vm.expectRevert("ONLY_TOKENS_RECIPIENT");
        auction.sweepUnsoldTokens();

        assertEq(quoteToken.balanceOf(address(graduatedStrategy)), 0);
        assertEq(token.balanceOf(address(graduatedStrategy)), RESERVE_AMOUNT);

        vm.roll(202);
        vm.prank(OPERATOR);
        graduatedStrategy.migrate();

        assertTrue(graduatedStrategy.migrated());
        assertEq(graduatedStrategy.migratedQuoteTokenForLP(), (200e18 * 4000) / 10_000);
        assertEq(graduatedStrategy.migratedTokenForLP(), RESERVE_AMOUNT);

        // Unsold auction tokens route through the strategy into vesting at sweep time (plus a
        // wei or two of position-mint rounding refund from the reserve).
        vm.roll(303);
        vm.prank(OPERATOR);
        graduatedStrategy.sweepToken();
        assertGe(token.balanceOf(address(vestingWallet)), AUCTION_AMOUNT);
        assertApproxEqAbs(token.balanceOf(address(vestingWallet)), AUCTION_AMOUNT, 100);
        assertEq(token.balanceOf(AGENT_TREASURY), 0);
    }

    function testMigrateRejectsNonzeroEffectiveProtocolFee() external {
        RegentLBPStrategy graduatedStrategy = new RegentLBPStrategy(_strategyConfig(100e18));
        _registerStrategySubject(graduatedStrategy);
        token.mint(address(graduatedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        graduatedStrategy.onTokensReceived();
        _registerOfficialPool(address(graduatedStrategy));

        MockDistributionContract auction =
            MockDistributionContract(graduatedStrategy.auctionAddress());
        quoteToken.mint(address(auction), 200e18);
        auction.setProtocolFeeAmount(24e18);

        vm.roll(202);
        vm.prank(OPERATOR);
        vm.expectRevert("CCA_PROTOCOL_FEE_NONZERO");
        graduatedStrategy.migrate();

        assertFalse(graduatedStrategy.migrated());
        assertEq(graduatedStrategy.accountedAuctionQuoteToken(), 0);
    }

    function testFuzzGraduatedMigrationSplitsRaisedCurrencyFortySixty(uint128 raisedSeed) external {
        uint256 raised = bound(uint256(raisedSeed), 3e18, 1000e18);
        RegentLBPStrategy graduatedStrategy =
            new RegentLBPStrategy(_strategyConfig(uint128(raised)));
        _registerStrategySubject(graduatedStrategy);
        token.mint(address(graduatedStrategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        graduatedStrategy.onTokensReceived();
        _registerOfficialPool(address(graduatedStrategy));

        MockDistributionContract auction =
            MockDistributionContract(graduatedStrategy.auctionAddress());
        quoteToken.mint(address(auction), raised);

        vm.roll(202);
        vm.prank(OPERATOR);
        graduatedStrategy.migrate();

        // Exactly 40% of the raised REGENT is committed to the LP.
        uint256 lpShare = (raised * 4000) / 10_000;
        assertEq(graduatedStrategy.migratedQuoteTokenForLP(), lpShare);

        uint256 treasuryBefore = quoteToken.balanceOf(AGENT_TREASURY);

        vm.roll(303);
        vm.prank(OPERATOR);
        graduatedStrategy.sweepQuoteToken();

        // The other 60% reaches the agent treasury — never less, and never more than a few wei
        // of position-mint rounding refund on top.
        assertEq(quoteToken.balanceOf(address(graduatedStrategy)), 0);
        assertGe(quoteToken.balanceOf(AGENT_TREASURY), treasuryBefore + raised - lpShare);
        assertApproxEqAbs(
            quoteToken.balanceOf(AGENT_TREASURY), treasuryBefore + raised - lpShare, 100
        );
    }

    function testMigrateIgnoresUnsolicitedQuoteTokenDonation() external {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        _registerOfficialPool(address(strategy));
        quoteToken.mint(strategy.auctionAddress(), 200e18);
        quoteToken.mint(address(strategy), 10_000e18);

        vm.roll(202);
        vm.prank(OPERATOR);
        strategy.migrate();

        assertEq(strategy.accountedAuctionQuoteToken(), 200e18);
        assertEq(strategy.migratedQuoteTokenForLP(), 80e18);
        assertApproxEqAbs(quoteToken.balanceOf(address(strategy)), 10_120e18, 1);
    }

    function testSweepCurrencyCanSendResidualDonationAfterMigration() external {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        _registerOfficialPool(address(strategy));
        quoteToken.mint(strategy.auctionAddress(), 200e18);
        quoteToken.mint(address(strategy), 10_000e18);

        vm.roll(202);
        vm.prank(OPERATOR);
        strategy.migrate();

        uint256 treasuryBefore = quoteToken.balanceOf(AGENT_TREASURY);
        uint256 residual = quoteToken.balanceOf(address(strategy));

        vm.roll(303);
        vm.prank(OPERATOR);
        strategy.sweepQuoteToken();

        assertEq(quoteToken.balanceOf(address(strategy)), 0);
        assertEq(quoteToken.balanceOf(AGENT_TREASURY), treasuryBefore + residual);
    }

    function testRecoverFailedAuctionRevertsForGraduatedAuction() external {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();

        vm.roll(303);
        vm.prank(OPERATOR);
        vm.expectRevert("AUCTION_GRADUATED");
        strategy.recoverFailedAuction();
    }

    function testRecoverFailedAuctionRevertsAfterMigration() external {
        _registerStrategySubject(strategy);
        strategy.onTokensReceived();
        _registerOfficialPool(address(strategy));
        quoteToken.mint(strategy.auctionAddress(), 200e18);

        vm.roll(202);
        vm.prank(OPERATOR);
        strategy.migrate();

        vm.roll(303);
        vm.prank(OPERATOR);
        vm.expectRevert("ALREADY_MIGRATED");
        strategy.recoverFailedAuction();
    }

    function testTreasuryCanRescueUnsupportedAssetsButNotCanonicalOnes() external {
        MintableERC20Mock junk = new MintableERC20Mock("Junk", "JUNK");
        junk.mint(address(strategy), 7e18);
        vm.deal(address(strategy), 1 ether);

        vm.startPrank(AGENT_TREASURY);
        strategy.rescueUnsupportedToken(address(junk), 7e18, address(0x4444));
        strategy.rescueNative(address(0x5555));
        vm.stopPrank();

        assertEq(junk.balanceOf(address(0x4444)), 7e18);
        assertEq(address(strategy).balance, 0);
        assertEq(address(0x5555).balance, 1 ether);

        vm.prank(AGENT_TREASURY);
        vm.expectRevert("PROTECTED_TOKEN");
        strategy.rescueUnsupportedToken(address(quoteToken), 1, AGENT_TREASURY);
    }

    function _expectedPoolKey() internal view returns (PoolKey memory poolKey) {
        Currency tokenCurrency = Currency.wrap(address(token));
        Currency quoteCurrency = Currency.wrap(address(quoteToken));
        (Currency currency0, Currency currency1) = tokenCurrency < quoteCurrency
            ? (tokenCurrency, quoteCurrency)
            : (quoteCurrency, tokenCurrency);
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: OFFICIAL_POOL_FEE,
            tickSpacing: OFFICIAL_POOL_TICK_SPACING,
            hooks: IHooks(address(hook))
        });
    }

    function _auctionParameters() internal view returns (AuctionParameters memory) {
        return _auctionParameters(0);
    }

    function _auctionParameters(uint128 requiredCurrencyRaised)
        internal
        view
        returns (AuctionParameters memory)
    {
        return AuctionParameters({
            currency: address(quoteToken),
            tokensRecipient: address(0),
            fundsRecipient: address(0),
            startBlock: 1,
            endBlock: 101,
            claimBlock: 101,
            tickSpacing: 1000,
            validationHook: address(0),
            floorPrice: 1000,
            requiredCurrencyRaised: requiredCurrencyRaised,
            auctionStepsData: bytes("")
        });
    }

    function _strategyConfig(uint128 requiredCurrencyRaised)
        internal
        view
        returns (RegentLBPStrategy.StrategyConfig memory)
    {
        return RegentLBPStrategy.StrategyConfig({
            token: address(token),
            quoteToken: address(quoteToken),
            auctionInitializerFactory: address(auctionFactory),
            auctionParameters: _auctionParameters(requiredCurrencyRaised),
            officialPoolHook: address(hook),
            agentSafe: AGENT_TREASURY,
            vestingWallet: address(vestingWallet),
            operator: OPERATOR,
            positionManager: address(positionManager),
            poolManager: address(poolManager),
            subjectRegistry: address(subjectRegistry),
            officialPoolFee: OFFICIAL_POOL_FEE,
            officialPoolTickSpacing: OFFICIAL_POOL_TICK_SPACING,
            auctionCreator: address(this),
            migrationBlock: 202,
            sweepBlock: 303,
            tokenSplitToAuctionMps: 6_666_666,
            totalStrategySupply: AUCTION_AMOUNT + RESERVE_AMOUNT,
            auctionTokenAmount: AUCTION_AMOUNT,
            reserveTokenAmount: RESERVE_AMOUNT
        });
    }
}
