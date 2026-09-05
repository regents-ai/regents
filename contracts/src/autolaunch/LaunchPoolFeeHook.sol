// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

contract LaunchPoolFeeHook is IHooks {
    using Hooks for IHooks;
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for uint256;

    uint256 public constant TOTAL_FEE_BPS = 200;
    uint256 public constant SUBJECT_STAKING_FEE_BPS = 100;
    uint256 public constant REGENT_STAKING_FEE_BPS = 100;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    // High-risk v4 permissions: beforeInitialize, beforeSwap, afterSwap, beforeSwapReturnDelta,
    // and afterSwapReturnDelta. beforeInitialize gates pool creation to the registry-authorized
    // initializer so a graduated launch cannot be front-run. The return-delta permissions are
    // required so the hook can charge the configured quote-token fee through PoolManager accounting.
    uint160 public constant REQUIRED_HOOK_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG
        | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    struct SwapFeeComputation {
        address chargedCurrency;
        uint256 chargedAmount;
        uint256 totalFee;
        uint256 subjectStakingFee;
        uint256 regentFee;
        bool exactInput;
    }

    LaunchFeeRegistry public immutable registryContract;
    LaunchFeeVault public immutable vaultContract;
    IPoolManager public immutable poolManagerContract;

    error HookNotImplemented();

    event SwapFeeAccrued(
        bytes32 indexed poolId,
        address indexed payer,
        address indexed currency,
        uint256 chargedAmount,
        uint256 totalFee,
        uint256 subjectStakingFee,
        uint256 regentFee,
        bool exactInput
    );

    address public immutable feeInfraDeployer;

    constructor(
        address feeInfraDeployer_,
        address poolManager_,
        address registry_,
        address vault_
    ) {
        require(feeInfraDeployer_ == msg.sender, "DEPLOYER_MISMATCH");
        require(poolManager_ != address(0), "POOL_MANAGER_ZERO");
        require(registry_ != address(0), "REGISTRY_ZERO");
        require(vault_ != address(0), "VAULT_ZERO");

        feeInfraDeployer = feeInfraDeployer_;
        poolManagerContract = IPoolManager(poolManager_);
        registryContract = LaunchFeeRegistry(registry_);
        vaultContract = LaunchFeeVault(payable(vault_));

        IHooks(address(this)).validateHookPermissions(_permissions());
    }

    function beforeInitialize(address sender, PoolKey calldata key, uint160)
        external
        view
        returns (bytes4)
    {
        require(msg.sender == address(poolManagerContract), "ONLY_POOL_MANAGER");

        bytes32 poolId = PoolId.unwrap(key.toId());
        LaunchFeeRegistry.PoolConfig memory config = _validatePool(poolId);
        require(sender == config.authorizedInitializer, "UNAUTHORIZED_INITIALIZER");

        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) external returns (bytes4, BeforeSwapDelta, uint24) {
        require(msg.sender == address(poolManagerContract), "ONLY_POOL_MANAGER");

        bytes32 poolId = PoolId.unwrap(key.toId());
        LaunchFeeRegistry.PoolConfig memory config = _validatePool(poolId);
        if (!_quoteTokenIsSpecified(key, params, config.quoteToken)) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        SwapFeeComputation memory feeData = _computeSpecifiedQuoteFee(params, config.quoteToken);
        if (feeData.totalFee == 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        _accrueQuoteFee(poolId, sender, feeData);

        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(feeData.totalFee.toInt128(), 0), 0);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external returns (bytes4, int128) {
        require(msg.sender == address(poolManagerContract), "ONLY_POOL_MANAGER");

        bytes32 poolId = PoolId.unwrap(key.toId());
        LaunchFeeRegistry.PoolConfig memory config = _validatePool(poolId);
        if (!_quoteTokenIsUnspecified(key, params, config.quoteToken)) {
            return (IHooks.afterSwap.selector, 0);
        }

        SwapFeeComputation memory feeData =
            _computeUnspecifiedQuoteFee(key, params, delta, config.quoteToken);
        if (feeData.totalFee == 0) {
            return (IHooks.afterSwap.selector, 0);
        }

        _accrueQuoteFee(poolId, sender, feeData);

        return (IHooks.afterSwap.selector, feeData.totalFee.toInt128());
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function getHookPermissions() external pure returns (Hooks.Permissions memory) {
        return _permissions();
    }

    function _permissions() internal pure returns (Hooks.Permissions memory permissions) {
        permissions.beforeInitialize = true;
        permissions.beforeSwap = true;
        permissions.afterSwap = true;
        permissions.beforeSwapReturnDelta = true;
        permissions.afterSwapReturnDelta = true;
    }

    function _computeSpecifiedQuoteFee(SwapParams calldata params, address quoteToken)
        internal
        pure
        returns (SwapFeeComputation memory feeData)
    {
        uint256 chargedAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
        feeData = _feeData(quoteToken, chargedAmount, params.amountSpecified < 0);
    }

    function _computeUnspecifiedQuoteFee(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        address quoteToken
    ) internal pure returns (SwapFeeComputation memory feeData) {
        bool chargeCurrency0 = _unspecifiedCurrency0(params);
        int128 chargedDelta = chargeCurrency0 ? delta.amount0() : delta.amount1();
        uint128 chargedAmount = _absUint128(chargedDelta);

        address chargedCurrency =
            chargeCurrency0 ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
        require(chargedCurrency == quoteToken, "QUOTE_TOKEN_MISMATCH");
        feeData = _feeData(quoteToken, chargedAmount, params.amountSpecified < 0);
    }

    function _absUint128(int128 value) internal pure returns (uint128) {
        require(value != type(int128).min, "DELTA_OVERFLOW");
        int128 magnitude = value < 0 ? -value : value;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(magnitude);
    }

    function _feeData(address quoteToken, uint256 chargedAmount, bool exactInput)
        internal
        pure
        returns (SwapFeeComputation memory feeData)
    {
        feeData.chargedCurrency = quoteToken;
        feeData.chargedAmount = chargedAmount;
        feeData.subjectStakingFee =
            feeData.chargedAmount * SUBJECT_STAKING_FEE_BPS / BPS_DENOMINATOR;
        feeData.regentFee = feeData.chargedAmount * REGENT_STAKING_FEE_BPS / BPS_DENOMINATOR;
        feeData.totalFee = feeData.subjectStakingFee + feeData.regentFee;
        feeData.exactInput = exactInput;
    }

    function _accrueQuoteFee(bytes32 poolId, address sender, SwapFeeComputation memory feeData)
        internal
    {
        _emitSwapFeeAccrued(
            poolId,
            sender,
            feeData.chargedCurrency,
            feeData.chargedAmount,
            feeData.totalFee,
            feeData.subjectStakingFee,
            feeData.regentFee,
            feeData.exactInput
        );

        poolManagerContract.take(
            Currency.wrap(feeData.chargedCurrency), address(vaultContract), feeData.totalFee
        );
        vaultContract.recordAccrual(
            poolId, feeData.chargedCurrency, feeData.subjectStakingFee, feeData.regentFee
        );
    }

    function _quoteTokenIsSpecified(
        PoolKey calldata key,
        SwapParams calldata params,
        address quoteToken
    ) internal pure returns (bool) {
        return (_specifiedCurrency0(params)
                    ? Currency.unwrap(key.currency0)
                    : Currency.unwrap(key.currency1)) == quoteToken;
    }

    function _quoteTokenIsUnspecified(
        PoolKey calldata key,
        SwapParams calldata params,
        address quoteToken
    ) internal pure returns (bool) {
        return (_unspecifiedCurrency0(params)
                    ? Currency.unwrap(key.currency0)
                    : Currency.unwrap(key.currency1)) == quoteToken;
    }

    function _specifiedCurrency0(SwapParams calldata params) internal pure returns (bool) {
        return (params.amountSpecified < 0) == params.zeroForOne;
    }

    function _unspecifiedCurrency0(SwapParams calldata params) internal pure returns (bool) {
        return !_specifiedCurrency0(params);
    }

    function _validatePool(bytes32 poolId)
        internal
        view
        returns (LaunchFeeRegistry.PoolConfig memory config)
    {
        config = registryContract.getPoolConfig(poolId);
        registryContract.requireActiveFeeInfrastructure(address(vaultContract), address(this));
        registryContract.requireSubjectStakingBinding();
        require(config.hookEnabled, "HOOK_DISABLED");
        require(config.poolManager == msg.sender, "POOL_MANAGER_MISMATCH");
        require(config.hook == address(this), "HOOK_MISMATCH");
        require(config.quoteToken != address(0), "QUOTE_TOKEN_ZERO");
    }

    function _emitSwapFeeAccrued(
        bytes32 poolId,
        address sender,
        address chargedCurrency,
        uint256 chargedAmount,
        uint256 totalFee,
        uint256 subjectStakingFee,
        uint256 regentFee,
        bool exactInput
    ) internal {
        emit SwapFeeAccrued(
            poolId,
            sender,
            chargedCurrency,
            chargedAmount,
            totalFee,
            subjectStakingFee,
            regentFee,
            exactInput
        );
    }
}
