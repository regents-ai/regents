// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockHookDeployer} from "test/mocks/MockHookDeployer.sol";
import {MockHookPoolManager, MockFeeSubjectRegistry} from "test/mocks/MockHookPoolManager.sol";

contract HookRegentFundingTarget {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    uint256 public totalFundedRegent;

    function fundRegentRewards(uint256 amount) external returns (uint256) {
        MintableERC20Mock(REGENT).transferFrom(msg.sender, address(this), amount);
        totalFundedRegent += amount;
        return amount;
    }
}

contract HookSubjectRegentSplitter {
    uint256 public constant ACC_PRECISION = 1e27;
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;

    address public immutable stakeToken;
    bytes32 public immutable subjectId;
    address public immutable subjectRegistry;
    uint256 public totalRegentReceived;
    uint256 public reservedRegent;

    constructor(address stakeToken_, bytes32 subjectId_, address subjectRegistry_) {
        stakeToken = stakeToken_;
        subjectId = subjectId_;
        subjectRegistry = subjectRegistry_;
    }

    function totalStaked() external pure returns (uint256) {
        return 0;
    }

    function accRewardPerTokenRegent() external pure returns (uint256) {
        return 0;
    }

    function fundRegentRewards(uint256 amount) external returns (uint256 received) {
        uint256 beforeBalance = MintableERC20Mock(REGENT).balanceOf(address(this));
        MintableERC20Mock(REGENT).transferFrom(msg.sender, address(this), amount);
        received = MintableERC20Mock(REGENT).balanceOf(address(this)) - beforeBalance;
        totalRegentReceived += received;
        reservedRegent += received;
    }
}

contract RealPoolManagerHarness is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeTransferLib for address;
    using TransientStateLibrary for IPoolManager;

    enum Action {
        MODIFY_LIQUIDITY,
        SWAP
    }
    IPoolManager public immutable poolManager;

    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params) external {
        poolManager.unlock(abi.encode(Action.MODIFY_LIQUIDITY, abi.encode(key, params)));
    }

    function swap(PoolKey memory key, SwapParams memory params)
        external
        returns (int128 amount0, int128 amount1)
    {
        bytes memory result = poolManager.unlock(abi.encode(Action.SWAP, abi.encode(key, params)));
        return abi.decode(result, (int128, int128));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "ONLY_POOL_MANAGER");
        (Action action, bytes memory inner) = abi.decode(data, (Action, bytes));
        if (action == Action.MODIFY_LIQUIDITY) {
            (PoolKey memory liquidityKey, ModifyLiquidityParams memory liquidityParams) =
                abi.decode(inner, (PoolKey, ModifyLiquidityParams));
            (BalanceDelta liquidityDelta,) =
                poolManager.modifyLiquidity(liquidityKey, liquidityParams, "");
            _resolve(liquidityKey.currency0);
            _resolve(liquidityKey.currency1);
            return abi.encode(liquidityDelta.amount0(), liquidityDelta.amount1());
        }
        (PoolKey memory swapKey, SwapParams memory swapParams) =
            abi.decode(inner, (PoolKey, SwapParams));
        BalanceDelta swapDelta = poolManager.swap(swapKey, swapParams, "");
        _resolve(swapKey.currency0);
        _resolve(swapKey.currency1);
        return abi.encode(swapDelta.amount0(), swapDelta.amount1());
    }

    function _resolve(Currency currency) internal {
        int256 delta = poolManager.currencyDelta(address(this), currency);
        if (delta < 0) {
            uint256 amount = uint256(-delta);
            poolManager.sync(currency);
            Currency.unwrap(currency).safeTransfer(address(poolManager), amount);
            poolManager.settle();
        } else if (delta > 0) {
            poolManager.take(currency, address(this), uint256(delta));
        }
    }
}

