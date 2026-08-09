// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/shared/auth/Owned.sol";
import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";

interface IRevenueShareSplitterV2Deployer {
    function deploy(
        address stakeToken,
        address usdc,
        address ingressFactory,
        address subjectRegistry,
        bytes32 subjectId,
        address treasuryRecipient,
        address stakingRevenueRouter,
        uint256 revenueShareSupplyDenominator,
        string calldata label,
        address owner
    ) external returns (address splitter);
}

contract RevenueShareFactory is Owned {
    address internal constant SPLITTER_RESERVED = address(1);

    error UsdcZero();
    error RegistryZero();
    error StakingRevenueRouterZero();
    error SplitterDeployerZero();
    error StakingRevenueRouterUsdcMismatch();
    error OnlyController();
    error AccountZero();
    error SubjectZero();
    error StakeTokenZero();
    error IngressFactoryZero();
    error AgentSafeZero();
    error StakingRevenueRouterMismatch();
    error SplitterExistsForToken();
    error SplitterExistsForSubject();
    error SupplyDenominatorZero();
    error IdentityChainIdZero();
    error IdentityRegistryZero();
    error IdentityAgentIdZero();
    error IdentityLinkFailed();
    error Reentrant();

    address public immutable usdc;
    address public immutable stakingRevenueRouter;
    address public immutable splitterDeployer;
    address public immutable controller;
    SubjectRegistry public immutable subjectRegistry;

    mapping(address => address) public splitterOfStakeToken;
    mapping(bytes32 => address) public splitterOfSubject;
    uint256 private _createLock = 1;

    struct SubjectSplitterParams {
        bytes32 subjectId;
        address stakeToken;
        address ingressFactory;
        address agentSafe;
        address configuredStakingRevenueRouter;
        uint256 revenueShareSupplyDenominator;
        string label;
        uint256 identityChainId;
        address identityRegistry;
        uint256 identityAgentId;
    }

    event SplitterDeployed(
        bytes32 indexed subjectId,
        address indexed stakeToken,
        address indexed splitter,
        address splitterOwner,
        address treasuryRecipient,
        address stakingRevenueRouter,
        string label
    );

    constructor(
        address owner_,
        address usdc_,
        SubjectRegistry subjectRegistry_,
        address stakingRevenueRouter_,
        address splitterDeployer_
    ) Owned(owner_) {
        if (usdc_ == address(0)) revert UsdcZero();
        if (address(subjectRegistry_) == address(0)) revert RegistryZero();
        if (stakingRevenueRouter_ == address(0)) revert StakingRevenueRouterZero();
        if (splitterDeployer_ == address(0)) revert SplitterDeployerZero();
        if (IRegentStakingRevenueRouter(stakingRevenueRouter_).usdc() != usdc_) {
            revert StakingRevenueRouterUsdcMismatch();
        }
        usdc = usdc_;
        stakingRevenueRouter = stakingRevenueRouter_;
        splitterDeployer = splitterDeployer_;
        subjectRegistry = subjectRegistry_;
        controller = subjectRegistry_.controller();
    }

    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController();
        _;
    }

    modifier nonReentrantCreate() {
        if (_createLock != 1) revert Reentrant();
        _createLock = 2;
        _;
        _createLock = 1;
    }

    function authorizedCreators(address account) external view returns (bool) {
        return account == controller;
    }

    function setAuthorizedCreator(address, bool) external pure {
        revert OnlyController();
    }

    // Reviewed in slither.db.json: nonReentrantCreate protects bound deployer callbacks.
    // slither-disable-next-line reentrancy-events,reentrancy-no-eth
    function createSubjectSplitter(
        bytes32 subjectId,
        address stakeToken,
        address ingressFactory,
        address agentSafe,
        address configuredStakingRevenueRouter,
        uint256 revenueShareSupplyDenominator,
        string calldata label,
        uint256 identityChainId,
        address identityRegistry,
        uint256 identityAgentId
    ) external onlyController nonReentrantCreate returns (address splitter) {
        SubjectSplitterParams memory params = SubjectSplitterParams({
            subjectId: subjectId,
            stakeToken: stakeToken,
            ingressFactory: ingressFactory,
            agentSafe: agentSafe,
            configuredStakingRevenueRouter: configuredStakingRevenueRouter,
            revenueShareSupplyDenominator: revenueShareSupplyDenominator,
            label: label,
            identityChainId: identityChainId,
            identityRegistry: identityRegistry,
            identityAgentId: identityAgentId
        });

        _validateSubjectSplitterParams(params);
        _reserveSubjectSplitter(params);
        splitter = _deploySubjectSplitter(params);
        _publishSubjectSplitter(params, splitter);
    }

    function _validateSubjectSplitterParams(SubjectSplitterParams memory params) internal view {
        if (params.subjectId == bytes32(0)) revert SubjectZero();
        if (params.stakeToken == address(0)) revert StakeTokenZero();
        if (params.ingressFactory == address(0)) revert IngressFactoryZero();
        if (params.agentSafe == address(0)) revert AgentSafeZero();
        if (params.configuredStakingRevenueRouter != stakingRevenueRouter) {
            revert StakingRevenueRouterMismatch();
        }
        if (splitterOfStakeToken[params.stakeToken] != address(0)) revert SplitterExistsForToken();
        if (splitterOfSubject[params.subjectId] != address(0)) revert SplitterExistsForSubject();
        if (params.revenueShareSupplyDenominator == 0) revert SupplyDenominatorZero();
        if (_hasIdentityLink(params)) _validateIdentityLink(params);
    }

    function _hasIdentityLink(SubjectSplitterParams memory params) internal pure returns (bool) {
        return params.identityChainId != 0 || params.identityRegistry != address(0)
            || params.identityAgentId != 0;
    }

    function _validateIdentityLink(SubjectSplitterParams memory params) internal pure {
        if (params.identityChainId == 0) revert IdentityChainIdZero();
        if (params.identityRegistry == address(0)) revert IdentityRegistryZero();
    }

    function _deploySubjectSplitter(SubjectSplitterParams memory params)
        internal
        returns (address splitter)
    {
        splitter = IRevenueShareSplitterV2Deployer(splitterDeployer)
            .deploy(
                params.stakeToken,
                usdc,
                params.ingressFactory,
                address(subjectRegistry),
                params.subjectId,
                params.agentSafe,
                stakingRevenueRouter,
                params.revenueShareSupplyDenominator,
                params.label,
                params.agentSafe
            );
    }

    function _reserveSubjectSplitter(SubjectSplitterParams memory params) internal {
        splitterOfStakeToken[params.stakeToken] = SPLITTER_RESERVED;
        splitterOfSubject[params.subjectId] = SPLITTER_RESERVED;
    }

    function _publishSubjectSplitter(SubjectSplitterParams memory params, address splitter)
        internal
    {
        splitterOfStakeToken[params.stakeToken] = splitter;
        splitterOfSubject[params.subjectId] = splitter;
        emit SplitterDeployed(
            params.subjectId,
            params.stakeToken,
            splitter,
            params.agentSafe,
            params.agentSafe,
            stakingRevenueRouter,
            params.label
        );
    }
}
