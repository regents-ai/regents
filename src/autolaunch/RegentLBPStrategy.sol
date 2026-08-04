// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    AuctionParameters,
    IContinuousClearingAuction
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {
    IContinuousClearingAuctionFactory
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuctionFactory.sol";
import {
    IDistributionContract
} from "src/autolaunch/cca/interfaces/external/IDistributionContract.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract RegentLBPStrategy is IDistributionContract {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeTransferLib for address;

    uint16 internal constant BPS_DENOMINATOR = 10_000;
    /// @notice Fixed protocol preset: 40% of the raised REGENT seeds the graduated pool's LP;
    ///         the remaining 60% is swept to the agent treasury. Identical for every launch.
    uint16 public constant LP_CURRENCY_BPS = 4000;
    /// @notice Canonical dead address. The migrated Uniswap v4 LP position NFT is minted here so
    ///         the graduated pool's liquidity is locked forever — nobody, including the agent,
    ///         can ever decrease or withdraw it. Failed-launch token supply burns here too.
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public immutable token;
    address public immutable quoteToken;
    address public immutable auctionInitializerFactory;
    address public immutable officialPoolHook;
    address public immutable agentSafe;
    address public immutable vestingWallet;
    address public immutable operator;
    address public immutable positionManager;
    address public immutable poolManager;
    address public immutable subjectRegistry;
    bytes32 public immutable subjectId;
    uint24 public immutable officialPoolFee;
    int24 public immutable officialPoolTickSpacing;

    address public immutable auctionCreator;
    uint64 public immutable migrationBlock;
    uint64 public immutable sweepBlock;
    uint24 public immutable tokenSplitToAuctionMps;
    uint128 public immutable totalStrategySupply;
    uint128 public immutable auctionTokenAmount;
    uint128 public immutable reserveTokenAmount;

    AuctionParameters public auctionParameters;
    address public auctionAddress;
    bytes32 public migratedPoolId;
    uint256 public migratedPositionId;
    uint128 public migratedLiquidity;
    uint128 public migratedQuoteTokenForLP;
    uint128 public migratedTokenForLP;
    uint256 public accountedAuctionQuoteToken;
    bool public migrated;
    bool public failedAuctionRecovered;
    uint256 private _reentrancyGuard = 1;

    struct StrategyConfig {
        address token;
        address quoteToken;
        address auctionInitializerFactory;
        AuctionParameters auctionParameters;
        address officialPoolHook;
        address agentSafe;
        address vestingWallet;
        address operator;
        address positionManager;
        address poolManager;
        address subjectRegistry;
        uint24 officialPoolFee;
        int24 officialPoolTickSpacing;
        address auctionCreator;
        uint64 migrationBlock;
        uint64 sweepBlock;
        uint24 tokenSplitToAuctionMps;
        uint128 totalStrategySupply;
        uint128 auctionTokenAmount;
        uint128 reserveTokenAmount;
    }

    struct MigrationLiquidity {
        uint256 quoteTokenBalance;
        uint256 quoteTokenForLP;
        uint256 tokenForLP;
        uint128 quoteTokenForLPUint128;
        uint128 tokenForLPUint128;
        PoolKey poolKey;
        bytes32 poolId;
        bool tokenIsCurrency0;
        uint160 sqrtPriceX96;
        uint128 liquidity;
        uint256 positionId;
    }

    event AuctionCreated(address indexed auction, uint128 auctionTokenAmount);
    event Migrated(
        bytes32 indexed poolId,
        uint256 indexed positionId,
        uint128 currencyUsedForLP,
        uint128 tokenUsedForLP,
        uint128 liquidity
    );
    event TokensSweptToVesting(address indexed vestingWallet, uint256 amount);
    event QuoteTokenSweptToTreasury(address indexed treasury, uint256 amount);
    event AuctionQuoteTokenAccounted(
        address indexed auction, uint256 quoteTokenRaised, uint256 strategyQuoteTokenBalance
    );
    event FailedAuctionBurned(
        address indexed auction,
        bytes32 indexed subjectId,
        uint256 strategyTokensBurned,
        uint256 vestingTokensBurned
    );
    event NativeRescued(address indexed recipient, uint256 amount);
    event UnsupportedTokenRescued(address indexed token, uint256 amount, address indexed recipient);

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    modifier onlyTreasury() {
        require(msg.sender == agentSafe, "ONLY_TREASURY");
        _;
    }

    constructor(StrategyConfig memory cfg) {
        require(cfg.token != address(0), "TOKEN_ZERO");
        require(cfg.quoteToken != address(0), "QUOTE_TOKEN_ZERO");
        require(cfg.auctionInitializerFactory != address(0), "AUCTION_FACTORY_ZERO");
        require(cfg.officialPoolHook != address(0), "HOOK_ZERO");
        require(cfg.agentSafe != address(0), "AGENT_SAFE_ZERO");
        require(cfg.vestingWallet != address(0), "VESTING_ZERO");
        require(cfg.operator != address(0), "OPERATOR_ZERO");
        require(cfg.positionManager != address(0), "POSITION_MANAGER_ZERO");
        require(cfg.poolManager != address(0), "POOL_MANAGER_ZERO");
        require(cfg.subjectRegistry != address(0), "SUBJECT_REGISTRY_ZERO");
        require(cfg.auctionCreator != address(0), "AUCTION_CREATOR_ZERO");
        require(cfg.officialPoolTickSpacing > 0, "POOL_TICK_SPACING_INVALID");
        require(cfg.officialPoolFee <= 1_000_000, "POOL_FEE_INVALID");
        require(cfg.auctionParameters.currency == cfg.quoteToken, "AUCTION_QUOTE_TOKEN_MISMATCH");
        require(
            cfg.auctionParameters.startBlock < cfg.auctionParameters.endBlock,
            "AUCTION_BLOCKS_INVALID"
        );
        require(
            cfg.auctionParameters.claimBlock >= cfg.auctionParameters.endBlock, "CLAIM_BEFORE_END"
        );
        require(cfg.migrationBlock > cfg.auctionParameters.endBlock, "MIGRATION_BEFORE_END");
        require(cfg.sweepBlock > cfg.migrationBlock, "SWEEP_BEFORE_MIGRATION");
        require(cfg.tokenSplitToAuctionMps != 0, "TOKEN_SPLIT_ZERO");
        require(cfg.tokenSplitToAuctionMps <= 10_000_000, "TOKEN_SPLIT_INVALID");
        require(cfg.totalStrategySupply != 0, "SUPPLY_ZERO");
        require(
            uint256(cfg.auctionTokenAmount) + uint256(cfg.reserveTokenAmount)
                == cfg.totalStrategySupply,
            "SUPPLY_SPLIT_INVALID"
        );
        require(cfg.auctionTokenAmount != 0, "AUCTION_SUPPLY_ZERO");
        require(cfg.reserveTokenAmount != 0, "RESERVE_SUPPLY_ZERO");

        token = cfg.token;
        quoteToken = cfg.quoteToken;
        auctionInitializerFactory = cfg.auctionInitializerFactory;
        officialPoolHook = cfg.officialPoolHook;
        agentSafe = cfg.agentSafe;
        vestingWallet = cfg.vestingWallet;
        operator = cfg.operator;
        positionManager = cfg.positionManager;
        poolManager = cfg.poolManager;
        subjectRegistry = cfg.subjectRegistry;
        subjectId = keccak256(abi.encode(block.chainid, cfg.token));
        officialPoolFee = cfg.officialPoolFee;
        officialPoolTickSpacing = cfg.officialPoolTickSpacing;
        auctionCreator = cfg.auctionCreator;
        migrationBlock = cfg.migrationBlock;
        sweepBlock = cfg.sweepBlock;
        tokenSplitToAuctionMps = cfg.tokenSplitToAuctionMps;
        totalStrategySupply = cfg.totalStrategySupply;
        auctionTokenAmount = cfg.auctionTokenAmount;
        reserveTokenAmount = cfg.reserveTokenAmount;
        auctionParameters = cfg.auctionParameters;
    }

    function onTokensReceived() external nonReentrant {
        require(msg.sender == auctionCreator, "ONLY_AUCTION_CREATOR");
        require(auctionAddress == address(0), "AUCTION_ALREADY_CREATED");
        require(
            IERC20SupplyMinimal(token).balanceOf(address(this)) >= totalStrategySupply,
            "STRATEGY_BALANCE_LOW"
        );

        AuctionParameters memory params = auctionParameters;
        // The strategy is the tokens recipient so unsold auction tokens always route through it:
        // to vesting after a graduated launch, to the burn address after a failed one. The agent
        // never receives launch tokens directly from the auction.
        params.tokensRecipient = address(this);
        params.fundsRecipient = address(this);
        bytes memory initData = abi.encode(params);
        address predictedAuction = address(
            IContinuousClearingAuctionFactory(auctionInitializerFactory)
                .getAddress(token, auctionTokenAmount, initData, bytes32(0), address(this))
        );
        require(predictedAuction != address(0), "AUCTION_PREDICT_ZERO");

        auctionAddress = predictedAuction;

        IDistributionContract auction = IContinuousClearingAuctionFactory(auctionInitializerFactory)
            .create(token, auctionTokenAmount, initData, bytes32(0));
        require(address(auction) == predictedAuction, "AUCTION_ADDRESS_MISMATCH");

        token.safeTransfer(predictedAuction, auctionTokenAmount);
        auction.onTokensReceived();

        emit AuctionCreated(predictedAuction, auctionTokenAmount);
    }

    function migrate() external nonReentrant {
        require(msg.sender == operator, "NOT_OPERATOR");
        require(block.number >= migrationBlock, "MIGRATION_NOT_ALLOWED");
        require(!migrated, "ALREADY_MIGRATED");
        migrated = true;
        require(auctionAddress != address(0), "AUCTION_NOT_CREATED");

        IContinuousClearingAuction auction = IContinuousClearingAuction(auctionAddress);
        require(auction.isGraduated(), "AUCTION_NOT_GRADUATED");

        MigrationLiquidity memory migration = _prepareMigrationLiquidity(auction);
        _initializeMigrationPool(migration);
        _mintMigrationLiquidity(migration);
        _recordMigration(migration);

        emit Migrated(
            migration.poolId,
            migration.positionId,
            migration.quoteTokenForLPUint128,
            migration.tokenForLPUint128,
            migration.liquidity
        );
    }

    function _prepareMigrationLiquidity(IContinuousClearingAuction auction)
        internal
        returns (MigrationLiquidity memory migration)
    {
        migration.quoteTokenBalance = _accountAuctionQuoteToken(auction);
        migration.quoteTokenForLP =
            (migration.quoteTokenBalance * LP_CURRENCY_BPS) / BPS_DENOMINATOR;
        require(migration.quoteTokenForLP != 0, "LP_QUOTE_TOKEN_ZERO");

        uint256 tokenBalance = IERC20SupplyMinimal(token).balanceOf(address(this));
        migration.tokenForLP = tokenBalance > reserveTokenAmount ? reserveTokenAmount : tokenBalance;
        require(migration.tokenForLP != 0, "LP_TOKEN_ZERO");
        migration.quoteTokenForLPUint128 = _toUint128(migration.quoteTokenForLP);
        migration.tokenForLPUint128 = _toUint128(migration.tokenForLP);

        migration.poolKey = _poolKey();
        migration.poolId = PoolId.unwrap(migration.poolKey.toId());
        migration.tokenIsCurrency0 = Currency.wrap(token) == migration.poolKey.currency0;
        migration.sqrtPriceX96 = _sqrtPriceX96(
            migration.tokenIsCurrency0, migration.quoteTokenForLP, migration.tokenForLP
        );
        migration.liquidity = _liquidityForAmounts(
            migration.poolKey,
            migration.tokenIsCurrency0,
            migration.sqrtPriceX96,
            migration.quoteTokenForLP,
            migration.tokenForLP
        );
        require(migration.liquidity != 0, "LP_LIQUIDITY_ZERO");
        migration.positionId = IPositionManager(positionManager).nextTokenId();
    }

    function _initializeMigrationPool(MigrationLiquidity memory migration) internal {
        int24 initializedTick =
            IPoolManager(poolManager).initialize(migration.poolKey, migration.sqrtPriceX96);
        require(
            initializedTick == TickMath.getTickAtSqrtPrice(migration.sqrtPriceX96),
            "POOL_TICK_MISMATCH"
        );
    }

    function _mintMigrationLiquidity(MigrationLiquidity memory migration) internal {
        token.safeTransfer(positionManager, migration.tokenForLP);
        quoteToken.safeTransfer(positionManager, migration.quoteTokenForLP);
        IPositionManager(positionManager)
            .modifyLiquidities(
                abi.encode(
                    bytes.concat(
                        bytes1(uint8(Actions.MINT_POSITION)),
                        bytes1(uint8(Actions.SETTLE)),
                        bytes1(uint8(Actions.SETTLE)),
                        bytes1(uint8(Actions.CLOSE_CURRENCY)),
                        bytes1(uint8(Actions.CLOSE_CURRENCY))
                    ),
                    _migrationParams(
                        migration.poolKey,
                        migration.liquidity,
                        migration.quoteTokenForLP,
                        migration.tokenForLP,
                        migration.tokenIsCurrency0
                    )
                ),
                block.timestamp
            );
    }

    function _recordMigration(MigrationLiquidity memory migration) internal {
        accountedAuctionQuoteToken = migration.quoteTokenBalance;
        migratedPoolId = migration.poolId;
        migratedPositionId = migration.positionId;
        migratedLiquidity = migration.liquidity;
        migratedQuoteTokenForLP = migration.quoteTokenForLPUint128;
        migratedTokenForLP = migration.tokenForLPUint128;
    }

    function sweepToken() external nonReentrant {
        require(msg.sender == operator, "NOT_OPERATOR");
        require(block.number >= sweepBlock, "SWEEP_NOT_ALLOWED");
        require(migrated, "MIGRATION_REQUIRED");

        _sweepUnsoldAuctionTokens();

        uint256 tokenBalance = IERC20SupplyMinimal(token).balanceOf(address(this));
        require(tokenBalance != 0, "NOTHING_TO_SWEEP");

        token.safeTransfer(vestingWallet, tokenBalance);

        emit TokensSweptToVesting(vestingWallet, tokenBalance);
    }

    function sweepQuoteToken() external nonReentrant {
        require(msg.sender == operator, "NOT_OPERATOR");
        require(block.number >= sweepBlock, "SWEEP_NOT_ALLOWED");
        require(migrated, "MIGRATION_REQUIRED");

        uint256 quoteTokenBalance = IERC20SupplyMinimal(quoteToken).balanceOf(address(this));
        require(quoteTokenBalance != 0, "NOTHING_TO_SWEEP");

        quoteToken.safeTransfer(agentSafe, quoteTokenBalance);

        emit QuoteTokenSweptToTreasury(agentSafe, quoteTokenBalance);
    }

    /// @notice Unwinds a launch whose auction did not graduate. The entire launched-token supply
    ///         held by the launch stack — unsold auction tokens, the strategy's LP reserve, and
    ///         the agent's unvested allocation — is burned to the canonical dead address, and the
    ///         subject is marked dead so its rev-share splitter and ingress accounts are disabled
    ///         permanently. The agent receives nothing. Bidders reclaim their REGENT themselves
    ///         through the auction's own exit path.
    function recoverFailedAuction() external nonReentrant {
        require(msg.sender == operator, "NOT_OPERATOR");
        require(block.number >= sweepBlock, "SWEEP_NOT_ALLOWED");
        require(!migrated, "ALREADY_MIGRATED");
        require(!failedAuctionRecovered, "ALREADY_RECOVERED");
        require(auctionAddress != address(0), "AUCTION_NOT_CREATED");

        IContinuousClearingAuction auction = IContinuousClearingAuction(auctionAddress);
        require(!auction.isGraduated(), "AUCTION_GRADUATED");
        failedAuctionRecovered = true;

        _sweepUnsoldAuctionTokens();
        uint256 vestingTokensBurned = ILaunchVestingBurnable(vestingWallet).burnOnFailedLaunch();

        uint256 tokenBalance = IERC20SupplyMinimal(token).balanceOf(address(this));
        require(tokenBalance != 0, "NOTHING_TO_BURN");
        token.safeTransfer(BURN_ADDRESS, tokenBalance);

        ISubjectRegistry(subjectRegistry).markSubjectDead(subjectId);

        emit FailedAuctionBurned(auctionAddress, subjectId, tokenBalance, vestingTokensBurned);
    }

    /// @dev Pulls any unsold launch tokens back from the auction. The strategy is the auction's
    ///      tokens recipient, so this is the only path unsold tokens can take.
    function _sweepUnsoldAuctionTokens() internal {
        IContinuousClearingAuction auction = IContinuousClearingAuction(auctionAddress);
        if (auction.remainingSupply() != 0) {
            auction.sweepUnsoldTokens();
        }
    }

    function rescueNative(address recipient) external onlyTreasury nonReentrant {
        require(recipient != address(0), "RECIPIENT_ZERO");

        uint256 amount = address(this).balance;
        require(amount != 0, "NOTHING_TO_RESCUE");

        address(0).safeTransfer(recipient, amount);
        emit NativeRescued(recipient, amount);
    }

    function rescueUnsupportedToken(address token_, uint256 amount, address recipient)
        external
        onlyTreasury
        nonReentrant
    {
        require(token_ != address(0), "TOKEN_ZERO");
        require(token_ != token && token_ != quoteToken, "PROTECTED_TOKEN");
        require(amount != 0, "AMOUNT_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");

        token_.safeTransfer(recipient, amount);
        emit UnsupportedTokenRescued(token_, amount, recipient);
    }

    function _accountAuctionQuoteToken(IContinuousClearingAuction auction)
        internal
        returns (uint256 quoteTokenRaised)
    {
        // The auction is created from the configured CCA factory and migration is non-reentrant.
        // Pre-existing strategy quote-token balance is excluded from the raised amount.
        uint256 balanceBefore = IERC20SupplyMinimal(quoteToken).balanceOf(address(this));
        auction.sweepCurrency();
        uint256 balanceAfter = IERC20SupplyMinimal(quoteToken).balanceOf(address(this));

        require(balanceAfter >= balanceBefore, "AUCTION_QUOTE_TOKEN_LOW");
        quoteTokenRaised = balanceAfter - balanceBefore;
        require(quoteTokenRaised != 0, "NO_QUOTE_TOKEN_RAISED");

        emit AuctionQuoteTokenAccounted(auctionAddress, quoteTokenRaised, balanceAfter);
    }

    function _poolKey() internal view returns (PoolKey memory poolKey) {
        (Currency currency0, Currency currency1) = _sortedCurrencies();
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: officialPoolFee,
            tickSpacing: officialPoolTickSpacing,
            hooks: IHooks(officialPoolHook)
        });
    }

    function _sortedCurrencies() internal view returns (Currency currency0, Currency currency1) {
        Currency tokenCurrency = Currency.wrap(token);
        Currency quoteCurrency = Currency.wrap(quoteToken);
        (currency0, currency1) = tokenCurrency < quoteCurrency
            ? (tokenCurrency, quoteCurrency)
            : (quoteCurrency, tokenCurrency);
    }

    function _migrationParams(
        PoolKey memory poolKey,
        uint128 liquidity,
        uint256 quoteTokenForLP,
        uint256 tokenForLP,
        bool tokenIsCurrency0
    ) internal view returns (bytes[] memory params) {
        uint128 quoteTokenForLPUint128 = _toUint128(quoteTokenForLP);
        uint128 tokenForLPUint128 = _toUint128(tokenForLP);
        uint128 amount0Max = tokenIsCurrency0 ? tokenForLPUint128 : quoteTokenForLPUint128;
        uint128 amount1Max = tokenIsCurrency0 ? quoteTokenForLPUint128 : tokenForLPUint128;
        int24 lowerTick = TickMath.minUsableTick(officialPoolTickSpacing);
        int24 upperTick = TickMath.maxUsableTick(officialPoolTickSpacing);

        params = new bytes[](5);
        // The LP position NFT is minted directly to the canonical dead address: no owner, no
        // approvals, so PositionManager's onlyIfApproved gate makes decreaseLiquidity/burn
        // unreachable forever. Pool trade fees still flow through the LaunchPoolFeeHook, which
        // charges swaps independently of position ownership.
        params[0] = abi.encode(
            poolKey,
            lowerTick,
            upperTick,
            liquidity,
            amount0Max,
            amount1Max,
            BURN_ADDRESS,
            bytes("")
        );
        params[1] = abi.encode(poolKey.currency0, ActionConstants.CONTRACT_BALANCE, false);
        params[2] = abi.encode(poolKey.currency1, ActionConstants.CONTRACT_BALANCE, false);
        params[3] = abi.encode(poolKey.currency0);
        params[4] = abi.encode(poolKey.currency1);
    }

    function _liquidityForAmounts(
        PoolKey memory poolKey,
        bool tokenIsCurrency0,
        uint160 sqrtPriceX96,
        uint256 quoteTokenForLP,
        uint256 tokenForLP
    ) internal pure returns (uint128 liquidity) {
        uint128 quoteTokenForLPUint128 = _toUint128(quoteTokenForLP);
        uint128 tokenForLPUint128 = _toUint128(tokenForLP);
        uint128 amount0 = tokenIsCurrency0 ? tokenForLPUint128 : quoteTokenForLPUint128;
        uint128 amount1 = tokenIsCurrency0 ? quoteTokenForLPUint128 : tokenForLPUint128;
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(poolKey.tickSpacing)),
            TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(poolKey.tickSpacing)),
            amount0,
            amount1
        );
    }

    function _sqrtPriceX96(bool tokenIsCurrency0, uint256 quoteTokenForLP, uint256 tokenForLP)
        internal
        pure
        returns (uint160 sqrtPriceX96)
    {
        uint256 amount0 = tokenIsCurrency0 ? tokenForLP : quoteTokenForLP;
        uint256 amount1 = tokenIsCurrency0 ? quoteTokenForLP : tokenForLP;
        uint256 ratioX192 = FullMath.mulDiv(amount1, uint256(1) << 192, amount0);
        uint256 sqrtPrice = Math.sqrt(ratioX192);
        require(sqrtPrice <= type(uint160).max, "SQRT_PRICE_OVERFLOW");
        // forge-lint: disable-next-line(unsafe-typecast)
        sqrtPriceX96 = uint160(sqrtPrice);
    }

    function _toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "UINT128_OVERFLOW");
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(value);
    }
}

interface ILaunchVestingBurnable {
    function burnOnFailedLaunch() external returns (uint256 amount);
}
