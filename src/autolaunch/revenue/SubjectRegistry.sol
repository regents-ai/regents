// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/shared/auth/Owned.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {ISubjectLifecycleSync} from "src/autolaunch/revenue/interfaces/ISubjectLifecycleSync.sol";
import {InputBounds} from "src/autolaunch/revenue/libraries/InputBounds.sol";

contract SubjectRegistry is Owned, ISubjectRegistry {
    struct IdentityLink {
        uint256 chainId;
        address registry;
        uint256 agentId;
    }

    mapping(bytes32 => SubjectConfig) private subjects;
    mapping(address => bytes32) public override subjectOfStakeToken;
    mapping(address => bytes32[]) private subjectsByStakeToken;
    mapping(address => bool) public authorizedRegistrars;
    mapping(bytes32 => mapping(address => bool)) public subjectManagers;
    mapping(bytes32 => IdentityLink[]) private identityLinks;
    mapping(bytes32 => bytes32) public subjectOfIdentityHash;
    mapping(bytes32 => address) public override subjectLifecycleAuthority;
    mapping(bytes32 => bool) public override subjectDead;

    event SubjectCreated(
        bytes32 indexed subjectId,
        address indexed stakeToken,
        address indexed splitter,
        address treasurySafe,
        string label
    );
    event AuthorizedRegistrarSet(address indexed registrar, bool enabled);
    event CanonicalSubjectForStakeTokenSet(address indexed stakeToken, bytes32 indexed subjectId);
    event PermissionlessSubjectCreated(
        bytes32 indexed subjectId,
        address indexed stakeToken,
        address indexed splitter,
        address treasurySafe,
        address creator,
        string label
    );
    event SubjectUpdated(
        bytes32 indexed subjectId,
        address indexed splitter,
        address treasurySafe,
        bool active,
        string label
    );
    event SubjectManagerSet(bytes32 indexed subjectId, address indexed account, bool enabled);
    event ClaimedIdentityLinked(
        bytes32 indexed subjectId,
        bytes32 indexed identityHash,
        uint256 chainId,
        address indexed registry,
        uint256 agentId
    );
    event ClaimedIdentityUnlinked(
        bytes32 indexed subjectId,
        bytes32 indexed identityHash,
        uint256 chainId,
        address indexed registry,
        uint256 agentId
    );
    event SubjectLifecycleAuthoritySet(bytes32 indexed subjectId, address indexed authority);
    event SubjectMarkedDead(
        bytes32 indexed subjectId, address indexed splitter, address indexed caller
    );

    constructor(address owner_) Owned(owner_) {}

    modifier onlyRegistrar() {
        require(canRegisterSubject(msg.sender), "ONLY_REGISTRAR");
        _;
    }

    modifier onlySubjectManager(bytes32 subjectId) {
        require(canManageSubject(subjectId, msg.sender), "ONLY_SUBJECT_MANAGER");
        _;
    }

    modifier onlySubjectController(bytes32 subjectId) {
        require(_canControlSubject(subjectId, msg.sender), "ONLY_SUBJECT_CONTROLLER");
        _;
    }

    function createSubject(
        bytes32 subjectId,
        address stakeToken,
        address splitter,
        address treasurySafe,
        bool active,
        string calldata label
    ) external override onlyRegistrar {
        require(subjectId != bytes32(0), "SUBJECT_ZERO");
        require(stakeToken != address(0), "STAKE_TOKEN_ZERO");
        require(splitter != address(0), "SPLITTER_ZERO");
        require(treasurySafe != address(0), "TREASURY_SAFE_ZERO");
        require(subjects[subjectId].stakeToken == address(0), "SUBJECT_EXISTS");
        require(subjectOfStakeToken[stakeToken] == bytes32(0), "STAKE_TOKEN_ALREADY_LINKED");
        InputBounds.requireStringMax(label, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");

        subjects[subjectId] = SubjectConfig({
            stakeToken: stakeToken,
            splitter: splitter,
            treasurySafe: treasurySafe,
            active: active,
            label: label
        });
        subjectOfStakeToken[stakeToken] = subjectId;
        subjectsByStakeToken[stakeToken].push(subjectId);
        subjectManagers[subjectId][treasurySafe] = true;
        subjectManagers[subjectId][msg.sender] = true;

        emit SubjectCreated(subjectId, stakeToken, splitter, treasurySafe, label);
        emit SubjectManagerSet(subjectId, treasurySafe, true);
        emit SubjectManagerSet(subjectId, msg.sender, true);
    }

    function createPermissionlessSubject(
        bytes32 subjectId,
        address stakeToken,
        address splitter,
        address treasurySafe,
        address creator,
        bool active,
        string calldata label
    ) external override onlyRegistrar {
        require(subjectId != bytes32(0), "SUBJECT_ZERO");
        require(stakeToken != address(0), "STAKE_TOKEN_ZERO");
        require(splitter != address(0), "SPLITTER_ZERO");
        require(treasurySafe != address(0), "TREASURY_SAFE_ZERO");
        require(creator != address(0), "CREATOR_ZERO");
        require(subjects[subjectId].stakeToken == address(0), "SUBJECT_EXISTS");
        InputBounds.requireStringMax(label, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");

        subjects[subjectId] = SubjectConfig({
            stakeToken: stakeToken,
            splitter: splitter,
            treasurySafe: treasurySafe,
            active: active,
            label: label
        });

        subjectsByStakeToken[stakeToken].push(subjectId);

        subjectManagers[subjectId][treasurySafe] = true;
        subjectManagers[subjectId][creator] = true;

        emit PermissionlessSubjectCreated(
            subjectId, stakeToken, splitter, treasurySafe, creator, label
        );
        emit SubjectManagerSet(subjectId, treasurySafe, true);
        emit SubjectManagerSet(subjectId, creator, true);
    }

    function setAuthorizedRegistrar(address registrar, bool enabled) external onlyOwner {
        require(registrar != address(0), "REGISTRAR_ZERO");
        authorizedRegistrars[registrar] = enabled;
        emit AuthorizedRegistrarSet(registrar, enabled);
    }

    function setCanonicalSubjectForStakeToken(address stakeToken, bytes32 subjectId)
        external
        override
        onlyOwner
    {
        require(stakeToken != address(0), "STAKE_TOKEN_ZERO");
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        require(cfg.stakeToken == stakeToken, "STAKE_TOKEN_MISMATCH");

        subjectOfStakeToken[stakeToken] = subjectId;
        emit CanonicalSubjectForStakeTokenSet(stakeToken, subjectId);
    }

    /// @notice Binds the one address (besides the owner) allowed to mark this subject dead.
    /// @dev Registrar-gated and set-once: for CCA launches the deployment controller binds the
    ///      launch's RegentLBPStrategy here (via RevenueShareFactory) so a failed auction can
    ///      kill its own subject atomically inside `recoverFailedAuction`.
    function setSubjectLifecycleAuthority(bytes32 subjectId, address authority)
        external
        override
        onlyRegistrar
    {
        _subjectStorage(subjectId);
        require(authority != address(0), "AUTHORITY_ZERO");
        require(subjectLifecycleAuthority[subjectId] == address(0), "AUTHORITY_SET");
        require(!subjectDead[subjectId], "SUBJECT_DEAD");

        subjectLifecycleAuthority[subjectId] = authority;
        emit SubjectLifecycleAuthoritySet(subjectId, authority);
    }

    /// @notice Permanently kills a subject: deactivates it, retires its splitter, and blocks
    ///         every future reactivation path. Used for failed launches — the subject must
    ///         never be stakeable, depositable, or mistaken for a live market again.
    function markSubjectDead(bytes32 subjectId) external override {
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        require(
            msg.sender == subjectLifecycleAuthority[subjectId] || msg.sender == owner,
            "ONLY_LIFECYCLE_AUTHORITY"
        );
        require(!subjectDead[subjectId], "SUBJECT_DEAD");

        subjectDead[subjectId] = true;
        cfg.active = false;
        // retiring=true permanently latches `subjectLifecycleRetired` on the splitter, so the
        // splitter stays disabled even independently of this registry flag.
        ISubjectLifecycleSync(cfg.splitter).syncSubjectLifecycle(false, true);

        emit SubjectMarkedDead(subjectId, cfg.splitter, msg.sender);
    }

    function updateSubject(
        bytes32 subjectId,
        address splitter,
        address treasurySafe,
        bool active,
        string calldata label
    ) external onlySubjectController(subjectId) {
        require(!subjectDead[subjectId], "SUBJECT_DEAD");
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        address previousSplitter = cfg.splitter;
        require(splitter != address(0), "SPLITTER_ZERO");
        require(treasurySafe != address(0), "TREASURY_SAFE_ZERO");
        InputBounds.requireStringMax(label, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");
        bool splitterChanged = previousSplitter != splitter;
        bool activeChanged = cfg.active != active;

        if (cfg.treasurySafe != treasurySafe) {
            subjectManagers[subjectId][cfg.treasurySafe] = false;
            emit SubjectManagerSet(subjectId, cfg.treasurySafe, false);
            subjectManagers[subjectId][treasurySafe] = true;
            emit SubjectManagerSet(subjectId, treasurySafe, true);
        }

        if (activeChanged || splitterChanged) {
            ISubjectLifecycleSync(previousSplitter).syncSubjectLifecycle(active, splitterChanged);
        }
        if (splitterChanged) {
            ISubjectLifecycleSync(splitter).syncSubjectLifecycle(active, false);
        }

        cfg.active = active;
        cfg.splitter = splitter;
        cfg.treasurySafe = treasurySafe;
        cfg.label = label;

        emit SubjectUpdated(subjectId, splitter, treasurySafe, active, label);
    }

    function setSubjectManager(bytes32 subjectId, address account, bool enabled)
        external
        onlySubjectController(subjectId)
    {
        require(account != address(0), "ACCOUNT_ZERO");
        subjectManagers[subjectId][account] = enabled;
        emit SubjectManagerSet(subjectId, account, enabled);
    }

    function setSubjectLabel(bytes32 subjectId, string calldata label)
        external
        onlySubjectManager(subjectId)
    {
        SubjectConfig storage cfg = _subjectStorage(subjectId);
        InputBounds.requireStringMax(label, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");
        cfg.label = label;
        emit SubjectUpdated(subjectId, cfg.splitter, cfg.treasurySafe, cfg.active, label);
    }

    function linkIdentity(bytes32 subjectId, uint256 chainId, address registry, uint256 agentId)
        external
        onlySubjectManager(subjectId)
        returns (bytes32 identityHash)
    {
        require(chainId != 0, "CHAIN_ID_ZERO");
        require(registry != address(0), "REGISTRY_ZERO");
        require(agentId != 0, "AGENT_ID_ZERO");
        _subjectStorage(subjectId);

        identityHash = _identityHash(chainId, registry, agentId);
        bytes32 previous = subjectOfIdentityHash[identityHash];
        require(previous == bytes32(0) || previous == subjectId, "IDENTITY_LINKED_TO_OTHER_SUBJECT");

        if (previous == bytes32(0)) {
            subjectOfIdentityHash[identityHash] = subjectId;
            identityLinks[subjectId].push(
                IdentityLink({chainId: chainId, registry: registry, agentId: agentId})
            );
            emit ClaimedIdentityLinked(subjectId, identityHash, chainId, registry, agentId);
        }
    }

    function unlinkIdentity(bytes32 subjectId, uint256 chainId, address registry, uint256 agentId)
        external
        onlySubjectManager(subjectId)
    {
        _subjectStorage(subjectId);
        bytes32 identityHash = _identityHash(chainId, registry, agentId);
        require(subjectOfIdentityHash[identityHash] == subjectId, "IDENTITY_NOT_LINKED");

        delete subjectOfIdentityHash[identityHash];

        IdentityLink[] storage links = identityLinks[subjectId];
        uint256 length = links.length;
        for (uint256 i; i < length; ++i) {
            IdentityLink memory link = links[i];
            if (link.chainId == chainId && link.registry == registry && link.agentId == agentId) {
                uint256 last = length - 1;
                if (i != last) {
                    links[i] = links[last];
                }
                links.pop();
                emit ClaimedIdentityUnlinked(subjectId, identityHash, chainId, registry, agentId);
                return;
            }
        }

        revert("IDENTITY_NOT_FOUND");
    }

    function getSubject(bytes32 subjectId) external view override returns (SubjectConfig memory) {
        return _subject(subjectId);
    }

    function splitterOfSubject(bytes32 subjectId) external view override returns (address) {
        return _subject(subjectId).splitter;
    }

    function isSubjectActive(bytes32 subjectId) external view override returns (bool) {
        SubjectConfig storage cfg = subjects[subjectId];
        return cfg.stakeToken != address(0) && cfg.active;
    }

    function canManageSubject(bytes32 subjectId, address account)
        public
        view
        override
        returns (bool)
    {
        SubjectConfig storage cfg = subjects[subjectId];
        if (cfg.stakeToken == address(0)) {
            return false;
        }

        return
            account == owner || subjectManagers[subjectId][account] || account == cfg.treasurySafe;
    }

    function canRegisterSubject(address account) public view override returns (bool) {
        return account == owner || authorizedRegistrars[account];
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
        _subjectStorage(subjectId);
        return identityLinks[subjectId].length;
    }

    function identityLinkAt(bytes32 subjectId, uint256 index)
        external
        view
        returns (IdentityLink memory)
    {
        _subjectStorage(subjectId);
        return identityLinks[subjectId][index];
    }

    function subjectForIdentity(uint256 chainId, address registry, uint256 agentId)
        external
        view
        returns (bytes32)
    {
        return subjectOfIdentityHash[_identityHash(chainId, registry, agentId)];
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

    function _canControlSubject(bytes32 subjectId, address account) internal view returns (bool) {
        SubjectConfig storage cfg = subjects[subjectId];
        if (cfg.stakeToken == address(0)) {
            return false;
        }

        return account == owner || account == cfg.treasurySafe;
    }

    function _identityHash(uint256 chainId, address registry, uint256 agentId)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(chainId, registry, agentId));
    }
}
