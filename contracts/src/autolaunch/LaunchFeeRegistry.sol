// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

interface ISubjectSplitterBinding {
    function stakeToken() external view returns (address);
    function subjectId() external view returns (bytes32);
    function subjectRegistry() external view returns (address);
}

contract LaunchFeeRegistry {
    using PoolIdLibrary for PoolKey;

    address public constant REGENT_REVENUE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;

    struct PoolRegistration {
        address launchToken;
        address quoteToken;
        uint24 poolFee;
        int24 tickSpacing;
        address poolManager;
        address hook;
        address authorizedInitializer;
    }

    struct PoolConfig {
        address launchToken;
        address quoteToken;
        address currency0;
        address currency1;
        uint24 poolFee;
        int24 tickSpacing;
        address poolManager;
        address hook;
        address authorizedInitializer;
        bool hookEnabled;
    }

    mapping(bytes32 => PoolConfig) private poolConfigs;
    address public immutable canonicalQuoteToken;
    ISubjectRegistry public immutable subjectRegistry;
    bytes32 public immutable subjectId;
    address public immutable agentSafe;
    address public setupAuthority;

    event PoolRegistered(
        bytes32 indexed poolId,
        address indexed launchToken,
        address indexed quoteToken,
        address subjectStakingRecipient,
        address poolManager,
        address hook,
        address authorizedInitializer
    );
    event HookStatusSet(bytes32 indexed poolId, bool enabled);

    constructor(
        address agentSafe_,
        address setupAuthority_,
        address subjectRegistry_,
        bytes32 subjectId_,
        address canonicalQuoteToken_
    ) {
        require(agentSafe_ != address(0), "AGENT_SAFE_ZERO");
        require(setupAuthority_ != address(0), "SETUP_AUTHORITY_ZERO");
        require(subjectRegistry_ != address(0), "SUBJECT_REGISTRY_ZERO");
        require(subjectId_ != bytes32(0), "SUBJECT_ID_ZERO");
        require(canonicalQuoteToken_ != address(0), "QUOTE_TOKEN_ZERO");
        setupAuthority = setupAuthority_;
        subjectRegistry = ISubjectRegistry(subjectRegistry_);
        subjectId = subjectId_;
        agentSafe = agentSafe_;
        canonicalQuoteToken = canonicalQuoteToken_;
    }

    function registerPool(PoolRegistration memory registration) external returns (bytes32 poolId) {
        require(msg.sender == setupAuthority, "ONLY_SETUP_AUTHORITY");
        address subjectSplitter = _requireActiveSubject(registration);
        require(registration.launchToken != address(0), "TOKEN_ZERO");
        require(registration.quoteToken == canonicalQuoteToken, "QUOTE_TOKEN_NOT_CANONICAL");
        require(registration.poolFee <= 1_000_000, "POOL_FEE_INVALID");
        require(registration.tickSpacing > 0, "TICK_SPACING_INVALID");
        require(registration.poolManager != address(0), "POOL_MANAGER_ZERO");
        require(registration.hook != address(0), "HOOK_ZERO");
        require(registration.authorizedInitializer != address(0), "INITIALIZER_ZERO");

        (Currency currency0, Currency currency1) =
            _sortCurrencies(registration.launchToken, registration.quoteToken);
        poolId = PoolId.unwrap(
            PoolKey({
                    currency0: currency0,
                    currency1: currency1,
                    fee: registration.poolFee,
                    tickSpacing: registration.tickSpacing,
                    hooks: IHooks(registration.hook)
                }).toId()
        );
        require(poolConfigs[poolId].launchToken == address(0), "POOL_ALREADY_REGISTERED");

        poolConfigs[poolId] = PoolConfig({
            launchToken: registration.launchToken,
            quoteToken: registration.quoteToken,
            currency0: Currency.unwrap(currency0),
            currency1: Currency.unwrap(currency1),
            poolFee: registration.poolFee,
            tickSpacing: registration.tickSpacing,
            poolManager: registration.poolManager,
            hook: registration.hook,
            authorizedInitializer: registration.authorizedInitializer,
            hookEnabled: true
        });
        setupAuthority = address(0);

        emit PoolRegistered(
            poolId,
            registration.launchToken,
            registration.quoteToken,
            subjectSplitter,
            registration.poolManager,
            registration.hook,
            registration.authorizedInitializer
        );
    }

    function setHookEnabled(bytes32 poolId, bool enabled) external {
        require(msg.sender == agentSafe, "ONLY_AGENT_SAFE");
        PoolConfig storage config = poolConfigs[poolId];
        require(config.launchToken != address(0), "POOL_NOT_REGISTERED");
        if (enabled) requireActiveFeeInfrastructure(address(0), config.hook);
        config.hookEnabled = enabled;
        emit HookStatusSet(poolId, enabled);
    }

    function requireActiveFeeInfrastructure(address vault, address hook) public view {
        ISubjectRegistry.SubjectConfig memory subject = _requireActiveFeeSubject();
        if (vault != address(0)) require(subject.feeVault == vault, "FEE_VAULT_MISMATCH");
        require(subject.feeHook == hook, "FEE_HOOK_MISMATCH");
    }

    function requireSubjectStakingBinding() external view {
        ISubjectRegistry.SubjectConfig memory subject = _requireActiveFeeSubject();
        _requireSplitterBinding(subject);
    }

    function getPoolConfig(bytes32 poolId) external view returns (PoolConfig memory) {
        return _poolOrRevert(poolId);
    }

    function isRegisteredPool(bytes32 poolId) external view returns (bool) {
        return poolConfigs[poolId].launchToken != address(0);
    }

    function subjectStakingRecipient(bytes32 poolId) external view returns (address recipient) {
        PoolConfig memory config = _poolOrRevert(poolId);
        ISubjectRegistry.SubjectConfig memory subject = _requireFeeSubject();
        require(subject.lifecycle != ISubjectRegistry.Lifecycle.Retired, "SUBJECT_RETIRED");
        require(subject.stakeToken == config.launchToken, "SUBJECT_TOKEN_MISMATCH");
        _requireSplitterBinding(subject);
        recipient = subject.splitter;
    }

    function regentRecipient(bytes32 poolId) external view returns (address) {
        _poolOrRevert(poolId);
        return REGENT_REVENUE_STAKING;
    }

    function quoteToken(bytes32 poolId) external view returns (address) {
        return _poolOrRevert(poolId).quoteToken;
    }

    function poolAuthorizedInitializer(bytes32 poolId) external view returns (address) {
        return _poolOrRevert(poolId).authorizedInitializer;
    }

    function computePoolId(
        address launchToken,
        address quoteToken_,
        uint24 poolFee,
        int24 tickSpacing,
        address hook
    ) external pure returns (bytes32) {
        (Currency currency0, Currency currency1) = _sortCurrencies(launchToken, quoteToken_);
        return PoolId.unwrap(
            PoolKey({
                    currency0: currency0,
                    currency1: currency1,
                    fee: poolFee,
                    tickSpacing: tickSpacing,
                    hooks: IHooks(hook)
                }).toId()
        );
    }

    function _requireActiveSubject(PoolRegistration memory registration)
        internal
        view
        returns (address splitter)
    {
        ISubjectRegistry.SubjectConfig memory subject = subjectRegistry.getSubject(subjectId);
        require(subject.lifecycle == ISubjectRegistry.Lifecycle.Active, "SUBJECT_NOT_ACTIVE");
        require(subject.stakeToken == registration.launchToken, "SUBJECT_TOKEN_MISMATCH");
        require(subject.treasurySafe == agentSafe, "AGENT_SAFE_MISMATCH");
        require(subject.strategy == registration.authorizedInitializer, "STRATEGY_MISMATCH");
        require(subject.launchFeeRegistry == address(this), "FEE_REGISTRY_MISMATCH");
        require(subject.feeHook == registration.hook, "FEE_HOOK_MISMATCH");
        require(subject.splitter != address(0), "SUBJECT_SPLITTER_ZERO");
        splitter = subject.splitter;
    }

    function _requireActiveFeeSubject()
        internal
        view
        returns (ISubjectRegistry.SubjectConfig memory subject)
    {
        subject = _requireFeeSubject();
        require(subject.lifecycle == ISubjectRegistry.Lifecycle.Active, "SUBJECT_NOT_ACTIVE");
    }

    function _requireFeeSubject()
        internal
        view
        returns (ISubjectRegistry.SubjectConfig memory subject)
    {
        subject = subjectRegistry.getSubject(subjectId);
        require(subject.treasurySafe == agentSafe, "AGENT_SAFE_MISMATCH");
        require(subject.launchFeeRegistry == address(this), "FEE_REGISTRY_MISMATCH");
    }

    function _requireSplitterBinding(ISubjectRegistry.SubjectConfig memory subject) internal view {
        require(subject.splitter != address(0), "SUBJECT_SPLITTER_ZERO");
        ISubjectSplitterBinding splitter = ISubjectSplitterBinding(subject.splitter);
        require(splitter.subjectId() == subjectId, "SPLITTER_SUBJECT_MISMATCH");
        require(splitter.stakeToken() == subject.stakeToken, "SPLITTER_TOKEN_MISMATCH");
        require(
            splitter.subjectRegistry() == address(subjectRegistry), "SPLITTER_REGISTRY_MISMATCH"
        );
    }

    function _poolOrRevert(bytes32 poolId) internal view returns (PoolConfig memory config) {
        config = poolConfigs[poolId];
        require(config.launchToken != address(0), "POOL_NOT_REGISTERED");
    }

    function _sortCurrencies(address launchToken, address quoteToken_)
        internal
        pure
        returns (Currency currency0, Currency currency1)
    {
        Currency launchCurrency = Currency.wrap(launchToken);
        Currency quoteCurrency = Currency.wrap(quoteToken_);
        require(!(launchCurrency == quoteCurrency), "POOL_CURRENCIES_EQUAL");
        (currency0, currency1) = launchCurrency < quoteCurrency
            ? (launchCurrency, quoteCurrency)
            : (quoteCurrency, launchCurrency);
    }
}
