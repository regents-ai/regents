// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDistributionContract} from "./external/IDistributionContract.sol";

interface IContinuousClearingAuctionFactory {
    function create(address token, uint256 totalSupply, bytes calldata configData, bytes32 salt)
        external
        returns (IDistributionContract distributor);

    function getAddress(
        address token,
        uint256 totalSupply,
        bytes calldata configData,
        bytes32 salt,
        address sender
    ) external view returns (IDistributionContract distributor);

    function protocolFeeController() external view returns (address);
}
