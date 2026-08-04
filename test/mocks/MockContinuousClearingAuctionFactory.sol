// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    AuctionParameters,
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
    uint256 private _currencyRaised;

    constructor(
        address token_,
        address currency_,
        address tokensRecipient_,
        address fundsRecipient_,
        uint64 endBlock_,
        uint128 requiredCurrencyRaised_
    ) {
        token = token_;
        currency = currency_;
        tokensRecipient = tokensRecipient_;
        fundsRecipient = fundsRecipient_;
        endBlock = endBlock_;
        requiredCurrencyRaised = requiredCurrencyRaised_;
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
        return _balanceOf(token, address(this)) << 96;
    }

    function remainingSupply() external view returns (uint256) {
        return _balanceOf(token, address(this));
    }

    function requiredDemandQ96(uint256 priceQ96) external view returns (uint256) {
        return _balanceOf(token, address(this)) * priceQ96;
    }

    function requiredDemandQ96AtNextActiveTick() external view returns (uint256) {
        return _balanceOf(token, address(this)) * (1 << 96);
    }

    function setProtocolFeeAmount(uint256 amount) external {
        protocolFeeAmount = amount;
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
}

contract MockContinuousClearingAuctionFactory is IContinuousClearingAuctionFactory {
    address public lastToken;
    uint256 public lastAmount;
    bytes public lastConfigData;
    bytes32 public lastSalt;
    address public lastAuction;

    function _deploymentSalt(
        address sender,
        address token,
        uint256 amount,
        bytes calldata configData,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(sender, token, amount, keccak256(configData), salt));
    }

    address public protocolFeeController = address(0xCAFE200);

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
            params.requiredCurrencyRaised
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
                    params.requiredCurrencyRaised
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
