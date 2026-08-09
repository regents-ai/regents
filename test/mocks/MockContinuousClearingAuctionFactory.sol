// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    AuctionParameters,
    Checkpoint,
    LBPInitializationParams
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {
    IContinuousClearingAuctionFactory
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuctionFactory.sol";
import {
    IDistributionContract
} from "src/autolaunch/cca/interfaces/external/IDistributionContract.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";

contract MockDistributionContract is IDistributionContract {
    using SafeTransferLib for address;

    address public immutable token;
    address public immutable currency;
    address public immutable tokensRecipient;
    address public immutable fundsRecipient;
    uint64 public immutable endBlock;
    uint128 public immutable requiredCurrencyRaised;
    bool public received;
    bool public currencySwept;
    uint256 public protocolFeeAmount;
    uint64 public lastCheckpointedBlock;
    uint256 public pendingFinalizationSteps;
    uint256 public bidCount;
    bool public soldOut;
    mapping(uint256 => bool) public bidExited;
    mapping(uint256 => bool) public bidClaimed;
    uint256 private _currencyRaised;

    constructor(
        address token_,
        address currency_,
        address tokensRecipient_,
        address fundsRecipient_,
        uint64 endBlock_,
        uint128 requiredCurrencyRaised_,
        uint256 pendingFinalizationSteps_,
        uint256 protocolFeeAmount_
    ) {
        token = token_;
        currency = currency_;
        tokensRecipient = tokensRecipient_;
        fundsRecipient = fundsRecipient_;
        endBlock = endBlock_;
        requiredCurrencyRaised = requiredCurrencyRaised_;
        pendingFinalizationSteps = pendingFinalizationSteps_;
        protocolFeeAmount = protocolFeeAmount_;
        if (pendingFinalizationSteps_ == 0) lastCheckpointedBlock = endBlock_;
    }

    function onTokensReceived() external {
        received = true;
    }

    function isGraduated() external view returns (bool) {
        return currencySwept || currencyRaised() >= requiredCurrencyRaised;
    }

    function currencyRaised() public view returns (uint256) {
        uint256 balance = _balanceOf(currency, address(this));
        return balance > _currencyRaised ? balance : _currencyRaised;
    }

    function lbpInitializationParams() external view returns (LBPInitializationParams memory) {
        uint256 gross = currencyRaised();
        uint256 fee = protocolFeeAmount > gross ? gross : protocolFeeAmount;
        return LBPInitializationParams({
            initialPriceX96: 1 << 96, tokensSold: 0, currencyRaised: gross - fee
        });
    }

    function remainingSupplyQ96X7() external view returns (uint256) {
        return _remainingSupply() << 96;
    }

    function remainingSupply() external view returns (uint256) {
        return _remainingSupply();
    }

    function requiredDemandQ96(uint256 priceQ96) external view returns (uint256) {
        return _remainingSupply() * priceQ96;
    }

    function requiredDemandQ96AtNextActiveTick() external view returns (uint256) {
        return pendingFinalizationSteps;
    }

    function setProtocolFeeAmount(uint256 amount) external {
        protocolFeeAmount = amount;
    }

    function setSoldOut(bool soldOut_) external {
        soldOut = soldOut_;
    }

    function checkpoint() external returns (Checkpoint memory checkpoint_) {
        require(pendingFinalizationSteps == 0, "FINALIZATION_PENDING");
        lastCheckpointedBlock = endBlock;
        checkpoint_.clearingPrice = 1 << 96;
        checkpoint_.cumulativeMps = 10_000_000;
    }

    function forceIterateOverTicks(uint256) external returns (uint256 clearingPriceQ96) {
        require(pendingFinalizationSteps != 0, "NO_PENDING_TICKS");
        unchecked {
            --pendingFinalizationSteps;
        }
        return 1 << 96;
    }

    function submitBid(uint256, uint128, address, uint256, bytes calldata)
        external
        payable
        returns (uint256 bidId)
    {
        bidId = ++bidCount;
    }

    function submitBid(uint256, uint128, address, bytes calldata)
        external
        payable
        returns (uint256 bidId)
    {
        bidId = ++bidCount;
    }

    function exitBid(uint256 bidId) external {
        bidExited[bidId] = true;
    }

    function exitPartiallyFilledBid(uint256 bidId, uint64, uint64) external {
        bidExited[bidId] = true;
    }

    function claimTokens(uint256 bidId) external {
        bidClaimed[bidId] = true;
    }

    function claimTokensBatch(address, uint256[] calldata bidIds) external {
        for (uint256 i; i < bidIds.length; ++i) {
            bidClaimed[bidIds[i]] = true;
        }
    }

    function sweepUnsoldTokens() external {
        require(block.number > endBlock, "AUCTION_NOT_ENDED");
        require(msg.sender == tokensRecipient, "ONLY_TOKENS_RECIPIENT");
        token.safeTransfer(tokensRecipient, _balanceOf(token, address(this)));
    }

    function sweepCurrency() external {
        require(block.number > endBlock, "AUCTION_NOT_ENDED");
        require(msg.sender == fundsRecipient, "ONLY_FUNDS_RECIPIENT");
        require(this.isGraduated(), "AUCTION_NOT_GRADUATED");
        uint256 balance = _balanceOf(currency, address(this));
        if (balance > _currencyRaised) {
            _currencyRaised = balance;
        }
        uint256 fee = protocolFeeAmount > balance ? balance : protocolFeeAmount;
        currencySwept = true;
        currency.safeTransfer(fundsRecipient, balance - fee);
    }

    function _balanceOf(address token_, address account) internal view returns (uint256 balance) {
        (bool success, bytes memory data) =
            token_.staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        require(success && data.length >= 32, "BALANCE_READ_FAILED");
        balance = abi.decode(data, (uint256));
    }

    function _remainingSupply() internal view returns (uint256) {
        return soldOut ? 0 : _balanceOf(token, address(this));
    }
}

contract MockContinuousClearingAuctionFactory is IContinuousClearingAuctionFactory {
    address public lastToken;
    uint256 public lastAmount;
    bytes public lastConfigData;
    bytes32 public lastSalt;
    address public lastAuction;
    address public protocolFeeController;
    uint256 public pendingFinalizationSteps;
    uint256 public protocolFeeAmount;

    function configureFinalization(uint256 pendingSteps) external {
        pendingFinalizationSteps = pendingSteps;
    }

    function configureProtocolFee(uint256 amount) external {
        protocolFeeAmount = amount;
    }

    function _deploymentSalt(
        address sender,
        address token,
        uint256 amount,
        bytes calldata configData,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(sender, token, amount, keccak256(configData), salt));
    }

    function create(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        external
        returns (IDistributionContract distributionContract)
    {
        AuctionParameters memory params = abi.decode(configData, (AuctionParameters));
        lastToken = token;
        lastAmount = amount;
        lastConfigData = configData;
        lastSalt = salt;

        MockDistributionContract auction = new MockDistributionContract{
            salt: _deploymentSalt(msg.sender, token, amount, configData, salt)
        }(
            token,
            params.currency,
            params.tokensRecipient,
            params.fundsRecipient,
            params.endBlock,
            params.requiredCurrencyRaised,
            pendingFinalizationSteps,
            protocolFeeAmount
        );
        lastAuction = address(auction);
        return auction;
    }

    function getAddress(
        address token,
        uint256 amount,
        bytes calldata configData,
        bytes32 salt,
        address sender
    ) external view returns (IDistributionContract) {
        AuctionParameters memory params = abi.decode(configData, (AuctionParameters));
        bytes32 deploymentSalt = _deploymentSalt(sender, token, amount, configData, salt);
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(MockDistributionContract).creationCode,
                abi.encode(
                    token,
                    params.currency,
                    params.tokensRecipient,
                    params.fundsRecipient,
                    params.endBlock,
                    params.requiredCurrencyRaised,
                    pendingFinalizationSteps,
                    protocolFeeAmount
                )
            )
        );
        return IDistributionContract(
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff), address(this), deploymentSalt, bytecodeHash
                            )
                        )
                    )
                )
            )
        );
    }
}
