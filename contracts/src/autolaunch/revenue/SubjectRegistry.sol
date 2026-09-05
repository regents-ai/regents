// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {IOwned} from "src/autolaunch/revenue/interfaces/IOwned.sol";
import {AgentSafePolicy} from "src/autolaunch/libraries/AgentSafePolicy.sol";
import {InputBounds} from "src/autolaunch/revenue/libraries/InputBounds.sol";

interface ISubjectSplitterRotation {
    function pendingTreasuryRecipient() external view returns (address);
}

interface ISubjectStrategyOperator {
    function operator() external view returns (address);
}

contract SubjectRegistry is ISubjectRegistry, IOwned {
    uint256 public constant RESTORATION_DELAY = 24 hours;

    struct IdentityLink {
        uint256 chainId;
        address registry;
        uint256 agentId;
    }

    address public immutable controller;
    address public immutable governance;
    address public immutable guardian;

    mapping(bytes32 => SubjectConfig) private subjects;
    mapping(address => bytes32) public override subjectOfStakeToken;
    mapping(address => bytes32[]) private subjectsByStakeToken;
    mapping(bytes32 => bytes32) public subjectOfIdentityHash;
    mapping(bytes32 => uint256) public override restorationExecutableAt;
    mapping(bytes32 => bytes32) public override restorationPolicyCommitment;

    event SubjectRegistered(
        bytes32 indexed subjectId,
        address indexed stakeToken,
        address indexed agentSafe,
        address splitter,
        address ingress,
        address paymentLinkFactory,
        address strategy,
        address launchFeeRegistry,
        address feeVault,
        address feeHook,
        address safeRuntime
    );
    event SubjectQuarantined(bytes32 indexed subjectId, address indexed caller);
    event RestorationRequested(
        bytes32 indexed subjectId, uint256 executableAt, bytes32 policyCommitment
    );
    event RestorationCancelled(
        bytes32 indexed subjectId, address indexed guardian, bytes32 policyCommitment
    );
    event SubjectRestored(
        bytes32 indexed subjectId, address indexed governance, bytes32 policyCommitment
    );
    event SubjectRetired(bytes32 indexed subjectId, address indexed strategy);

    constructor(address controller_, address governance_, address guardian_) {
        require(controller_ != address(0), "CONTROLLER_ZERO");
        require(governance_ != address(0), "GOVERNANCE_ZERO");
        require(guardian_ != address(0), "GUARDIAN_ZERO");
        require(controller_ != governance_, "CONTROLLER_IS_GOVERNANCE");
        require(controller_ != guardian_, "CONTROLLER_IS_GUARDIAN");
        require(governance_ != guardian_, "GOVERNANCE_IS_GUARDIAN");
        controller = controller_;
        governance = governance_;
        guardian = guardian_;
    }

    /// @notice Compatibility getter for deployment tooling. Governance is immutable.
    function owner() external view override returns (address) {
        return governance;
    }

    function registerSubject(SubjectRegistration calldata registration) external override {
        require(msg.sender == controller, "ONLY_CONTROLLER");
        require(registration.subjectId != bytes32(0), "SUBJECT_ZERO");
        require(registration.stakeToken != address(0), "STAKE_TOKEN_ZERO");
        require(registration.splitter != address(0), "SPLITTER_ZERO");
        require(registration.agentSafe != address(0), "AGENT_SAFE_ZERO");
        require(registration.ingress != address(0), "INGRESS_ZERO");
        require(registration.paymentLinkFactory != address(0), "PAYMENT_LINK_FACTORY_ZERO");
        require(registration.strategy != address(0), "STRATEGY_ZERO");
        require(registration.safeRuntime != address(0), "SAFE_RUNTIME_ZERO");
        require(registration.agentSafe != controller, "AGENT_SAFE_IS_CONTROLLER");
        require(registration.agentSafe != governance, "AGENT_SAFE_IS_GOVERNANCE");
        require(registration.agentSafe != guardian, "AGENT_SAFE_IS_GUARDIAN");
        require(registration.strategy != controller, "STRATEGY_IS_CONTROLLER");
        require(registration.strategy != governance, "STRATEGY_IS_GOVERNANCE");
        require(registration.strategy != guardian, "STRATEGY_IS_GUARDIAN");
        require(registration.strategy != registration.agentSafe, "STRATEGY_IS_AGENT_SAFE");
        require(registration.safeRuntime != controller, "SAFE_RUNTIME_IS_CONTROLLER");
        require(registration.safeRuntime != governance, "SAFE_RUNTIME_IS_GOVERNANCE");
        require(registration.safeRuntime != guardian, "SAFE_RUNTIME_IS_GUARDIAN");
        require(registration.safeRuntime != registration.agentSafe, "SAFE_RUNTIME_IS_AGENT_SAFE");
        require(registration.safeRuntime != registration.strategy, "SAFE_RUNTIME_IS_STRATEGY");
        require(
            ISubjectStrategyOperator(registration.strategy).operator() == registration.safeRuntime,
            "SAFE_RUNTIME_OPERATOR_MISMATCH"
        );
        require(registration.launchFeeRegistry != address(0), "FEE_REGISTRY_ZERO");
        require(registration.feeVault != address(0), "FEE_VAULT_ZERO");
        require(registration.feeHook != address(0), "FEE_HOOK_ZERO");
        require(subjects[registration.subjectId].stakeToken == address(0), "SUBJECT_EXISTS");
        require(
            subjectOfStakeToken[registration.stakeToken] == bytes32(0), "STAKE_TOKEN_ALREADY_LINKED"
        );
        InputBounds.requireStringMax(
            registration.label, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG"
        );
        _validateIdentity(registration);

        subjects[registration.subjectId] = SubjectConfig({
            stakeToken: registration.stakeToken,
            splitter: registration.splitter,
            treasurySafe: registration.agentSafe,
            ingress: registration.ingress,
            paymentLinkFactory: registration.paymentLinkFactory,
            strategy: registration.strategy,
            launchFeeRegistry: registration.launchFeeRegistry,
            feeVault: registration.feeVault,
            feeHook: registration.feeHook,
            identityChainId: registration.identityChainId,
            identityRegistry: registration.identityRegistry,
            identityAgentId: registration.identityAgentId,
            lifecycle: Lifecycle.Active,
            label: registration.label,
            safeRuntime: registration.safeRuntime
        });
        subjectOfStakeToken[registration.stakeToken] = registration.subjectId;
        subjectsByStakeToken[registration.stakeToken].push(registration.subjectId);

        if (registration.identityRegistry != address(0)) {
            bytes32 identityHash = _identityHash(
                registration.identityChainId,
                registration.identityRegistry,
                registration.identityAgentId
            );
            require(subjectOfIdentityHash[identityHash] == bytes32(0), "IDENTITY_ALREADY_LINKED");
            subjectOfIdentityHash[identityHash] = registration.subjectId;
        }

        emit SubjectRegistered(
            registration.subjectId,
            registration.stakeToken,
            registration.agentSafe,
            registration.splitter,
            registration.ingress,
            registration.paymentLinkFactory,
            registration.strategy,
            registration.launchFeeRegistry,
            registration.feeVault,
            registration.feeHook,
            registration.safeRuntime
        );
    }

    function quarantineSubject(bytes32 subjectId) external override {
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        require(
            msg.sender == cfg.treasurySafe || msg.sender == governance || msg.sender == guardian,
            "ONLY_QUARANTINE_AUTHORITY"
        );
        require(cfg.lifecycle == Lifecycle.Active, "SUBJECT_NOT_ACTIVE");
        cfg.lifecycle = Lifecycle.Quarantined;
        emit SubjectQuarantined(subjectId, msg.sender);
    }

    // A fixed governance delay is the intended lifecycle policy.
    // slither-disable-next-line timestamp
    function requestRestoration(bytes32 subjectId) external override {
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        require(msg.sender == cfg.treasurySafe, "ONLY_AGENT_SAFE");
        require(cfg.lifecycle == Lifecycle.Quarantined, "SUBJECT_NOT_QUARANTINED");
        require(restorationExecutableAt[subjectId] == 0, "RESTORATION_PENDING");
        bytes32 policyCommitment = AgentSafePolicy.structureCommitment(
            AgentSafePolicy.readStructure(cfg.treasurySafe, controller, cfg.safeRuntime)
        );
        require(_pendingTreasuryRecipient(cfg.splitter) == address(0), "TREASURY_ROTATION_PENDING");
        uint256 executableAt = block.timestamp + RESTORATION_DELAY;
        restorationExecutableAt[subjectId] = executableAt;
        restorationPolicyCommitment[subjectId] = policyCommitment;
        emit RestorationRequested(subjectId, executableAt, policyCommitment);
    }

    // slither-disable-next-line timestamp
    function executeRestoration(bytes32 subjectId) external override {
        require(msg.sender == governance, "ONLY_GOVERNANCE");
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        require(cfg.lifecycle == Lifecycle.Quarantined, "SUBJECT_NOT_QUARANTINED");
        uint256 executableAt = restorationExecutableAt[subjectId];
        require(executableAt != 0, "NO_RESTORATION_PENDING");
        require(block.timestamp >= executableAt, "RESTORATION_DELAY");
        bytes32 policyCommitment = restorationPolicyCommitment[subjectId];
        bytes32 currentCommitment = AgentSafePolicy.structureCommitment(
            AgentSafePolicy.readStructure(cfg.treasurySafe, controller, cfg.safeRuntime)
        );
        require(currentCommitment == policyCommitment, "SAFE_STRUCTURE_CHANGED");
        require(_pendingTreasuryRecipient(cfg.splitter) == address(0), "TREASURY_ROTATION_PENDING");
        delete restorationExecutableAt[subjectId];
        delete restorationPolicyCommitment[subjectId];
        cfg.lifecycle = Lifecycle.Active;
        emit SubjectRestored(subjectId, msg.sender, policyCommitment);
    }

    // slither-disable-next-line timestamp
    function cancelRestoration(bytes32 subjectId) external override {
        require(msg.sender == guardian, "ONLY_GUARDIAN");
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        require(cfg.lifecycle == Lifecycle.Quarantined, "SUBJECT_NOT_QUARANTINED");
        require(restorationExecutableAt[subjectId] != 0, "NO_RESTORATION_PENDING");
        bytes32 policyCommitment = restorationPolicyCommitment[subjectId];
        delete restorationExecutableAt[subjectId];
        delete restorationPolicyCommitment[subjectId];
        emit RestorationCancelled(subjectId, msg.sender, policyCommitment);
    }

    function retireSubject(bytes32 subjectId) external override {
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        require(msg.sender == cfg.strategy, "ONLY_STRATEGY");
        require(cfg.lifecycle == Lifecycle.Active, "SUBJECT_NOT_ACTIVE");
        cfg.lifecycle = Lifecycle.Retired;
        emit SubjectRetired(subjectId, msg.sender);
    }

    function getSubject(bytes32 subjectId) external view override returns (SubjectConfig memory) {
        return _subject(subjectId);
    }

    function lifecycleOf(bytes32 subjectId) external view override returns (Lifecycle) {
        return _subjectStorage(subjectId).lifecycle;
    }

    function splitterOfSubject(bytes32 subjectId) external view override returns (address) {
        return _subjectStorage(subjectId).splitter;
    }

    function canRegisterSubject(address account) public view override returns (bool) {
        return account == controller;
    }

    function subjectCountForStakeToken(address stakeToken)
        external
        view
        override
        returns (uint256)
    {
        return subjectsByStakeToken[stakeToken].length;
    }

    function subjectForStakeTokenAt(address stakeToken, uint256 index)
        external
        view
        override
        returns (bytes32)
    {
        return subjectsByStakeToken[stakeToken][index];
    }

    function subjectsForStakeToken(address stakeToken)
        external
        view
        override
        returns (bytes32[] memory)
    {
        return subjectsByStakeToken[stakeToken];
    }

    function identityLinkCount(bytes32 subjectId) external view returns (uint256) {
        return _subjectStorage(subjectId).identityRegistry == address(0) ? 0 : 1;
    }

    function identityLinkAt(bytes32 subjectId, uint256 index)
        external
        view
        returns (IdentityLink memory)
    {
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        require(index == 0 && cfg.identityRegistry != address(0), "IDENTITY_INDEX_OOB");
        return IdentityLink({
            chainId: cfg.identityChainId,
            registry: cfg.identityRegistry,
            agentId: cfg.identityAgentId
        });
    }

    function subjectForIdentity(uint256 chainId, address registry, uint256 agentId)
        external
        view
        returns (bytes32)
    {
        return subjectOfIdentityHash[_identityHash(chainId, registry, agentId)];
    }

    // Legacy authority and mutation selectors remain present only to fail before side effects.
    function authorizedRegistrars(address) external pure returns (bool) {
        return false;
    }

    function subjectManagers(bytes32, address) external pure returns (bool) {
        return false;
    }

    function canManageSubject(bytes32, address) external pure returns (bool) {
        return false;
    }

    function setAuthorizedRegistrar(address, bool) external pure {
        revert("LEGACY_AUTHORITY_DISABLED");
    }

    function setCanonicalSubjectForStakeToken(address, bytes32) external pure {
        revert("CANONICAL_REASSIGNMENT_DISABLED");
    }

    function setSubjectLifecycleAuthority(bytes32, address) external pure {
        revert("LEGACY_AUTHORITY_DISABLED");
    }

    function markSubjectDead(bytes32) external pure {
        revert("LEGACY_DEATH_DISABLED");
    }

    function createSubject(bytes32, address, address, address, bool, string calldata)
        external
        pure
    {
        revert("LEGACY_REGISTRATION_DISABLED");
    }

    function createPermissionlessSubject(
        bytes32,
        address,
        address,
        address,
        address,
        bool,
        string calldata
    ) external pure {
        revert("PERMISSIONLESS_REGISTRATION_DISABLED");
    }

    function updateSubject(bytes32, address, address, bool, string calldata) external pure {
        revert("SUBJECT_IMMUTABLE");
    }

    function setSubjectManager(bytes32, address, bool) external pure {
        revert("LEGACY_AUTHORITY_DISABLED");
    }

    function setSubjectLabel(bytes32, string calldata) external pure {
        revert("SUBJECT_IMMUTABLE");
    }

    function linkIdentity(bytes32, uint256, address, uint256) external pure returns (bytes32) {
        revert("POST_REGISTRATION_LINK_DISABLED");
    }

    function unlinkIdentity(bytes32, uint256, address, uint256) external pure {
        revert("POST_REGISTRATION_LINK_DISABLED");
    }

    function _validateIdentity(SubjectRegistration calldata registration) internal pure {
        bool hasIdentity = registration.identityChainId != 0
            || registration.identityRegistry != address(0) || registration.identityAgentId != 0;
        if (!hasIdentity) return;
        require(registration.identityChainId != 0, "IDENTITY_CHAIN_ID_ZERO");
        require(registration.identityRegistry != address(0), "IDENTITY_REGISTRY_ZERO");
    }

    function _subject(bytes32 subjectId) internal view returns (SubjectConfig memory) {
        SubjectConfig memory cfg = subjects[subjectId];
        require(cfg.stakeToken != address(0), "SUBJECT_NOT_FOUND");
        return cfg;
    }

    function _subjectStorage(bytes32 subjectId) internal view returns (SubjectConfig storage cfg) {
        cfg = subjects[subjectId];
        require(cfg.stakeToken != address(0), "SUBJECT_NOT_FOUND");
    }

    function _pendingTreasuryRecipient(address splitter) private view returns (address) {
        return ISubjectSplitterRotation(splitter).pendingTreasuryRecipient();
    }

    function _identityHash(uint256 chainId, address registry, uint256 agentId)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(chainId, registry, agentId));
    }
}
