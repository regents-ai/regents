// SPDX-License-Identifier: MIT
// slither-disable-next-line pragma
pragma solidity ^0.8.26;

interface IAgentSafe {
    function masterCopy() external view returns (address);
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function nonce() external view returns (uint256);
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory modules, address next);
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);
}
