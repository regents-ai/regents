// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IDistributionContract
} from "src/autolaunch/cca/interfaces/external/IDistributionContract.sol";

interface IDistributionStrategy {
    function initializeDistribution(
        address token,
        uint256 amount,
        bytes calldata configData,
        bytes32 salt
    ) external returns (IDistributionContract distributionContract);
}
