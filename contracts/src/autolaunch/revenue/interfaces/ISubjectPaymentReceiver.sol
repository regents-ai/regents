// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISubjectPaymentReceiver {
    function subjectId() external view returns (bytes32);
    function usdc() external view returns (address);
    function destination() external view returns (address);
    function isReceiverActive() external view returns (bool);
    function replacementReceiver() external view returns (address);

    function sweepUSDC(bytes32 sourceRef) external returns (uint256 balance, uint256 recognized);
}
