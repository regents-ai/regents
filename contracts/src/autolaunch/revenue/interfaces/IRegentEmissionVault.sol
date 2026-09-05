// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRegentEmissionVault {
    function regent() external view returns (address);
    function availableRegent() external view returns (uint256);

    function emitRegent(address recipient, uint256 amount, bytes32 subjectId, bytes32 sourceRef)
        external;
}
