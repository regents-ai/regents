// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISubjectRegistry {
    enum Lifecycle {
        Active,
        Quarantined,
        Retired
    }

    struct SubjectConfig {
        address stakeToken;
        address splitter;
        address treasurySafe;
        address ingress;
        address paymentLinkFactory;
        address strategy;
        address launchFeeRegistry;
        address feeVault;
        address feeHook;
        uint256 identityChainId;
        address identityRegistry;
        uint256 identityAgentId;
        Lifecycle lifecycle;
        string label;
        address safeRuntime;
    }

    struct SubjectRegistration {
        bytes32 subjectId;
        address stakeToken;
        address splitter;
        address agentSafe;
        address ingress;
        address paymentLinkFactory;
        address strategy;
        address launchFeeRegistry;
        address feeVault;
        address feeHook;
        uint256 identityChainId;
        address identityRegistry;
        uint256 identityAgentId;
        string label;
        address safeRuntime;
    }

    function getSubject(bytes32 subjectId) external view returns (SubjectConfig memory);
    function lifecycleOf(bytes32 subjectId) external view returns (Lifecycle);
    function splitterOfSubject(bytes32 subjectId) external view returns (address);
    function subjectOfStakeToken(address stakeToken) external view returns (bytes32);
    function restorationExecutableAt(bytes32 subjectId) external view returns (uint256);
    function restorationPolicyCommitment(bytes32 subjectId) external view returns (bytes32);
    function canRegisterSubject(address account) external view returns (bool);
    function subjectCountForStakeToken(address stakeToken) external view returns (uint256);
    function subjectForStakeTokenAt(address stakeToken, uint256 index)
        external
        view
        returns (bytes32);
    function subjectsForStakeToken(address stakeToken) external view returns (bytes32[] memory);

    function registerSubject(SubjectRegistration calldata registration) external;
    function quarantineSubject(bytes32 subjectId) external;
    function requestRestoration(bytes32 subjectId) external;
    function executeRestoration(bytes32 subjectId) external;
    function cancelRestoration(bytes32 subjectId) external;
    function retireSubject(bytes32 subjectId) external;
}
