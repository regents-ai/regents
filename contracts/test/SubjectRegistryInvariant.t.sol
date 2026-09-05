// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";

contract SubjectRegistryHandler is Test {
    SubjectRegistry public immutable registry;
    bytes32 public immutable subjectId;
    address public immutable agentSafe;
    address public immutable governance;
    address public immutable guardian;
    address public immutable strategy;
    bool public retiredObserved;

    constructor(
        SubjectRegistry registry_,
        bytes32 subjectId_,
        address agentSafe_,
        address governance_,
        address guardian_,
        address strategy_
    ) {
        registry = registry_;
        subjectId = subjectId_;
        agentSafe = agentSafe_;
        governance = governance_;
        guardian = guardian_;
        strategy = strategy_;
    }

    function quarantine(uint8 role) external {
        address caller = role % 3 == 0 ? agentSafe : role % 3 == 1 ? governance : guardian;
        vm.prank(caller);
        try registry.quarantineSubject(subjectId) {} catch {}
        _observeRetirement();
    }

    function requestRestoration() external {
        vm.prank(agentSafe);
        try registry.requestRestoration(subjectId) {} catch {}
        _observeRetirement();
    }

    function cancelRestoration() external {
        vm.prank(guardian);
        try registry.cancelRestoration(subjectId) {} catch {}
        _observeRetirement();
    }

    function executeRestoration(uint32 elapsed) external {
        vm.warp(block.timestamp + bound(elapsed, 0, 2 days));
        vm.prank(governance);
        try registry.executeRestoration(subjectId) {} catch {}
        _observeRetirement();
    }

    function retire() external {
        vm.prank(strategy);
        try registry.retireSubject(subjectId) {} catch {}
        _observeRetirement();
    }

    function _observeRetirement() internal {
        if (registry.lifecycleOf(subjectId) == ISubjectRegistry.Lifecycle.Retired) {
            retiredObserved = true;
        }
    }
}

contract SubjectRegistryInvariant is StdInvariant, Test {
    bytes32 internal constant SUBJECT_ID = keccak256("invariant-subject");
    address internal constant TOKEN = address(0xBEEF);
    address internal constant SAFE = address(0x1111);
    address internal constant GOVERNANCE = address(0x2222);
    address internal constant GUARDIAN = address(0x3333);
    address internal constant STRATEGY = address(0x4444);

    SubjectRegistry internal registry;
    SubjectRegistryHandler internal handler;
    bytes32 internal initialBundleHash;

    function setUp() external {
        registry = new SubjectRegistry(address(this), GOVERNANCE, GUARDIAN);
        vm.mockCall(STRATEGY, abi.encodeWithSignature("operator()"), abi.encode(address(0x7007)));
        registry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: SUBJECT_ID,
                stakeToken: TOKEN,
                splitter: address(0x1001),
                agentSafe: SAFE,
                ingress: address(0x1002),
                paymentLinkFactory: address(0x1003),
                strategy: STRATEGY,
                launchFeeRegistry: address(0x1004),
                feeVault: address(0x1005),
                feeHook: address(0x1006),
                identityChainId: 8453,
                identityRegistry: address(0x8004),
                identityAgentId: 7,
                label: "Invariant",
                safeRuntime: address(0x7007)
            })
        );
        initialBundleHash = _bundleHash();
        handler =
            new SubjectRegistryHandler(registry, SUBJECT_ID, SAFE, GOVERNANCE, GUARDIAN, STRATEGY);
        targetContract(address(handler));
    }

    function invariantRoutingBundleNeverChanges() external view {
        assertEq(_bundleHash(), initialBundleHash);
    }

    function invariantLifecycleIsClosed() external view {
        assertLe(uint256(registry.lifecycleOf(SUBJECT_ID)), 2);
    }

    function invariantRetiredIsTerminal() external view {
        if (handler.retiredObserved()) {
            assertEq(
                uint256(registry.lifecycleOf(SUBJECT_ID)),
                uint256(ISubjectRegistry.Lifecycle.Retired)
            );
        }
    }

    function invariantRolesNeverChange() external view {
        assertEq(registry.controller(), address(this));
        assertEq(registry.governance(), GOVERNANCE);
        assertEq(registry.guardian(), GUARDIAN);
    }

    function _bundleHash() internal view returns (bytes32) {
        ISubjectRegistry.SubjectConfig memory cfg = registry.getSubject(SUBJECT_ID);
        return keccak256(
            abi.encode(
                cfg.stakeToken,
                cfg.splitter,
                cfg.treasurySafe,
                cfg.ingress,
                cfg.paymentLinkFactory,
                cfg.strategy,
                cfg.launchFeeRegistry,
                cfg.feeVault,
                cfg.feeHook,
                cfg.identityChainId,
                cfg.identityRegistry,
                cfg.identityAgentId,
                cfg.label,
                cfg.safeRuntime
            )
        );
    }
}
