// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AuctionParameters} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {
    IDistributionContract
} from "src/autolaunch/cca/interfaces/external/IDistributionContract.sol";
import {IDistributionStrategy} from "src/shared/interfaces/IDistributionStrategy.sol";
import {Owned} from "src/shared/auth/Owned.sol";
import {RegentLBPStrategy} from "src/autolaunch/RegentLBPStrategy.sol";
import {BaseMainnetChainConfig} from "src/shared/libraries/BaseMainnetChainConfig.sol";
import {AutolaunchBindings} from "src/autolaunch/libraries/AutolaunchBindings.sol";
import {
    IContinuousClearingAuctionFactory
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuctionFactory.sol";

contract RegentLBPStrategyFactory is Owned, IDistributionStrategy {
    struct RegentLBPStrategyConfig {
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
        uint64 migrationBlock;
        uint64 sweepBlock;
        uint24 tokenSplitToAuctionMps;
        uint128 auctionTokenAmount;
        uint128 reserveTokenAmount;
    }

    mapping(address => bool) public authorizedCreators;

    event DistributionInitialized(
        address indexed distributionContract, address indexed token, uint256 amount
    );
    event RegentStrategyCreated(
        address indexed strategy, address indexed token, uint256 strategySupply
    );
    event AuthorizedCreatorSet(address indexed account, bool enabled);

    constructor(address owner_) Owned(owner_) {
        address expectedDeployer = _strategyDeployer();
        RegentLBPStrategyDeployer deployer = new RegentLBPStrategyDeployer();
        require(address(deployer) == expectedDeployer, "DEPLOYER_ADDRESS_MISMATCH");
    }

    modifier onlyAuthorizedCreator() {
        require(msg.sender == owner || authorizedCreators[msg.sender], "ONLY_AUTHORIZED_CREATOR");
        _;
    }

    function setAuthorizedCreator(address account, bool enabled) external onlyOwner {
        require(account != address(0), "ACCOUNT_ZERO");
        authorizedCreators[account] = enabled;
        emit AuthorizedCreatorSet(account, enabled);
    }

    function initializeDistribution(
        address token,
        uint256 amount,
        bytes calldata configData,
        bytes32
    ) external onlyAuthorizedCreator returns (IDistributionContract distributionContract) {
        RegentLBPStrategyConfig memory cfg = abi.decode(configData, (RegentLBPStrategyConfig));
        require(amount <= type(uint128).max, "STRATEGY_SUPPLY_TOO_LARGE");
        _validateQuoteToken(cfg);

        bytes memory constructorArguments = abi.encode(
            RegentLBPStrategy.StrategyConfig({
                token: token,
                quoteToken: cfg.quoteToken,
                auctionInitializerFactory: cfg.auctionInitializerFactory,
                auctionParameters: cfg.auctionParameters,
                officialPoolHook: cfg.officialPoolHook,
                agentSafe: cfg.agentSafe,
                vestingWallet: cfg.vestingWallet,
                operator: cfg.operator,
                positionManager: cfg.positionManager,
                poolManager: cfg.poolManager,
                subjectRegistry: cfg.subjectRegistry,
                officialPoolFee: cfg.officialPoolFee,
                officialPoolTickSpacing: cfg.officialPoolTickSpacing,
                auctionCreator: msg.sender,
                migrationBlock: cfg.migrationBlock,
                sweepBlock: cfg.sweepBlock,
                tokenSplitToAuctionMps: cfg.tokenSplitToAuctionMps,
                // forge-lint: disable-next-line(unsafe-typecast)
                totalStrategySupply: uint128(amount),
                auctionTokenAmount: cfg.auctionTokenAmount,
                reserveTokenAmount: cfg.reserveTokenAmount
            })
        );
        // The fixed deployer only creates the exact strategy, whose constructor makes no calls.
        // slither-disable-next-line reentrancy-events
        distributionContract = IDistributionContract(
            RegentLBPStrategyDeployer(_strategyDeployer()).deploy(constructorArguments)
        );

        emit DistributionInitialized(address(distributionContract), token, amount);
        emit RegentStrategyCreated(address(distributionContract), token, amount);
    }

    function _validateQuoteToken(RegentLBPStrategyConfig memory cfg) internal view {
        BaseMainnetChainConfig.requireRegent(cfg.quoteToken);
        BaseMainnetChainConfig.requirePoolManager(cfg.poolManager);
        BaseMainnetChainConfig.requirePositionManager(cfg.positionManager);
        require(
            cfg.auctionInitializerFactory == AutolaunchBindings.CCA_FACTORY, "CCA_FACTORY_MISMATCH"
        );
        require(
            cfg.auctionInitializerFactory.code.length
                == AutolaunchBindings.CCA_FACTORY_RUNTIME_SIZE,
            "CCA_FACTORY_RUNTIME_SIZE"
        );
        require(
            cfg.auctionInitializerFactory.codehash
                == AutolaunchBindings.CCA_FACTORY_RUNTIME_CODE_HASH,
            "CCA_FACTORY_RUNTIME_HASH"
        );
        require(
            IContinuousClearingAuctionFactory(cfg.auctionInitializerFactory).protocolFeeController()
                == address(0),
            "CCA_PROTOCOL_FEE_CONTROLLER"
        );
        require(cfg.auctionParameters.currency == cfg.quoteToken, "AUCTION_QUOTE_TOKEN_MISMATCH");
        require(cfg.quoteToken.code.length != 0, "QUOTE_TOKEN_NO_CODE");
        require(IERC20MetadataMinimal(cfg.quoteToken).decimals() == 18, "QUOTE_TOKEN_DECIMALS");
    }

    function _strategyDeployer() private view returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(this), hex"01"))))
            );
    }
}

contract RegentLBPStrategyDeployer {
    address private immutable factory;

    constructor() {
        factory = msg.sender;
    }

    function deploy(bytes calldata constructorArguments) external returns (address strategy) {
        require(msg.sender == factory, "ONLY_FACTORY");

        // The apparent literal is compiler-generated fixed strategy creation code.
        // slither-disable-next-line too-many-digits
        bytes memory initcode =
            bytes.concat(type(RegentLBPStrategy).creationCode, constructorArguments);
        // Assembly is required to bubble CREATE return data exactly, including an empty revert.
        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            strategy := create(0, add(initcode, 0x20), mload(initcode))
            if iszero(strategy) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        require(strategy.code.length != 0, "STRATEGY_NO_CODE");
    }
}

interface IERC20MetadataMinimal {
    function decimals() external view returns (uint8);
}
