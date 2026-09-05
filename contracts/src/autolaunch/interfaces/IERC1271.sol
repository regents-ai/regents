// SPDX-License-Identifier: MIT
// slither-disable-next-line pragma
pragma solidity ^0.8.26;

interface IERC1271 {
    function isValidSignature(bytes32 digest, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue);
}
