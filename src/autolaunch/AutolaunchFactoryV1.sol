// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UERC20Metadata} from "@uniswap/uerc20-factory/src/libraries/UERC20MetadataLibrary.sol";
import {AuctionParameters} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {
    IDistributionContract
} from "src/autolaunch/cca/interfaces/external/IDistributionContract.sol";
import {AgentTokenVestingWallet} from "src/autolaunch/AgentTokenVestingWallet.sol";
import {IAutolaunchFactoryV1} from "src/autolaunch/interfaces/IAutolaunchFactoryV1.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {RegentLBPStrategy} from "src/autolaunch/RegentLBPStrategy.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {PaymentLinkFactory} from "src/autolaunch/revenue/PaymentLinkFactory.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {IOwned} from "src/autolaunch/revenue/interfaces/IOwned.sol";
import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {IDistributionStrategy} from "src/shared/interfaces/IDistributionStrategy.sol";
import {ITokenFactory} from "src/shared/interfaces/ITokenFactory.sol";
import {BaseMainnetChainConfig} from "src/shared/libraries/BaseMainnetChainConfig.sol";

contract AutolaunchFactoryV1 is IAutolaunchFactoryV1 {
    uint256 internal constant TOTAL_SUPPLY = 100_000_000_000e18;
    uint256 internal constant AUCTION_AMOUNT = 10_000_000_000e18;
    uint256 internal constant RESERVE_AMOUNT = 5_000_000_000e18;
    uint256 internal constant VESTING_AMOUNT = 85_000_000_000e18;
    uint256 internal constant STRATEGY_SUPPLY = AUCTION_AMOUNT + RESERVE_AMOUNT;
    uint24 internal constant TOKEN_SPLIT_TO_AUCTION_MPS = 6_666_666;
    uint256 internal constant AUCTION_TICK_SPACING = 79_228_162_514_264_337_593_543_950;
    uint64 internal constant AUCTION_BLOCKS = 86_401;
    uint64 internal constant CLAIM_DELAY = 64;
    uint64 internal constant MIGRATION_DELAY = 128;
    uint64 internal constant SWEEP_DELAY = 256;
    uint64 internal constant VESTING_DURATION = 365 days;
    uint24 internal constant OFFICIAL_POOL_FEE = 0;
    int24 internal constant OFFICIAL_POOL_TICK_SPACING = 60;
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant CCA_FACTORY = 0x000000001F26a0044BaA66024e7b6599c61963F8;
    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address internal constant LIVE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;

    address private immutable tokenFactory;
    address private immutable strategyFactory;
    address private immutable revenueShareFactory;
    address private immutable revenueIngressFactory;
    address private immutable paymentLinkFactory;
    address private immutable feeInfraDeployer;
    address private immutable identityRegistry;
    address private immutable operationsSafe;
    address private immutable subjectRegistry;
    uint256 private _launchLock = 1;

    struct LaunchStack {
        address agentSafe;
        AgentTokenVestingWallet vesting;
        LaunchFeeRegistry feeRegistry;
        LaunchFeeVault feeVault;
        LaunchPoolFeeHook feeHook;
    }

    constructor(
        address tokenFactory_,
        address strategyFactory_,
        address revenueShareFactory_,
        address revenueIngressFactory_,
        address paymentLinkFactory_,
        address feeInfraDeployer_,
        address identityRegistry_,
        address operationsSafe_
    ) {
        require(tokenFactory_ != address(0), "DEPENDENCY_ZERO");
        require(tokenFactory_.code.length != 0, "DEPENDENCY_NOT_CONTRACT");
        _requireContract(strategyFactory_);
        _requireContract(revenueShareFactory_);
        _requireContract(revenueIngressFactory_);
        _requireContract(paymentLinkFactory_);
        _requireContract(feeInfraDeployer_);
        _requireContract(identityRegistry_);
        _requireContract(operationsSafe_);
        require(identityRegistry_ == IDENTITY_REGISTRY, "IDENTITY_REGISTRY_NOT_CANONICAL");

        SubjectRegistry registry = RevenueShareFactory(revenueShareFactory_).subjectRegistry();
        _requireContract(address(registry));
        require(registry.controller() == address(this), "SUBJECT_REGISTRY_CONTROLLER_MISMATCH");
        require(
            RevenueShareFactory(revenueShareFactory_).controller() == address(this),
            "REVENUE_SHARE_CONTROLLER_MISMATCH"
        );
        require(
            RevenueIngressFactory(revenueIngressFactory_).controller() == address(this),
            "REVENUE_INGRESS_CONTROLLER_MISMATCH"
        );
        require(
            PaymentLinkFactory(paymentLinkFactory_).controller() == address(this),
            "PAYMENT_LINK_CONTROLLER_MISMATCH"
        );
        require(
            RevenueIngressFactory(revenueIngressFactory_).subjectRegistry() == address(registry),
            "REVENUE_INGRESS_REGISTRY_MISMATCH"
        );
        require(
            PaymentLinkFactory(paymentLinkFactory_).subjectRegistry() == address(registry),
            "PAYMENT_LINK_REGISTRY_MISMATCH"
        );

        address stakingRouter = RevenueShareFactory(revenueShareFactory_).stakingRevenueRouter();
        address splitterDeployer = RevenueShareFactory(revenueShareFactory_).splitterDeployer();
        _requireContract(stakingRouter);
        _requireContract(splitterDeployer);
        require(RevenueShareFactory(revenueShareFactory_).usdc() == USDC, "REVENUE_USDC_MISMATCH");
        require(
            RevenueIngressFactory(revenueIngressFactory_).usdc() == USDC, "INGRESS_USDC_MISMATCH"
        );
        require(PaymentLinkFactory(paymentLinkFactory_).usdc() == USDC, "PAYMENT_USDC_MISMATCH");
        require(IRegentStakingRevenueRouter(stakingRouter).usdc() == USDC, "ROUTER_USDC_MISMATCH");
        require(
            IStakingRouterBinding(stakingRouter).subjectRegistry() == address(registry),
            "ROUTER_REGISTRY_MISMATCH"
        );
        require(
            IRegentStakingRevenueRouter(stakingRouter).regentRevenueStaking() == LIVE_STAKING,
            "LIVE_STAKING_MISMATCH"
        );
        require(
            IRegentStakingRevenueRouter(stakingRouter).protocolSkimBps() == 100,
            "PROTOCOL_SKIM_MISMATCH"
        );
        require(
            RegentLBPStrategyFactory(strategyFactory_).authorizedCreators(address(this)),
            "STRATEGY_FACTORY_NOT_AUTHORIZED"
        );
        require(
            LaunchFeeInfraDeployer(feeInfraDeployer_).authorizedController() == address(this),
            "FEE_DEPLOYER_CONTROLLER_MISMATCH"
        );

        require(operationsSafe_ != address(this), "OPERATIONS_SAFE_IS_FACTORY");
        require(operationsSafe_ != address(registry), "OPERATIONS_SAFE_IS_REGISTRY");
        require(operationsSafe_ != registry.governance(), "OPERATIONS_SAFE_IS_GOVERNANCE");
        require(operationsSafe_ != registry.guardian(), "OPERATIONS_SAFE_IS_GUARDIAN");
        address[15] memory dependencies = [
            tokenFactory_,
            strategyFactory_,
            revenueShareFactory_,
            revenueIngressFactory_,
            paymentLinkFactory_,
            feeInfraDeployer_,
            identityRegistry_,
            stakingRouter,
            splitterDeployer,
            USDC,
            REGENT,
            CCA_FACTORY,
            POOL_MANAGER,
            POSITION_MANAGER,
            LIVE_STAKING
        ];
        for (uint256 i; i < dependencies.length; ++i) {
            require(operationsSafe_ != dependencies[i], "OPERATIONS_SAFE_IS_DEPENDENCY");
        }

        tokenFactory = tokenFactory_;
        strategyFactory = strategyFactory_;
        revenueShareFactory = revenueShareFactory_;
        revenueIngressFactory = revenueIngressFactory_;
        paymentLinkFactory = paymentLinkFactory_;
        feeInfraDeployer = feeInfraDeployer_;
        identityRegistry = identityRegistry_;
        operationsSafe = operationsSafe_;
        subjectRegistry = address(registry);
    }

    modifier nonReentrantLaunch() {
        require(_launchLock == 1, "REENTRANT");
        _launchLock = 2;
        _;
        _launchLock = 1;
    }

    // The vesting start is timestamp-bound; direct launch and rollback tests cover every postcheck.
    // The one-slot nonReentrantLaunch guard protects the sole external state-mutating entrypoint;
    // LaunchCreated is success-only and needs complete results, while
    // testReentryAtTokenCreationFullyRollsBack proves callback reentry total rollback.
    // slither-disable-next-line timestamp,reentrancy-events
    function launch(LaunchParams calldata params)
        external
        nonReentrantLaunch
        returns (LaunchResult memory result)
    {
        uint256 entryUsdcBalance = IERC20LaunchAsset(USDC).balanceOf(address(this));
        BaseMainnetChainConfig.requireBaseMainnet();
        _validateLaunch(params);

        LaunchStack memory stack = LaunchStack({
            agentSafe: msg.sender,
            vesting: AgentTokenVestingWallet(address(0)),
            feeRegistry: LaunchFeeRegistry(address(0)),
            feeVault: LaunchFeeVault(payable(address(0))),
            feeHook: LaunchPoolFeeHook(address(0))
        });
        require(stack.agentSafe.code.length != 0, "CALLER_NOT_CONTRACT");
        require(stack.agentSafe != operationsSafe, "OPERATIONS_SAFE_FORBIDDEN");
        require(
            IERC721Identity(identityRegistry).ownerOf(params.agentId) == stack.agentSafe,
            "IDENTITY_NOT_OWNED"
        );

        result.token = _createToken(params, stack.agentSafe);
        result.subjectId = keccak256(abi.encode(block.chainid, result.token));
        stack.vesting = new AgentTokenVestingWallet(
            stack.agentSafe, uint64(block.timestamp), VESTING_DURATION, result.token
        );
        result.vestingWallet = address(stack.vesting);
        result.revenueShare = _createRevenueShare(params, result, stack.agentSafe);
        result.defaultIngress = RevenueIngressFactory(revenueIngressFactory)
            .predictDefaultIngress(result.subjectId, stack.agentSafe);
        require(result.defaultIngress != address(0), "DEFAULT_INGRESS_ZERO");

        (stack.feeRegistry, stack.feeVault, stack.feeHook) = LaunchFeeInfraDeployer(
                feeInfraDeployer
            )
            .deploy(
                stack.agentSafe,
                subjectRegistry,
                result.subjectId,
                POOL_MANAGER,
                REGENT,
                params.launchFeeHookSalt
            );

        result.strategy = _createStrategy(params, result, address(stack.feeHook), stack.agentSafe);
        stack.vesting.bindStrategy(result.strategy);
        _registerSubject(params, result, stack);
        address ingress = RevenueIngressFactory(revenueIngressFactory)
            .createDefaultIngressAccount(result.subjectId, "default-usdc-ingress");
        require(ingress == result.defaultIngress, "DEFAULT_INGRESS_MISMATCH");
        result.canonicalPaymentLink = PaymentLinkFactory(paymentLinkFactory)
            .createCanonicalPaymentLink(result.subjectId, params.tokenName, result.subjectId);
        require(
            result.canonicalPaymentLink != address(0)
                && result.canonicalPaymentLink != result.defaultIngress,
            "CANONICAL_LINK_INVALID"
        );

        require(
            IERC20LaunchAsset(result.token).transfer(result.strategy, STRATEGY_SUPPLY),
            "STRATEGY_TRANSFER_FAILED"
        );
        require(
            IERC20LaunchAsset(result.token).transfer(result.vestingWallet, VESTING_AMOUNT),
            "VESTING_TRANSFER_FAILED"
        );
        IDistributionContract(result.strategy).onTokensReceived();
        result.auction = RegentLBPStrategy(result.strategy).auctionAddress();
        require(result.auction != address(0), "AUCTION_NOT_CREATED");

        result.poolId = stack.feeRegistry
            .registerPool(
                LaunchFeeRegistry.PoolRegistration({
                    launchToken: result.token,
                    quoteToken: REGENT,
                    poolFee: OFFICIAL_POOL_FEE,
                    tickSpacing: OFFICIAL_POOL_TICK_SPACING,
                    poolManager: POOL_MANAGER,
                    hook: address(stack.feeHook),
                    authorizedInitializer: result.strategy
                })
            );
        stack.feeVault.setCanonicalTokens(result.poolId);

        _assertFinalState(result, stack, entryUsdcBalance);
        emit LaunchCreated(
            result.subjectId,
            params.agentId,
            stack.agentSafe,
            result.token,
            result.auction,
            result.strategy,
            result.vestingWallet,
            result.revenueShare,
            result.defaultIngress,
            result.canonicalPaymentLink,
            result.poolId
        );
    }

    // The timestamp check protects the uint64 vesting binding exercised by direct launch tests.
    // slither-disable-next-line timestamp
    function _validateLaunch(LaunchParams calldata params) private view {
        require(params.startBlock >= block.number + 300, "START_BLOCK_TOO_SOON");
        require(params.startBlock <= type(uint64).max - AUCTION_BLOCKS, "END_BLOCK_OVERFLOW");
        uint64 endBlock = params.startBlock + AUCTION_BLOCKS;
        require(endBlock <= type(uint64).max - MIGRATION_DELAY, "MIGRATION_BLOCK_OVERFLOW");
        require(
            endBlock + MIGRATION_DELAY <= type(uint64).max - SWEEP_DELAY, "SWEEP_BLOCK_OVERFLOW"
        );
        require(params.floorPrice != 0, "FLOOR_PRICE_ZERO");
        require(params.floorPrice % AUCTION_TICK_SPACING == 0, "FLOOR_PRICE_TICK_MISALIGNED");
        require(params.requiredRegentRaised != 0, "REQUIRED_REGENT_ZERO");
        require(block.timestamp != 0 && block.timestamp <= type(uint64).max, "TIMESTAMP_OVERFLOW");
        require(bytes(params.tokenName).length != 0, "NAME_EMPTY");
        require(bytes(params.tokenSymbol).length != 0, "SYMBOL_EMPTY");
    }

    function _createToken(LaunchParams calldata params, address agentSafe)
        private
        returns (address token)
    {
        UERC20Metadata memory metadata = UERC20Metadata({description: "", website: "", image: ""});
        token = ITokenFactory(tokenFactory)
            .createToken(
                params.tokenName,
                params.tokenSymbol,
                18,
                TOTAL_SUPPLY,
                address(this),
                abi.encode(metadata),
                keccak256(abi.encode(agentSafe, params.agentId))
            );
        require(token != address(0) && token.code.length != 0, "TOKEN_NOT_CREATED");
    }

    function _createRevenueShare(
        LaunchParams calldata params,
        LaunchResult memory result,
        address agentSafe
    ) private returns (address) {
        RevenueShareFactory factory = RevenueShareFactory(revenueShareFactory);
        return factory.createSubjectSplitter(
            result.subjectId,
            result.token,
            revenueIngressFactory,
            agentSafe,
            factory.stakingRevenueRouter(),
            TOTAL_SUPPLY,
            params.tokenName,
            block.chainid,
            identityRegistry,
            params.agentId
        );
    }

    // Launch timestamp taint reaches strategy creation; exact binding tests cover the postcondition.
    // slither-disable-next-line timestamp
    function _createStrategy(
        LaunchParams calldata params,
        LaunchResult memory result,
        address feeHook,
        address agentSafe
    ) private returns (address strategy) {
        uint64 endBlock = params.startBlock + AUCTION_BLOCKS;
        AuctionParameters memory auctionParameters = AuctionParameters({
            currency: REGENT,
            tokensRecipient: address(0),
            fundsRecipient: address(0),
            startBlock: params.startBlock,
            endBlock: endBlock,
            claimBlock: endBlock + CLAIM_DELAY,
            tickSpacing: AUCTION_TICK_SPACING,
            validationHook: address(0),
            floorPrice: params.floorPrice,
            requiredCurrencyRaised: params.requiredRegentRaised,
            auctionStepsData: _auctionSteps()
        });
        RegentLBPStrategyFactory.RegentLBPStrategyConfig memory cfg =
            RegentLBPStrategyFactory.RegentLBPStrategyConfig({
                quoteToken: REGENT,
                auctionInitializerFactory: CCA_FACTORY,
                auctionParameters: auctionParameters,
                officialPoolHook: feeHook,
                agentSafe: agentSafe,
                vestingWallet: result.vestingWallet,
                operator: operationsSafe,
                positionManager: POSITION_MANAGER,
                poolManager: POOL_MANAGER,
                subjectRegistry: subjectRegistry,
                officialPoolFee: OFFICIAL_POOL_FEE,
                officialPoolTickSpacing: OFFICIAL_POOL_TICK_SPACING,
                migrationBlock: endBlock + MIGRATION_DELAY,
                sweepBlock: endBlock + MIGRATION_DELAY + SWEEP_DELAY,
                tokenSplitToAuctionMps: TOKEN_SPLIT_TO_AUCTION_MPS,
                auctionTokenAmount: uint128(AUCTION_AMOUNT),
                reserveTokenAmount: uint128(RESERVE_AMOUNT)
            });

        strategy = address(
            IDistributionStrategy(strategyFactory)
                .initializeDistribution(result.token, STRATEGY_SUPPLY, abi.encode(cfg), bytes32(0))
        );
        require(strategy != address(0) && strategy.code.length != 0, "STRATEGY_NOT_CREATED");
    }

    function _registerSubject(
        LaunchParams calldata params,
        LaunchResult memory result,
        LaunchStack memory stack
    ) private {
        ISubjectRegistry.SubjectRegistration memory registration =
            ISubjectRegistry.SubjectRegistration({
                subjectId: result.subjectId,
                stakeToken: result.token,
                splitter: result.revenueShare,
                agentSafe: stack.agentSafe,
                ingress: result.defaultIngress,
                paymentLinkFactory: paymentLinkFactory,
                strategy: result.strategy,
                launchFeeRegistry: address(stack.feeRegistry),
                feeVault: address(stack.feeVault),
                feeHook: address(stack.feeHook),
                identityChainId: block.chainid,
                identityRegistry: identityRegistry,
                identityAgentId: params.agentId,
                label: params.tokenName,
                safeRuntime: operationsSafe
            });
        SubjectRegistry(subjectRegistry).registerSubject(registration);
    }

    // Launch timestamp taint reaches these ownership checks; direct launch tests cover them.
    // slither-disable-next-line timestamp
    function _assertFinalState(
        LaunchResult memory result,
        LaunchStack memory stack,
        uint256 entryUsdcBalance
    ) private view {
        require(IOwned(result.revenueShare).owner() == stack.agentSafe, "SPLITTER_OWNER_MISMATCH");
        require(
            IPendingOwned(result.revenueShare).pendingOwner() == address(0),
            "SPLITTER_OWNER_PENDING"
        );
        require(stack.vesting.beneficiary() == stack.agentSafe, "VESTING_BENEFICIARY_MISMATCH");
        require(stack.vesting.strategy() == result.strategy, "VESTING_STRATEGY_MISMATCH");
        require(stack.feeRegistry.setupAuthority() == address(0), "REGISTRY_AUTHORITY_REMAINS");
        require(stack.feeVault.hookSetupAuthority() == address(0), "HOOK_AUTHORITY_REMAINS");
        require(stack.feeVault.tokenSetupAuthority() == address(0), "TOKEN_AUTHORITY_REMAINS");
        // Atomic success and rollback tests require exact token-balance exhaustion.
        // slither-disable-next-line incorrect-equality
        require(
            IERC20LaunchAsset(result.token).balanceOf(address(this)) == 0, "TOKEN_BALANCE_REMAINS"
        );
        // Atomic success and rollback tests require exact allowance exhaustion.
        // slither-disable-next-line incorrect-equality
        require(
            IERC20LaunchAsset(result.token).allowance(address(this), result.strategy) == 0,
            "TOKEN_ALLOWANCE_REMAINS"
        );
        // Direct launch and rollback tests require exact preservation of entry USDC dust.
        // slither-disable-next-line incorrect-equality
        require(
            IERC20LaunchAsset(USDC).balanceOf(address(this)) == entryUsdcBalance, "USDC_CHANGED"
        );
    }

    function _auctionSteps() private pure returns (bytes memory) {
        // The vector test fixes this exact 104-byte auction schedule.
        // slither-disable-next-line too-many-digits
        return hex"0000360000002a8e000044000000214500004b0000001e7b00004f0000001ccd0000530000001b9c0000550000001ab300005800000019f700005a000000195a00005c00000018d400005e000000185e00005f00000017f8000061000000179b2d97e60000000001";
    }

    function _requireContract(address account) private view {
        require(account != address(0), "DEPENDENCY_ZERO");
        require(account.code.length != 0, "DEPENDENCY_NOT_CONTRACT");
    }
}

interface IERC20LaunchAsset {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IERC721Identity {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IStakingRouterBinding {
    function subjectRegistry() external view returns (address);
}

interface IPendingOwned {
    function pendingOwner() external view returns (address);
}
