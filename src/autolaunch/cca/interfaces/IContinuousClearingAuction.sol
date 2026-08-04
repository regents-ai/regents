// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct AuctionParameters {
    address currency;
    address tokensRecipient;
    address fundsRecipient;
    uint64 startBlock;
    uint64 endBlock;
    uint64 claimBlock;
    uint256 tickSpacing;
    address validationHook;
    uint256 floorPrice;
    uint128 requiredCurrencyRaised;
    bytes auctionStepsData;
}

struct LBPInitializationParams {
    uint256 initialPriceX96;
    uint256 tokensSold;
    uint256 currencyRaised;
}

interface IContinuousClearingAuction {
    function isGraduated() external view returns (bool);

    function currencyRaised() external view returns (uint256);

    function lbpInitializationParams() external view returns (LBPInitializationParams memory);

    function remainingSupplyQ96X7() external view returns (uint256);

    function remainingSupply() external view returns (uint256);

    function requiredDemandQ96(uint256 priceQ96) external view returns (uint256);

    function requiredDemandQ96AtNextActiveTick() external view returns (uint256);

    function tokensRecipient() external view returns (address);

    function fundsRecipient() external view returns (address);

    function sweepCurrency() external;

    function sweepUnsoldTokens() external;

    // Bidder-side entrypoints, vendored verbatim from
    // Uniswap/continuous-clearing-auction src/shared/interfaces/IContinuousClearingAuction.sol.

    /// @notice Submit a new bid
    /// @param maxPriceQ96 The maximum Q96 price the bidder is willing to pay
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param prevTickPriceQ96 The Q96 price of the previous tick
    /// @param hookData Additional data to pass to the hook required for validation
    /// @return bidId The id of the bid
    function submitBid(
        uint256 maxPriceQ96,
        uint128 amount,
        address owner,
        uint256 prevTickPriceQ96,
        bytes calldata hookData
    ) external payable returns (uint256 bidId);

    /// @notice Exit a bid
    /// @dev This function can only be used for bids where the max price is above the final clearing price after the auction has ended
    /// @param bidId The id of the bid
    function exitBid(uint256 bidId) external;

    /// @notice Exit a bid which has been partially filled
    /// @dev This function can be used only for partially filled bids. For fully filled bids, `exitBid` must be used
    /// @param bidId The id of the bid
    /// @param lastFullyFilledCheckpointBlock The last checkpointed block where the clearing price is strictly < bid.maxPrice
    /// @param outbidBlock The first checkpointed block where the clearing price is strictly > bid.maxPrice, or 0 if the bid is partially filled at the end of the auction
    function exitPartiallyFilledBid(
        uint256 bidId,
        uint64 lastFullyFilledCheckpointBlock,
        uint64 outbidBlock
    ) external;

    /// @notice Claim tokens after the auction's claim block
    /// @notice The bid must be exited before claiming tokens
    /// @dev Anyone can claim tokens for any bid, the tokens are transferred to the bid owner
    /// @param bidId The id of the bid
    function claimTokens(uint256 bidId) external;
}
