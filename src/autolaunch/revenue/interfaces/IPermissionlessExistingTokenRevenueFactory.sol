// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPermissionlessExistingTokenRevenueFactory {
    struct ExistingTokenRevenueConfig {
        address stakeToken;
        address treasury;
        uint16 stakerPoolBps;
        string label;
        bytes32 salt;
    }

    function createExistingTokenRevenueSubject(ExistingTokenRevenueConfig calldata cfg)
        external
        returns (bytes32 subjectId, address splitter, address ingress);
}
