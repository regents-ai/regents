// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AuctionParameters} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {
    IDistributionContract
} from "src/autolaunch/cca/interfaces/external/IDistributionContract.sol";
import {Owned} from "src/shared/auth/Owned.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {PaymentLinkFactory} from "src/autolaunch/revenue/PaymentLinkFactory.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {AgentTokenVestingWallet} from "src/autolaunch/AgentTokenVestingWallet.sol";
import {RegentLBPStrategy} from "src/autolaunch/RegentLBPStrategy.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {ITokenFactory} from "src/shared/interfaces/ITokenFactory.sol";
import {IDistributionStrategy} from "src/shared/interfaces/IDistributionStrategy.sol";
import {BaseMainnetChainConfig} from "src/shared/libraries/BaseMainnetChainConfig.sol";
import {InputBounds} from "src/autolaunch/revenue/libraries/InputBounds.sol";

contract LaunchDeploymentController is Owned {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant MPS_TOTAL = 10_000_000;
    uint16 internal constant PUBLIC_SALE_BPS = 1000;
    uint16 internal constant LP_RESERVE_BPS = 500;
    uint16 internal constant VESTING_BPS = 8500;
    uint24 internal constant MAX_POOL_FEE = 1_000_000;

    struct DeploymentAddresses {
        address agentSafe;
        address feeInfraDeployer;
        address revenueShareFactory;
        address revenueIngressFactory;
        address paymentLinkFactory;
        address identityRegistry;
        address tokenFactory;
        address strategyFactory;
        address auctionInitializerFactory;
        address poolManager;
        address positionManager;
        address strategyOperator;
        address auctionQuoteToken;
        address revenueUsdcToken;
        address regentRecipient;
        address validationHook;
    }

    struct DeploymentEconomics {
        uint256 identityAgentId;
        uint256 totalSupply;
        uint24 officialPoolFee;
        int24 officialPoolTickSpacing;
        uint256 auctionTickSpacing;
        uint256 floorPrice;
        uint128 requiredCurrencyRaised;
    }

    struct DeploymentSchedule {
        uint64 startBlock;
        uint64 endBlock;
        uint64 claimBlock;
        uint64 migrationBlock;
        uint64 sweepBlock;
        uint64 vestingStartTimestamp;
        uint64 vestingDurationSeconds;
    }

    struct DeploymentMetadata {
        bytes auctionStepsData;
        string tokenName;
        string tokenSymbol;
        string subjectLabel;
        bytes tokenFactoryData;
        bytes32 tokenFactoryGraffiti;
        bytes32 launchFeeHookSalt;
    }

    struct DeploymentConfig {
        DeploymentAddresses addresses;
        DeploymentEconomics economics;
        DeploymentSchedule schedule;
        DeploymentMetadata metadata;
    }

    struct DeploymentResult {
        address tokenAddress;
        address auctionAddress;
        address strategyAddress;
        address vestingWalletAddress;
        address hookAddress;
        address feeVaultAddress;
        address launchFeeRegistryAddress;
        address subjectRegistryAddress;
        address revenueShareSplitterAddress;
        address defaultIngressAddress;
        bytes32 subjectId;
        bytes32 poolId;
    }

    struct AllocationData {
        uint256 publicSaleAmount;
        uint256 lpReserveAmount;
        uint256 vestingAmount;
        uint256 strategySupply;
        uint24 tokenSplitToAuctionMps;
    }

    struct FeeInfra {
        LaunchFeeRegistry launchFeeRegistry;
        LaunchFeeVault feeVault;
        LaunchPoolFeeHook hook;
    }

    struct RevenueSubject {
        bytes32 subjectId;
        address revenueShareSplitter;
        address defaultIngress;
    }

    struct StagedLaunch {
        bytes32 configHash;
        address tokenAddress;
        address strategyAddress;
        address auctionAddress;
        address vestingWalletAddress;
        address hookAddress;
        address feeVaultAddress;
        address launchFeeRegistryAddress;
        address subjectRegistryAddress;
        address revenueShareSplitterAddress;
        address defaultIngressAddress;
        bytes32 poolId;
        bool feeInfraDeployed;
        bool finalized;
    }

    mapping(bytes32 => StagedLaunch) private stagedLaunches;
    uint256 private _deploymentLock = 1;

    event LaunchStackDeployed(
        address indexed deployer,
        bytes32 indexed subjectId,
        address indexed tokenAddress,
        address auctionAddress,
        address strategyAddress,
        bytes32 poolId,
        address agentSafe
    );
    event LaunchTokenRoles(
        bytes32 indexed subjectId,
        address indexed auctionQuoteToken,
        address indexed revenueUsdcToken
    );
    event StagedLaunchPrepared(
        bytes32 indexed launchId,
        address indexed tokenAddress,
        address indexed vestingWalletAddress,
        address revenueShareSplitterAddress,
        address defaultIngressAddress
    );
    event StagedLaunchFeeInfraDeployed(
        bytes32 indexed launchId,
        address indexed hookAddress,
        address indexed feeVaultAddress,
        address launchFeeRegistryAddress
    );

    constructor() Owned(msg.sender) {}

    modifier nonReentrantDeployment() {
        require(_deploymentLock == 1, "REENTRANT");
        _deploymentLock = 2;
        _;
        _deploymentLock = 1;
    }

    // Reviewed in slither.db.json: owner-only orchestration across bound factories.
    // slither-disable-next-line reentrancy-events,reentrancy-no-eth
    function deploy(
        bytes calldata addressesData,
        bytes calldata economicsData,
        bytes calldata scheduleData,
        bytes calldata metadataData
    ) external nonReentrantDeployment onlyOwner returns (bytes32 launchId) {
        DeploymentConfig memory cfg =
            _decodeConfig(addressesData, economicsData, scheduleData, metadataData);
        launchId = _prepareLaunch(cfg);
        _deployLaunchFeeInfra(launchId, cfg);
        _finalizeLaunch(launchId, cfg);
    }

    function prepareLaunch(
        bytes calldata addressesData,
        bytes calldata economicsData,
        bytes calldata scheduleData,
        bytes calldata metadataData
    ) external nonReentrantDeployment onlyOwner returns (bytes32 launchId) {
        DeploymentConfig memory cfg =
            _decodeConfig(addressesData, economicsData, scheduleData, metadataData);
        return _prepareLaunch(cfg);
    }

    // Reviewed in slither.db.json: publication follows calls to bound deployment factories.
    // slither-disable-next-line reentrancy-benign,reentrancy-events,reentrancy-no-eth
    function _prepareLaunch(DeploymentConfig memory cfg) internal returns (bytes32 launchId) {
        _validateConfig(cfg);
        _allocationData(cfg.economics.totalSupply);
        SubjectRegistry subjectRegistry =
            _subjectRegistryOrRevert(cfg.addresses.revenueShareFactory);

        address token = _createToken(cfg);
        launchId = keccak256(abi.encode(block.chainid, token));
        StagedLaunch storage launch = stagedLaunches[launchId];
        require(launch.configHash == bytes32(0), "LAUNCH_EXISTS");

        launch.configHash = _configHash(cfg);
        launch.tokenAddress = token;
        launch.subjectRegistryAddress = address(subjectRegistry);

        AgentTokenVestingWallet vestingWallet = _createVestingWallet(cfg, token);
        RevenueSubject memory revenueSubject = _createRevenueSubject(cfg, token);
        require(revenueSubject.subjectId == launchId, "SUBJECT_ID_MISMATCH");

        launch.vestingWalletAddress = address(vestingWallet);
        launch.revenueShareSplitterAddress = revenueSubject.revenueShareSplitter;
        launch.defaultIngressAddress = revenueSubject.defaultIngress;

        emit StagedLaunchPrepared(
            launchId,
            token,
            address(vestingWallet),
            revenueSubject.revenueShareSplitter,
            revenueSubject.defaultIngress
        );
    }

    function deployLaunchFeeInfra(
        bytes32 launchId,
        bytes calldata addressesData,
        bytes calldata economicsData,
        bytes calldata scheduleData,
        bytes calldata metadataData
    ) external nonReentrantDeployment onlyOwner {
        DeploymentConfig memory cfg = _decodeConfig(
            addressesData, economicsData, scheduleData, metadataData
        );
        _deployLaunchFeeInfra(launchId, cfg);
    }

    // Reviewed in slither.db.json: this event records completed bound-factory deployment.
    // slither-disable-next-line reentrancy-events
    function _deployLaunchFeeInfra(bytes32 launchId, DeploymentConfig memory cfg) internal {
        StagedLaunch storage launch = _stagedLaunchOrRevert(launchId, cfg);
        require(!launch.feeInfraDeployed, "FEE_INFRA_ALREADY_DEPLOYED");

        FeeInfra memory feeInfra = _deployFeeInfra(cfg);

        launch.launchFeeRegistryAddress = address(feeInfra.launchFeeRegistry);
        launch.feeVaultAddress = address(feeInfra.feeVault);
        launch.hookAddress = address(feeInfra.hook);
        launch.feeInfraDeployed = true;

        emit StagedLaunchFeeInfraDeployed(
            launchId,
            address(feeInfra.hook),
            address(feeInfra.feeVault),
            address(feeInfra.launchFeeRegistry)
        );
    }

    function finalizeLaunch(
        bytes32 launchId,
        bytes calldata addressesData,
        bytes calldata economicsData,
        bytes calldata scheduleData,
        bytes calldata metadataData
    ) external nonReentrantDeployment onlyOwner {
        DeploymentConfig memory cfg = _decodeConfig(
            addressesData, economicsData, scheduleData, metadataData
        );
        _finalizeLaunch(launchId, cfg);
    }

    // Reviewed in slither.db.json: terminal events follow atomic launch finalization.
    // slither-disable-next-line reentrancy-events
    function _finalizeLaunch(bytes32 launchId, DeploymentConfig memory cfg) internal {
        StagedLaunch storage launch = _stagedLaunchOrRevert(launchId, cfg);
        require(launch.feeInfraDeployed, "FEE_INFRA_NOT_DEPLOYED");
        require(!launch.finalized, "LAUNCH_FINALIZED");

        AllocationData memory allocation = _allocationData(cfg.economics.totalSupply);
        IDistributionContract strategy = _initializeStrategy(
            cfg,
            launch.tokenAddress,
            launch.subjectRegistryAddress,
            AgentTokenVestingWallet(launch.vestingWalletAddress),
            LaunchPoolFeeHook(launch.hookAddress),
            allocation
        );

        AgentTokenVestingWallet(launch.vestingWalletAddress).bindStrategy(address(strategy));

        _registerSubject(launchId, cfg, launch, address(strategy));
        address ingress = RevenueIngressFactory(cfg.addresses.revenueIngressFactory)
            .createDefaultIngressAccount(launchId, "default-usdc-ingress");
        require(ingress == launch.defaultIngressAddress, "DEFAULT_INGRESS_ADDRESS_MISMATCH");

        require(
            IERC20Like(launch.tokenAddress).transfer(address(strategy), allocation.strategySupply),
            "STRATEGY_TRANSFER_FAILED"
        );
        require(
            IERC20Like(launch.tokenAddress)
                .transfer(launch.vestingWalletAddress, allocation.vestingAmount),
            "VESTING_TRANSFER_FAILED"
        );
        strategy.onTokensReceived();
        require(
            RegentLBPStrategy(address(strategy)).auctionAddress() != address(0),
            "AUCTION_NOT_CREATED"
        );

        LaunchFeeRegistry launchFeeRegistry = LaunchFeeRegistry(launch.launchFeeRegistryAddress);
        LaunchFeeVault feeVault = LaunchFeeVault(payable(launch.feeVaultAddress));
        LaunchPoolFeeHook hook = LaunchPoolFeeHook(launch.hookAddress);

        bytes32 poolId = launchFeeRegistry.registerPool(
            LaunchFeeRegistry.PoolRegistration({
                launchToken: launch.tokenAddress,
                quoteToken: cfg.addresses.auctionQuoteToken,
                treasury: cfg.addresses.agentSafe,
                regentRecipient: cfg.addresses.regentRecipient,
                poolFee: cfg.economics.officialPoolFee,
                tickSpacing: cfg.economics.officialPoolTickSpacing,
                poolManager: cfg.addresses.poolManager,
                hook: address(hook),
                authorizedInitializer: address(strategy)
            })
        );
        feeVault.setCanonicalTokens(launch.tokenAddress, cfg.addresses.auctionQuoteToken);

        launchFeeRegistry.transferOwnership(cfg.addresses.agentSafe);
        feeVault.transferOwnership(cfg.addresses.agentSafe);
        hook.transferOwnership(cfg.addresses.agentSafe);

        launch.strategyAddress = address(strategy);
        launch.auctionAddress = RegentLBPStrategy(address(strategy)).auctionAddress();
        launch.poolId = poolId;
        launch.finalized = true;

        _emitLaunchStackDeployed(launchId, launch, cfg.addresses.agentSafe);
        _emitLaunchTokenRoles(launchId, cfg);
    }

    function _registerSubject(
        bytes32 launchId,
        DeploymentConfig memory cfg,
        StagedLaunch storage launch,
        address strategy
    ) internal {
        ISubjectRegistry.SubjectRegistration memory registration =
            ISubjectRegistry.SubjectRegistration({
                subjectId: launchId,
                stakeToken: launch.tokenAddress,
                splitter: launch.revenueShareSplitterAddress,
                agentSafe: cfg.addresses.agentSafe,
                ingress: launch.defaultIngressAddress,
                paymentLinkFactory: cfg.addresses.paymentLinkFactory,
                strategy: strategy,
                launchFeeRegistry: launch.launchFeeRegistryAddress,
                feeVault: launch.feeVaultAddress,
                feeHook: launch.hookAddress,
                identityChainId: cfg.addresses.identityRegistry == address(0) ? 0 : block.chainid,
                identityRegistry: cfg.addresses.identityRegistry,
                identityAgentId: cfg.economics.identityAgentId,
                label: cfg.metadata.subjectLabel,
                safeRuntime: cfg.addresses.strategyOperator
            });
        SubjectRegistry(launch.subjectRegistryAddress).registerSubject(registration);
    }

    function stagedLaunchCore(bytes32 launchId)
        external
        view
        returns (
            address tokenAddress,
            address auctionAddress,
            address strategyAddress,
            address vestingWalletAddress
        )
    {
        StagedLaunch storage launch = _stagedLaunchById(launchId);
        return (
            launch.tokenAddress,
            launch.auctionAddress,
            launch.strategyAddress,
            launch.vestingWalletAddress
        );
    }

    function stagedLaunchInfra(bytes32 launchId)
        external
        view
        returns (
            address hookAddress,
            address feeVaultAddress,
            address launchFeeRegistryAddress,
            bytes32 poolId
        )
    {
        StagedLaunch storage launch = _stagedLaunchById(launchId);
        return (
            launch.hookAddress,
            launch.feeVaultAddress,
            launch.launchFeeRegistryAddress,
            launch.poolId
        );
    }

    function stagedLaunchRevenue(bytes32 launchId)
        external
        view
        returns (
            address subjectRegistryAddress,
            address revenueShareSplitterAddress,
            address defaultIngressAddress,
            bool feeInfraDeployed,
            bool finalized
        )
    {
        StagedLaunch storage launch = _stagedLaunchById(launchId);
        return (
            launch.subjectRegistryAddress,
            launch.revenueShareSplitterAddress,
            launch.defaultIngressAddress,
            launch.feeInfraDeployed,
            launch.finalized
        );
    }

    function _decodeConfig(
        bytes calldata addressesData,
        bytes calldata economicsData,
        bytes calldata scheduleData,
        bytes calldata metadataData
    ) internal pure returns (DeploymentConfig memory cfg) {
        cfg.addresses = abi.decode(addressesData, (DeploymentAddresses));
        cfg.economics = abi.decode(economicsData, (DeploymentEconomics));
        cfg.schedule = abi.decode(scheduleData, (DeploymentSchedule));
        cfg.metadata = abi.decode(metadataData, (DeploymentMetadata));
    }

    function _validateConfig(DeploymentConfig memory cfg) internal view {
        _validateAddresses(cfg.addresses);
        _validateIdentity(cfg.addresses.identityRegistry, cfg.economics.identityAgentId);
        _validateEconomics(cfg.economics);
        _validateSchedule(cfg.schedule);
        _validateMetadata(cfg.metadata, cfg.schedule.endBlock - cfg.schedule.startBlock);
        _validateRevenueFactories(cfg.addresses);
        require(
            PUBLIC_SALE_BPS + LP_RESERVE_BPS + VESTING_BPS == BPS_DENOMINATOR,
            "ALLOCATION_BPS_INVALID"
        );
    }

    function _validateAddresses(DeploymentAddresses memory addresses) internal view {
        require(addresses.agentSafe != address(0), "AGENT_SAFE_ZERO");
        require(addresses.feeInfraDeployer != address(0), "FEE_INFRA_DEPLOYER_ZERO");
        require(addresses.revenueShareFactory != address(0), "REVENUE_SHARE_FACTORY_ZERO");
        require(addresses.revenueIngressFactory != address(0), "REVENUE_INGRESS_FACTORY_ZERO");
        require(addresses.paymentLinkFactory != address(0), "PAYMENT_LINK_FACTORY_ZERO");
        require(addresses.tokenFactory != address(0), "TOKEN_FACTORY_ZERO");
        require(addresses.strategyFactory != address(0), "STRATEGY_FACTORY_ZERO");
        require(addresses.auctionInitializerFactory != address(0), "AUCTION_FACTORY_ZERO");
        require(addresses.poolManager != address(0), "POOL_MANAGER_ZERO");
        require(addresses.positionManager != address(0), "POSITION_MANAGER_ZERO");
        require(addresses.strategyOperator != address(0), "STRATEGY_OPERATOR_ZERO");
        require(addresses.auctionQuoteToken != address(0), "QUOTE_TOKEN_ZERO");
        require(addresses.revenueUsdcToken != address(0), "REVENUE_USDC_ZERO");
        BaseMainnetChainConfig.requireRegent(addresses.auctionQuoteToken);
        BaseMainnetChainConfig.requireUsdc(addresses.revenueUsdcToken);
        BaseMainnetChainConfig.requirePoolManager(addresses.poolManager);
        BaseMainnetChainConfig.requirePositionManager(addresses.positionManager);
        require(addresses.auctionQuoteToken.code.length != 0, "QUOTE_TOKEN_NO_CODE");
        require(
            IERC20MetadataLike(addresses.auctionQuoteToken).decimals() == 18, "QUOTE_TOKEN_DECIMALS"
        );
        require(addresses.regentRecipient != address(0), "REGENT_RECIPIENT_ZERO");
    }

    function _validateIdentity(address identityRegistry, uint256 identityAgentId) internal pure {
        bool hasIdentityLink = identityRegistry != address(0) || identityAgentId != 0;
        if (hasIdentityLink) {
            require(identityRegistry != address(0), "IDENTITY_REGISTRY_ZERO");
            require(identityAgentId != 0, "AGENT_ID_ZERO");
        }
    }

    function _validateEconomics(DeploymentEconomics memory economics) internal pure {
        require(economics.totalSupply != 0, "SUPPLY_ZERO");
        require(economics.officialPoolTickSpacing > 0, "POOL_TICK_SPACING_INVALID");
        require(economics.officialPoolFee <= MAX_POOL_FEE, "POOL_FEE_INVALID");
        require(economics.floorPrice > 0, "FLOOR_PRICE_ZERO");
        require(economics.auctionTickSpacing > 0, "AUCTION_TICK_SPACING_ZERO");
        require(
            economics.floorPrice % economics.auctionTickSpacing == 0, "FLOOR_PRICE_TICK_MISALIGNED"
        );
        require(
            economics.auctionTickSpacing >= economics.floorPrice / 10_000,
            "AUCTION_TICK_SPACING_TOO_SMALL"
        );
    }

    function _validateSchedule(DeploymentSchedule memory schedule) internal pure {
        require(schedule.startBlock < schedule.endBlock, "START_BLOCK_INVALID");
        require(schedule.claimBlock >= schedule.endBlock, "CLAIM_BEFORE_END");
        require(schedule.migrationBlock > schedule.endBlock, "MIGRATION_BEFORE_END");
        require(schedule.sweepBlock > schedule.migrationBlock, "SWEEP_BEFORE_MIGRATION");
        require(schedule.vestingDurationSeconds != 0, "VESTING_DURATION_ZERO");
    }

    function _validateMetadata(DeploymentMetadata memory metadata, uint256 durationBlocks)
        internal
        pure
    {
        _validateAuctionStepsData(metadata.auctionStepsData, durationBlocks);
        InputBounds.requireNonEmptyString(
            metadata.tokenName, InputBounds.MAX_TOKEN_NAME_BYTES, "NAME_EMPTY", "NAME_TOO_LONG"
        );
        InputBounds.requireNonEmptyString(
            metadata.tokenSymbol,
            InputBounds.MAX_TOKEN_SYMBOL_BYTES,
            "SYMBOL_EMPTY",
            "SYMBOL_TOO_LONG"
        );
        InputBounds.requireNonEmptyString(
            metadata.subjectLabel,
            InputBounds.MAX_LABEL_BYTES,
            "SUBJECT_LABEL_EMPTY",
            "SUBJECT_LABEL_TOO_LONG"
        );
        InputBounds.requireBytesMax(
            metadata.tokenFactoryData,
            InputBounds.MAX_TOKEN_FACTORY_DATA_BYTES,
            "TOKEN_FACTORY_DATA_TOO_LONG"
        );
    }

    function _validateRevenueFactories(DeploymentAddresses memory addresses) internal view {
        require(
            RevenueShareFactory(addresses.revenueShareFactory).usdc() == addresses.revenueUsdcToken,
            "REVENUE_SHARE_USDC_MISMATCH"
        );
        require(
            RevenueIngressFactory(addresses.revenueIngressFactory).usdc()
                == addresses.revenueUsdcToken,
            "REVENUE_INGRESS_USDC_MISMATCH"
        );
        require(
            PaymentLinkFactory(addresses.paymentLinkFactory).usdc() == addresses.revenueUsdcToken,
            "PAYMENT_LINK_USDC_MISMATCH"
        );
        address registry =
            address(RevenueShareFactory(addresses.revenueShareFactory).subjectRegistry());
        require(
            RevenueIngressFactory(addresses.revenueIngressFactory).subjectRegistry() == registry,
            "REVENUE_INGRESS_REGISTRY_MISMATCH"
        );
        require(
            PaymentLinkFactory(addresses.paymentLinkFactory).subjectRegistry() == registry,
            "PAYMENT_LINK_REGISTRY_MISMATCH"
        );
        require(
            RevenueShareFactory(addresses.revenueShareFactory).controller() == address(this),
            "REVENUE_SHARE_CONTROLLER_MISMATCH"
        );
        require(
            RevenueIngressFactory(addresses.revenueIngressFactory).controller() == address(this),
            "REVENUE_INGRESS_CONTROLLER_MISMATCH"
        );
        require(
            PaymentLinkFactory(addresses.paymentLinkFactory).controller() == address(this),
            "PAYMENT_LINK_CONTROLLER_MISMATCH"
        );
    }

    function _allocationData(uint256 totalSupply)
        internal
        pure
        returns (AllocationData memory data)
    {
        data.publicSaleAmount =
            (totalSupply * PUBLIC_SALE_BPS) / BPS_DENOMINATOR;
        data.lpReserveAmount = (totalSupply * LP_RESERVE_BPS) / BPS_DENOMINATOR;
        data.vestingAmount = totalSupply - data.publicSaleAmount - data.lpReserveAmount;
        data.strategySupply = data.publicSaleAmount + data.lpReserveAmount;

        require(data.publicSaleAmount != 0, "PUBLIC_SALE_ZERO");
        require(data.lpReserveAmount != 0, "LP_RESERVE_ZERO");
        require(data.vestingAmount != 0, "VESTING_ZERO");
        require(data.strategySupply <= type(uint128).max, "STRATEGY_SUPPLY_OVERFLOW");
        require(data.publicSaleAmount <= type(uint128).max, "PUBLIC_SALE_OVERFLOW");
        require(data.lpReserveAmount <= type(uint128).max, "LP_RESERVE_OVERFLOW");

        uint256 tokenSplitToAuctionMpsRaw =
            (totalSupply * PUBLIC_SALE_BPS * MPS_TOTAL) / (BPS_DENOMINATOR * data.strategySupply);
        require(tokenSplitToAuctionMpsRaw <= type(uint24).max, "TOKEN_SPLIT_OVERFLOW");
        data.tokenSplitToAuctionMps = _toUint24(tokenSplitToAuctionMpsRaw);
        require(data.tokenSplitToAuctionMps != 0, "TOKEN_SPLIT_ZERO");
        require(data.tokenSplitToAuctionMps <= MPS_TOTAL, "TOKEN_SPLIT_INVALID");
    }

    function _subjectRegistryOrRevert(address revenueShareFactory)
        internal
        view
        returns (SubjectRegistry subjectRegistry)
    {
        subjectRegistry = RevenueShareFactory(revenueShareFactory).subjectRegistry();
        require(
            subjectRegistry.controller() == address(this), "SUBJECT_REGISTRY_CONTROLLER_MISMATCH"
        );
    }

    function _createToken(DeploymentConfig memory cfg) internal returns (address token) {
        token = ITokenFactory(cfg.addresses.tokenFactory)
            .createToken(
                cfg.metadata.tokenName,
                cfg.metadata.tokenSymbol,
                18,
                cfg.economics.totalSupply,
                address(this),
                cfg.metadata.tokenFactoryData,
                cfg.metadata.tokenFactoryGraffiti
            );
        require(token != address(0), "TOKEN_NOT_CREATED");
    }

    function _createVestingWallet(DeploymentConfig memory cfg, address token)
        internal
        returns (AgentTokenVestingWallet vestingWallet)
    {
        vestingWallet = new AgentTokenVestingWallet(
            cfg.addresses.agentSafe,
            cfg.schedule.vestingStartTimestamp,
            cfg.schedule.vestingDurationSeconds,
            token
        );
    }

    function _deployFeeInfra(DeploymentConfig memory cfg)
        internal
        returns (FeeInfra memory feeInfra)
    {
        (feeInfra.launchFeeRegistry, feeInfra.feeVault, feeInfra.hook) = LaunchFeeInfraDeployer(
                cfg.addresses.feeInfraDeployer
            )
            .deploy(
                address(this),
                cfg.addresses.poolManager,
                cfg.addresses.auctionQuoteToken,
                cfg.metadata.launchFeeHookSalt
            );

        feeInfra.launchFeeRegistry.acceptOwnership();
        feeInfra.feeVault.acceptOwnership();
        feeInfra.hook.acceptOwnership();
    }

    function _createRevenueSubject(DeploymentConfig memory cfg, address token)
        internal
        returns (RevenueSubject memory revenueSubject)
    {
        revenueSubject.subjectId = keccak256(abi.encode(block.chainid, token));
        uint256 identityChainId = cfg.addresses.identityRegistry == address(0)
            && cfg.economics.identityAgentId == 0
            ? 0
            : block.chainid;
        revenueSubject.revenueShareSplitter = RevenueShareFactory(cfg.addresses.revenueShareFactory)
            .createSubjectSplitter(
                revenueSubject.subjectId,
                token,
                cfg.addresses.revenueIngressFactory,
                cfg.addresses.agentSafe,
                RevenueShareFactory(cfg.addresses.revenueShareFactory).stakingRevenueRouter(),
                cfg.economics.totalSupply,
                cfg.metadata.subjectLabel,
                identityChainId,
                cfg.addresses.identityRegistry,
                cfg.economics.identityAgentId
            );

        revenueSubject.defaultIngress = RevenueIngressFactory(cfg.addresses.revenueIngressFactory)
            .predictDefaultIngress(revenueSubject.subjectId, cfg.addresses.agentSafe);
        require(revenueSubject.defaultIngress != address(0), "DEFAULT_INGRESS_NOT_PREDICTED");
    }

    function _initializeStrategy(
        DeploymentConfig memory cfg,
        address token,
        address subjectRegistry,
        AgentTokenVestingWallet vestingWallet,
        LaunchPoolFeeHook hook,
        AllocationData memory allocation
    ) internal returns (IDistributionContract strategy) {
        RegentLBPStrategyFactory.RegentLBPStrategyConfig memory
            strategyCfg = _strategyConfig(cfg, subjectRegistry, vestingWallet, hook, allocation);

        strategy = IDistributionStrategy(cfg.addresses.strategyFactory)
            .initializeDistribution(
                token, allocation.strategySupply, abi.encode(strategyCfg), bytes32(0)
            );
    }

    function _strategyConfig(
        DeploymentConfig memory cfg,
        address subjectRegistry,
        AgentTokenVestingWallet vestingWallet,
        LaunchPoolFeeHook hook,
        AllocationData memory allocation
    ) internal pure returns (RegentLBPStrategyFactory.RegentLBPStrategyConfig memory strategyCfg) {
        strategyCfg.quoteToken = cfg.addresses.auctionQuoteToken;
        strategyCfg.auctionInitializerFactory = cfg.addresses.auctionInitializerFactory;
        strategyCfg.auctionParameters = _auctionParameters(cfg);
        strategyCfg.officialPoolHook = address(hook);
        strategyCfg.agentSafe = cfg.addresses.agentSafe;
        strategyCfg.vestingWallet = address(vestingWallet);
        strategyCfg.operator = cfg.addresses.strategyOperator;
        strategyCfg.positionManager = cfg.addresses.positionManager;
        strategyCfg.poolManager = cfg.addresses.poolManager;
        strategyCfg.subjectRegistry = subjectRegistry;
        strategyCfg.officialPoolFee = cfg.economics.officialPoolFee;
        strategyCfg.officialPoolTickSpacing = cfg.economics.officialPoolTickSpacing;
        strategyCfg.migrationBlock = cfg.schedule.migrationBlock;
        strategyCfg.sweepBlock = cfg.schedule.sweepBlock;
        strategyCfg.tokenSplitToAuctionMps = allocation.tokenSplitToAuctionMps;
        strategyCfg.auctionTokenAmount = uint128(allocation.publicSaleAmount);
        strategyCfg.reserveTokenAmount = uint128(allocation.lpReserveAmount);
    }

    function _auctionParameters(DeploymentConfig memory cfg)
        internal
        pure
        returns (AuctionParameters memory)
    {
        return AuctionParameters({
            currency: cfg.addresses.auctionQuoteToken,
            tokensRecipient: address(0),
            fundsRecipient: address(0),
            startBlock: cfg.schedule.startBlock,
            endBlock: cfg.schedule.endBlock,
            claimBlock: cfg.schedule.claimBlock,
            tickSpacing: cfg.economics.auctionTickSpacing,
            validationHook: cfg.addresses.validationHook,
            floorPrice: cfg.economics.floorPrice,
            requiredCurrencyRaised: cfg.economics.requiredCurrencyRaised,
            auctionStepsData: cfg.metadata.auctionStepsData
        });
    }

    // Reviewed in slither.db.json: bounded assembly reads fixed-width packed schedule entries.
    // slither-disable-next-line assembly
    function _validateAuctionStepsData(bytes memory steps, uint256 durationBlocks) internal pure {
        require(steps.length != 0, "AUCTION_STEPS_EMPTY");
        require(steps.length % 8 == 0, "AUCTION_STEPS_LENGTH");

        uint256 totalMps;
        uint256 totalBlocks;

        for (uint256 offset; offset < steps.length; offset += 8) {
            uint256 packed;
            assembly ("memory-safe") {
                packed := shr(192, mload(add(add(steps, 0x20), offset)))
            }

            uint256 stepMps = packed >> 40;
            uint256 blockDelta = packed & type(uint40).max;
            require(blockDelta != 0, "AUCTION_STEP_BLOCKS_ZERO");

            totalMps += stepMps * blockDelta;
            totalBlocks += blockDelta;
        }

        require(totalMps == MPS_TOTAL, "AUCTION_STEPS_MPS");
        require(totalBlocks == durationBlocks, "AUCTION_STEPS_BLOCKS");
    }

    function _stagedLaunchOrRevert(bytes32 launchId, DeploymentConfig memory cfg)
        internal
        view
        returns (StagedLaunch storage launch)
    {
        launch = stagedLaunches[launchId];
        require(launch.configHash != bytes32(0), "LAUNCH_NOT_PREPARED");
        require(launch.configHash == _configHash(cfg), "LAUNCH_CONFIG_CHANGED");
    }

    function _stagedLaunchById(bytes32 launchId)
        internal
        view
        returns (StagedLaunch storage launch)
    {
        launch = stagedLaunches[launchId];
        require(launch.configHash != bytes32(0), "LAUNCH_NOT_PREPARED");
    }

    function _configHash(DeploymentConfig memory cfg) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _addressesHash(cfg.addresses),
                _economicsHash(cfg.economics),
                _scheduleHash(cfg.schedule),
                _metadataHash(cfg.metadata)
            )
        );
    }

    function _addressesHash(DeploymentAddresses memory addresses) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                addresses.agentSafe,
                addresses.feeInfraDeployer,
                addresses.revenueShareFactory,
                addresses.revenueIngressFactory,
                addresses.paymentLinkFactory,
                addresses.identityRegistry,
                addresses.tokenFactory,
                addresses.strategyFactory,
                addresses.auctionInitializerFactory,
                addresses.poolManager,
                addresses.positionManager,
                addresses.strategyOperator,
                addresses.auctionQuoteToken,
                addresses.revenueUsdcToken,
                addresses.regentRecipient,
                addresses.validationHook
            )
        );
    }

    function _economicsHash(DeploymentEconomics memory economics) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                economics.identityAgentId,
                economics.totalSupply,
                economics.officialPoolFee,
                economics.officialPoolTickSpacing,
                economics.auctionTickSpacing,
                economics.floorPrice,
                economics.requiredCurrencyRaised
            )
        );
    }

    function _scheduleHash(DeploymentSchedule memory schedule) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                schedule.startBlock,
                schedule.endBlock,
                schedule.claimBlock,
                schedule.migrationBlock,
                schedule.sweepBlock,
                schedule.vestingStartTimestamp,
                schedule.vestingDurationSeconds
            )
        );
    }

    function _metadataHash(DeploymentMetadata memory metadata) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                metadata.auctionStepsData,
                metadata.tokenName,
                metadata.tokenSymbol,
                metadata.subjectLabel,
                metadata.tokenFactoryData,
                metadata.tokenFactoryGraffiti,
                metadata.launchFeeHookSalt
            )
        );
    }

    function _emitLaunchStackDeployed(
        bytes32 launchId,
        StagedLaunch storage launch,
        address agentSafe
    ) internal {
        emit LaunchStackDeployed(
            msg.sender,
            launchId,
            launch.tokenAddress,
            launch.auctionAddress,
            launch.strategyAddress,
            launch.poolId,
            agentSafe
        );
    }

    function _emitLaunchTokenRoles(bytes32 subjectId, DeploymentConfig memory cfg) internal {
        emit LaunchTokenRoles(
            subjectId, cfg.addresses.auctionQuoteToken, cfg.addresses.revenueUsdcToken
        );
    }

    function _toUint24(uint256 value) internal pure returns (uint24) {
        require(value <= type(uint24).max, "UINT24_OVERFLOW");
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint24(value);
    }
}

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC20MetadataLike {
    function decimals() external view returns (uint8);
}