contract LaunchPoolFeeHookTest is Test {
    using PoolIdLibrary for PoolKey;

    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;
    address internal constant AGENT_SAFE = address(0xA11CE);
    address internal constant TRADER = address(0xB0B);
    uint24 internal constant POOL_FEE = 3000;
    int24 internal constant TICK_SPACING = 60;
    bytes32 internal constant SUBJECT_ID = keccak256("mock-subject");
    bytes32 internal constant REAL_SUBJECT_ID = keccak256("real-subject");

    MintableERC20Mock internal regent;
    MintableERC20Mock internal launchToken;
    MockFeeSubjectRegistry internal subjectRegistry;
    LaunchFeeRegistry internal registry;
    LaunchFeeVault internal vault;
    MockHookDeployer internal hookDeployer;
    MockHookPoolManager internal poolManager;
    LaunchPoolFeeHook internal hook;
    PoolKey internal poolKey;
    bytes32 internal poolId;
    mapping(bytes32 => HookSubjectRegentSplitter) internal subjectSplitters;

    PoolManager internal realPoolManager;
    RealPoolManagerHarness internal realHarness;
    MintableERC20Mock internal realLaunchToken;
    MockFeeSubjectRegistry internal realSubjectRegistry;
    LaunchFeeRegistry internal realRegistry;
    LaunchFeeVault internal realVault;
    LaunchPoolFeeHook internal realHook;
    PoolKey internal realPoolKey;
    bytes32 internal realPoolId;

    function setUp() external {
        MintableERC20Mock regentImplementation = new MintableERC20Mock("REGENT", "REGENT");
        vm.etch(REGENT, address(regentImplementation).code);
        regent = MintableERC20Mock(REGENT);
        launchToken = new MintableERC20Mock("Launch", "LAUNCH");
        hookDeployer = new MockHookDeployer();
        poolManager = new MockHookPoolManager();
        subjectRegistry = new MockFeeSubjectRegistry();
        registry = new LaunchFeeRegistry(
            AGENT_SAFE, address(this), address(subjectRegistry), SUBJECT_ID, REGENT
        );
        vault = new LaunchFeeVault(address(registry));
        hook = hookDeployer.deploy(address(poolManager), address(registry), address(vault));
        vault.setHook(address(hook));
        _setSubject(subjectRegistry, SUBJECT_ID, registry, vault, hook, launchToken, address(this));
        poolId = registry.registerPool(
            _registration(address(launchToken), address(poolManager), address(hook))
        );
        vault.setCanonicalTokens(poolId);
        poolKey = _sortedPoolKey(address(launchToken), REGENT, address(hook));
        regent.mint(address(poolManager), 100_000e18);

        realPoolManager = new PoolManager(AGENT_SAFE);
        realHarness = new RealPoolManagerHarness(realPoolManager);
        realLaunchToken = new MintableERC20Mock("Real Launch", "RLAUNCH");
        realSubjectRegistry = new MockFeeSubjectRegistry();
        realRegistry = new LaunchFeeRegistry(
            AGENT_SAFE, address(this), address(realSubjectRegistry), REAL_SUBJECT_ID, REGENT
        );
        realVault = new LaunchFeeVault(address(realRegistry));
        realHook = hookDeployer.deploy(
            address(realPoolManager), address(realRegistry), address(realVault)
        );
        realVault.setHook(address(realHook));
        _setSubject(
            realSubjectRegistry,
            REAL_SUBJECT_ID,
            realRegistry,
            realVault,
            realHook,
            realLaunchToken,
            address(this)
        );
        realPoolId = realRegistry.registerPool(
            _registration(address(realLaunchToken), address(realPoolManager), address(realHook))
        );
        realVault.setCanonicalTokens(realPoolId);
        realPoolKey = _sortedPoolKey(address(realLaunchToken), REGENT, address(realHook));
        realLaunchToken.mint(address(realHarness), 100_000e18);
        regent.mint(address(realHarness), 100_000e18);
        realPoolManager.initialize(realPoolKey, TickMath.getSqrtPriceAtTick(0));
        realHarness.modifyLiquidity(
            realPoolKey,
            ModifyLiquidityParams({
                tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18, salt: bytes32(0)
            })
        );
    }

    function testFourArgumentConstructorBindsActualDeployerAndFinalOwner() external view {
        assertEq(hook.feeInfraDeployer(), address(hookDeployer));
        assertEq(registry.agentSafe(), AGENT_SAFE);
        assertEq(uint160(address(hook)) & uint160((1 << 14) - 1), hook.REQUIRED_HOOK_FLAGS());
    }

    function testBeforeInitializePermissionAndFlagAreEnabled() external view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeInitialize);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertTrue(permissions.beforeSwapReturnDelta);
        assertTrue(permissions.afterSwapReturnDelta);
        assertFalse(permissions.afterInitialize);
        assertTrue(uint160(address(hook)) & Hooks.BEFORE_INITIALIZE_FLAG != 0);
        assertTrue(uint160(address(realHook)) & Hooks.BEFORE_INITIALIZE_FLAG != 0);
    }

    function testUnauthorizedInitializerIsRejected() external {
        vm.prank(address(poolManager));
        vm.expectRevert("UNAUTHORIZED_INITIALIZER");
        hook.beforeInitialize(address(0xBAD), poolKey, TickMath.getSqrtPriceAtTick(0));
    }

    function testLegitimateInitializerCanCreatePool() external view {
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(realPoolManager, PoolId.wrap(realPoolId));
        assertTrue(sqrtPriceX96 != 0);
    }

    function testZeroForOneExactInputChargesRegent() external {
        _assertSwapFee(true, -100e18, -100e18, 80e18);
    }

    function testZeroForOneExactOutputChargesRegent() external {
        _assertSwapFee(true, 90e18, -120e18, 90e18);
    }

    function testOneForZeroExactInputChargesRegent() external {
        _assertSwapFee(false, -100e18, 70e18, -100e18);
    }

    function testOneForZeroExactOutputChargesRegent() external {
        _assertSwapFee(false, 80e18, 80e18, -110e18);
    }

    function testEachFeeHalfIsExactlyOnePercentAcrossRoundingBoundaries() external {
        _simulateSwap(99, -99, 99);
        assertEq(vault.subjectAccrued(poolId, REGENT), 0);
        assertEq(vault.regentAccrued(poolId, REGENT), 0);

        _simulateSwap(100, -100, 98);
        assertEq(vault.subjectAccrued(poolId, REGENT), 1);
        assertEq(vault.regentAccrued(poolId, REGENT), 1);

        _simulateSwap(199, -199, 195);
        assertEq(vault.subjectAccrued(poolId, REGENT), 2);
        assertEq(vault.regentAccrued(poolId, REGENT), 2);
    }

    function testOrdinaryPoolFeeRemainsIndependentFromTwoPercentHookFee() external {
        (, BeforeSwapDelta beforeDelta, uint24 feeOverride) = poolManager.simulateBeforeSwap(
            address(hook),
            TRADER,
            poolKey,
            SwapParams({
                zeroForOne: _regentIsCurrency0(poolKey),
                amountSpecified: -100e18,
                sqrtPriceLimitX96: 0
            })
        );
        assertEq(registry.getPoolConfig(poolId).poolFee, POOL_FEE);
        assertEq(feeOverride, 0);
        assertEq(uint128(BeforeSwapDeltaLibrary.getSpecifiedDelta(beforeDelta)), 2e18);
    }

    function testRealPoolManagerExactInputAccruesSeparateHookFee() external {
        bool regentIsCurrency0 = _regentIsCurrency0(realPoolKey);
        realHarness.swap(
            realPoolKey,
            SwapParams({
                zeroForOne: regentIsCurrency0,
                amountSpecified: -10e18,
                sqrtPriceLimitX96: regentIsCurrency0
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            })
        );
        assertEq(realRegistry.getPoolConfig(realPoolId).poolFee, POOL_FEE);
        assertEq(realVault.subjectAccrued(realPoolId, REGENT), 0.1e18);
        assertEq(realVault.regentAccrued(realPoolId, REGENT), 0.1e18);
    }

    function testRealPoolManagerExactOutputAccruesSeparateHookFee() external {
        bool zeroForOne = !_regentIsCurrency0(realPoolKey);
        realHarness.swap(
            realPoolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: 5e18,
                sqrtPriceLimitX96: zeroForOne
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            })
        );
        assertEq(realRegistry.getPoolConfig(realPoolId).poolFee, POOL_FEE);
        assertEq(realVault.subjectAccrued(realPoolId, REGENT), 0.05e18);
        assertEq(realVault.regentAccrued(realPoolId, REGENT), 0.05e18);
    }

    function testQuarantineBlocksInitializeSwapTakeAndAccrual() external {
        subjectRegistry.setLifecycle(SUBJECT_ID, ISubjectRegistry.Lifecycle.Quarantined);
        uint256 managerBefore = regent.balanceOf(address(poolManager));

        vm.prank(address(poolManager));
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        hook.beforeInitialize(address(this), poolKey, TickMath.getSqrtPriceAtTick(0));

        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        _simulateSwap(100e18, -100e18, 98e18);

        assertEq(regent.balanceOf(address(poolManager)), managerBefore);
        assertEq(regent.balanceOf(address(vault)), 0);
        assertEq(vault.subjectAccrued(poolId, REGENT), 0);
        assertEq(vault.regentAccrued(poolId, REGENT), 0);
    }

    function testRejectsDirectBeforeSwapCallFromNonPoolManager() external {
        vm.expectRevert("ONLY_POOL_MANAGER");
        hook.beforeSwap(
            TRADER,
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -100e18, sqrtPriceLimitX96: 0}),
            ""
        );
    }

    function testRejectsDirectAfterSwapCallFromNonPoolManager() external {
        vm.expectRevert("ONLY_POOL_MANAGER");
        hook.afterSwap(
            TRADER,
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -100e18, sqrtPriceLimitX96: 0}),
            BalanceDelta.wrap(0),
            ""
        );
    }

    function testRejectsPoolRegisteredForDifferentPoolManager() external {
        MintableERC20Mock token = new MintableERC20Mock("Other", "OTHER");
        (
            MockFeeSubjectRegistry otherSubjectRegistry,
            LaunchFeeRegistry otherRegistry,
            LaunchFeeVault otherVault,
            LaunchPoolFeeHook otherHook
        ) = _freshInfrastructure();
        _setSubject(
            otherSubjectRegistry,
            keccak256("fresh-subject"),
            otherRegistry,
            otherVault,
            otherHook,
            token,
            address(this)
        );
        otherRegistry.registerPool(_registrationFor(token, address(0xDEAD), address(otherHook)));
        otherVault.setCanonicalTokens(
            otherRegistry.computePoolId(
                address(token), REGENT, POOL_FEE, TICK_SPACING, address(otherHook)
            )
        );
        PoolKey memory key = _sortedPoolKey(address(token), REGENT, address(otherHook));

        vm.expectRevert("POOL_MANAGER_MISMATCH");
        poolManager.simulateBeforeSwap(
            address(otherHook),
            TRADER,
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100e18, sqrtPriceLimitX96: 0})
        );
    }

    function testRejectsPoolRegisteredForDifferentHook() external {
        MintableERC20Mock token = new MintableERC20Mock("Other", "OTHER");
        (
            MockFeeSubjectRegistry otherSubjectRegistry,
            LaunchFeeRegistry otherRegistry,
            LaunchFeeVault otherVault,
            LaunchPoolFeeHook otherHook
        ) = _freshInfrastructure();
        address wrongHook = address(0x1234);
        _setSubjectWithHook(
            otherSubjectRegistry,
            keccak256("fresh-subject"),
            otherRegistry,
            otherVault,
            wrongHook,
            token,
            address(this)
        );
        otherRegistry.registerPool(_registrationFor(token, address(poolManager), wrongHook));
        _setSubject(
            otherSubjectRegistry,
            keccak256("fresh-subject"),
            otherRegistry,
            otherVault,
            otherHook,
            token,
            address(this)
        );
        PoolKey memory key = _sortedPoolKey(address(token), REGENT, wrongHook);

        vm.expectRevert("HOOK_MISMATCH");
        poolManager.simulateBeforeSwap(
            address(otherHook),
            TRADER,
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100e18, sqrtPriceLimitX96: 0})
        );
    }

    function testUnregisteredPoolCannotChargeFee() external {
        PoolKey memory unknownKey = poolKey;
        unknownKey.tickSpacing = 120;
        vm.expectRevert("POOL_NOT_REGISTERED");
        poolManager.simulateBeforeSwap(
            address(hook),
            TRADER,
            unknownKey,
            SwapParams({zeroForOne: true, amountSpecified: -100e18, sqrtPriceLimitX96: 0})
        );
    }

    function testRejectsPoolRegistrationWithoutQuoteToken() external {
        MintableERC20Mock token = new MintableERC20Mock("Other", "OTHER");
        MockFeeSubjectRegistry otherSubjectRegistry = new MockFeeSubjectRegistry();
        bytes32 otherSubjectId = keccak256("quote-zero-subject");
        LaunchFeeRegistry otherRegistry = new LaunchFeeRegistry(
            AGENT_SAFE, address(this), address(otherSubjectRegistry), otherSubjectId, REGENT
        );
        _setSubjectWithHook(
            otherSubjectRegistry,
            otherSubjectId,
            otherRegistry,
            vault,
            address(hook),
            token,
            address(this)
        );
        LaunchFeeRegistry.PoolRegistration memory registration =
            _registrationFor(token, address(poolManager), address(hook));
        registration.quoteToken = address(0);

        vm.expectRevert("QUOTE_TOKEN_NOT_CANONICAL");
        otherRegistry.registerPool(registration);
    }

    function testAgentSafeCanDisableAndReEnableActiveFeeCapture() external {
        vm.prank(AGENT_SAFE);
        registry.setHookEnabled(poolId, false);
        vm.expectRevert("HOOK_DISABLED");
        _simulateSwap(100e18, -100e18, 98e18);

        vm.prank(AGENT_SAFE);
        registry.setHookEnabled(poolId, true);
        _assertSwapFee(_regentIsCurrency0(poolKey), -100e18, -100e18, 98e18);
    }

    function testFuzzRegentFeesAreFullyBackedAndClaimable(uint128 amountSeed) external {
        uint256 amount = bound(uint256(amountSeed), 100, 1_000_000e18);
        uint256 share = amount / 100;
        regent.mint(address(poolManager), share * 2);
        uint256 subjectBefore = regent.balanceOf(address(subjectSplitters[SUBJECT_ID]));

        _simulateSwap(amount, -int128(int256(amount)), int128(int256(amount)));
        assertEq(vault.subjectAccrued(poolId, REGENT), share);
        assertEq(vault.regentAccrued(poolId, REGENT), share);
        assertEq(regent.balanceOf(address(vault)), share * 2);

        HookRegentFundingTarget target = new HookRegentFundingTarget();
        vm.etch(STAKING, address(target).code);
        vault.fundSubjectShare(poolId);
        vault.fundRegentShare(poolId);

        assertEq(regent.balanceOf(address(subjectSplitters[SUBJECT_ID])) - subjectBefore, share);
        assertEq(regent.balanceOf(STAKING), share);
        assertEq(HookRegentFundingTarget(STAKING).totalFundedRegent(), share);
        assertEq(regent.balanceOf(address(vault)), 0);
        assertEq(vault.subjectAccrued(poolId, REGENT), 0);
        assertEq(vault.regentAccrued(poolId, REGENT), 0);
    }

    function _simulateSwap(uint256 amount, int128 amount0, int128 amount1) internal {
        bool regentIsCurrency0 = _regentIsCurrency0(poolKey);
        poolManager.simulateSwap(
            address(hook),
            TRADER,
            poolKey,
            SwapParams({
                zeroForOne: regentIsCurrency0,
                amountSpecified: -int256(amount),
                sqrtPriceLimitX96: 0
            }),
            amount0,
            amount1
        );
    }

    function _assertSwapFee(bool zeroForOne, int256 amountSpecified, int128 amount0, int128 amount1)
        internal
    {
        bool exactInput = amountSpecified < 0;
        bool specifiedCurrency0 = exactInput == zeroForOne;
        bool quoteIsSpecified = specifiedCurrency0 == _regentIsCurrency0(poolKey);
        int128 chargedDelta = (!specifiedCurrency0) ? amount0 : amount1;
        uint256 baseAmount = quoteIsSpecified
            ? uint256(amountSpecified < 0 ? -amountSpecified : amountSpecified)
            : uint256(uint128(chargedDelta < 0 ? -chargedDelta : chargedDelta));
        uint256 share = baseAmount / 100;
        uint256 totalFee = share * 2;

        (
            bytes4 beforeSelector,
            BeforeSwapDelta beforeDelta,
            bytes4 afterSelector,
            int128 afterDelta
        ) = poolManager.simulateSwap(
            address(hook),
            TRADER,
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0
            }),
            amount0,
            amount1
        );

        assertEq(beforeSelector, IHooks.beforeSwap.selector);
        assertEq(afterSelector, IHooks.afterSwap.selector);
        assertEq(
            uint128(BeforeSwapDeltaLibrary.getSpecifiedDelta(beforeDelta)),
            quoteIsSpecified ? totalFee : 0
        );
        assertEq(uint128(afterDelta), quoteIsSpecified ? 0 : totalFee);
        assertEq(BeforeSwapDeltaLibrary.getUnspecifiedDelta(beforeDelta), 0);
        assertEq(poolManager.lastTakeCurrency(), REGENT);
        assertEq(poolManager.lastTakeRecipient(), address(vault));
        assertEq(poolManager.lastTakeAmount(), totalFee);
        assertEq(vault.subjectAccrued(poolId, REGENT), share);
        assertEq(vault.regentAccrued(poolId, REGENT), share);
        assertEq(regent.balanceOf(address(vault)), totalFee);
    }

    function _freshInfrastructure()
        internal
        returns (
            MockFeeSubjectRegistry otherSubjectRegistry,
            LaunchFeeRegistry otherRegistry,
            LaunchFeeVault otherVault,
            LaunchPoolFeeHook otherHook
        )
    {
        otherSubjectRegistry = new MockFeeSubjectRegistry();
        otherRegistry = new LaunchFeeRegistry(
            AGENT_SAFE,
            address(this),
            address(otherSubjectRegistry),
            keccak256("fresh-subject"),
            REGENT
        );
        otherVault = new LaunchFeeVault(address(otherRegistry));
        otherHook =
            hookDeployer.deploy(address(poolManager), address(otherRegistry), address(otherVault));
        otherVault.setHook(address(otherHook));
    }

    function _registrationFor(MintableERC20Mock token, address manager, address hookAddress)
        internal
        view
        returns (LaunchFeeRegistry.PoolRegistration memory)
    {
        return _registration(address(token), manager, hookAddress);
    }

    function _registration(address token, address manager, address hookAddress)
        internal
        view
        returns (LaunchFeeRegistry.PoolRegistration memory)
    {
        return LaunchFeeRegistry.PoolRegistration({
            launchToken: token,
            quoteToken: REGENT,
            poolFee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            poolManager: manager,
            hook: hookAddress,
            authorizedInitializer: address(this)
        });
    }

    function _setSubject(
        MockFeeSubjectRegistry subjectRegistry_,
        bytes32 subjectId_,
        LaunchFeeRegistry registry_,
        LaunchFeeVault vault_,
        LaunchPoolFeeHook hook_,
        MintableERC20Mock token,
        address strategy
    ) internal {
        _setSubjectWithHook(
            subjectRegistry_, subjectId_, registry_, vault_, address(hook_), token, strategy
        );
    }

    function _setSubjectWithHook(
        MockFeeSubjectRegistry subjectRegistry_,
        bytes32 subjectId_,
        LaunchFeeRegistry registry_,
        LaunchFeeVault vault_,
        address hook_,
        MintableERC20Mock token,
        address strategy
    ) internal {
        HookSubjectRegentSplitter subjectSplitter = new HookSubjectRegentSplitter(
            address(token), subjectId_, address(subjectRegistry_)
        );
        subjectSplitters[subjectId_] = subjectSplitter;
        subjectRegistry_.setSubject(
            subjectId_,
            ISubjectRegistry.SubjectConfig({
                stakeToken: address(token),
                splitter: address(subjectSplitter),
                treasurySafe: AGENT_SAFE,
                ingress: address(2),
                paymentLinkFactory: address(3),
                strategy: strategy,
                launchFeeRegistry: address(registry_),
                feeVault: address(vault_),
                feeHook: hook_,
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                lifecycle: ISubjectRegistry.Lifecycle.Active,
                label: "subject",
                safeRuntime: address(4)
            })
        );
    }

    function _sortedPoolKey(address tokenA, address tokenB, address hookAddress)
        internal
        pure
        returns (PoolKey memory)
    {
        (address currency0, address currency1) =
            tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hookAddress)
        });
    }

    function _regentIsCurrency0(PoolKey memory key) internal pure returns (bool) {
        return Currency.unwrap(key.currency0) == REGENT;
    }
}
