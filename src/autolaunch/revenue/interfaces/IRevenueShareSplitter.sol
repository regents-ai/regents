// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRevenueShareSplitter {
    struct RevenueSplitPreview {
        uint256 amountReceived;
        uint256 protocolAmount;
        uint256 subjectLaneAmount;
        uint256 stakerEligibleAmount;
        uint256 treasuryReservedAmount;
        uint256 stakerEntitlement;
        uint256 treasuryResidualAmount;
        uint256 dustAmount;
    }

    struct TreasuryBalancePreview {
        uint256 treasuryResidualUsdc;
        uint256 treasuryReservedUsdc;
        uint256 undistributedDustUsdc;
        uint256 surplusUsdc;
    }

    struct StakeCapacityPreview {
        uint256 totalStaked;
        uint256 stakeCapacity;
        uint256 remainingStakeCapacity;
    }

    function stakeToken() external view returns (address);
    function usdc() external view returns (address);
    function subjectId() external view returns (bytes32);
    function treasuryRecipient() external view returns (address);
    function protocolRecipient() external view returns (address);
    function totalStaked() external view returns (uint256);
    function previewClaimableUSDC(address account) external view returns (uint256);
    function previewRevenueSplit(uint256 amount)
        external
        view
        returns (RevenueSplitPreview memory preview);
    function previewTreasuryBalances() external view returns (TreasuryBalancePreview memory preview);
    function previewStakeCapacity() external view returns (StakeCapacityPreview memory preview);

    function depositUSDC(uint256 amount, bytes32 sourceTag, bytes32 sourceRef)
        external
        returns (uint256 received);

    /// @notice Pulls `amount` USDC from the calling ingress account (which must have approved
    ///         the splitter) and recognizes only the measured received balance delta as
    ///         verified ingress revenue.
    function recordIngressSweep(uint256 amount, bytes32 sourceRef)
        external
        returns (uint256 recognized);
}
