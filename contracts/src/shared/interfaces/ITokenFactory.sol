// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITokenFactory {
    function createToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 totalSupply,
        address recipient,
        bytes calldata configData,
        bytes32 graffiti
    ) external returns (address token);
}
