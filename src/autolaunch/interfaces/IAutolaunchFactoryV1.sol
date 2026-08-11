// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAutolaunchFactoryV1 {
    struct LaunchParams {
        uint256 agentId;
        string tokenName;
        string tokenSymbol;
        uint64 startBlock;
        uint256 floorPrice;
        uint128 requiredRegentRaised;
        uint256 expectedFee;
        bytes32 launchFeeHookSalt;
    }

    struct LaunchResult {
        address token;
        address auction;
        address strategy;
        address vestingWallet;
        address revenueShare;
        address defaultIngress;
        address canonicalPaymentLink;
        bytes32 subjectId;
        bytes32 poolId;
    }

    function launch(LaunchParams calldata params) external returns (LaunchResult memory result);

    function launchFee() external view returns (uint256);

    function setLaunchFee(uint256 newLaunchFee) external;

    event LaunchFeeUpdated(uint256 previousLaunchFee, uint256 newLaunchFee);

    event LaunchCreated(
        bytes32 indexed launchId,
        uint256 indexed agentId,
        address indexed agentSafe,
        address token,
        address auction,
        address strategy,
        address vestingWallet,
        address revenueShare,
        address defaultIngress,
        address canonicalPaymentLink,
        bytes32 poolId
    );
}
