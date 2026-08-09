// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";

contract RevertingLifecycleTarget {
    address public constant operator = address(0x7007);

    fallback() external {
        revert("NO_CALLBACK_ALLOWED");
    }
}

contract StrategyOperatorTarget {
    address public immutable operator;

    constructor(address operator_) {
        operator = operator_;
    }
}

contract RevertingOperatorTarget {
    function operator() external pure returns (address) {
        revert("OPERATOR_REVERT");
    }
}

contract MalformedOperatorTarget {
    fallback() external {
        assembly {
            mstore(0, 0x7007)
            return(0, 1)
        }
    }
}

contract MissingOperatorTarget {}

contract SubjectRegistryTest is Test {
    address internal constant GOVERNANCE = address(0xA11CE);
    address internal constant GUARDIAN = address(0x600D);
    address internal constant AGENT_SAFE = address(0x1111);
    address internal constant SAFE_RUNTIME = address(0x7007);
    bytes32 internal constant SUBJECT_ID = keccak256("subject");
    address internal constant TOKEN = address(0xBEEF);

    SubjectRegistry internal registry;
    address internal strategy;

    function setUp() external {
        strategy = address(new StrategyOperatorTarget(SAFE_RUNTIME));
        registry = new SubjectRegistry(address(this), GOVERNANCE, GUARDIAN);
        registry.registerSubject(_registration(SUBJECT_ID, TOKEN, strategy));
    }

    function testControllerRegistersCompleteImmutableBundleDirectly() external view {
        ISubjectRegistry.SubjectConfig memory cfg = registry.getSubject(SUBJECT_ID);
        assertEq(cfg.stakeToken, TOKEN);
        assertEq(cfg.splitter, address(0x1001));
        assertEq(cfg.treasurySafe, AGENT_SAFE);
        assertEq(cfg.ingress, address(0x1002));
        assertEq(cfg.paymentLinkFactory, address(0x1003));
        assertEq(cfg.strategy, strategy);
        assertEq(cfg.launchFeeRegistry, address(0x1004));
        assertEq(cfg.feeVault, address(0x1005));
        assertEq(cfg.feeHook, address(0x1006));
        assertEq(cfg.safeRuntime, SAFE_RUNTIME);
        assertEq(uint256(cfg.lifecycle), uint256(ISubjectRegistry.Lifecycle.Active));
        assertEq(registry.subjectOfStakeToken(TOKEN), SUBJECT_ID);
        assertEq(
            registry.subjectForIdentity(8453, address(0x8004), uint256(uint160(TOKEN))), SUBJECT_ID
        );
    }

    function testOnlyBoundControllerCanRegister() external {
        vm.prank(GOVERNANCE);
        vm.expectRevert("ONLY_CONTROLLER");
        registry.registerSubject(_registration(keccak256("other"), address(0xCAFE), strategy));
    }

    function testRegistrationRejectsOverlappingAuthorityRoles() external {
        ISubjectRegistry.SubjectRegistration memory registration =
            _registration(keccak256("role-overlap"), address(0xCAFE), strategy);

        registration.agentSafe = address(this);
        vm.expectRevert("AGENT_SAFE_IS_CONTROLLER");
        registry.registerSubject(registration);

        registration.agentSafe = GOVERNANCE;
        vm.expectRevert("AGENT_SAFE_IS_GOVERNANCE");
        registry.registerSubject(registration);

        registration.agentSafe = GUARDIAN;
        vm.expectRevert("AGENT_SAFE_IS_GUARDIAN");
        registry.registerSubject(registration);

        registration.agentSafe = AGENT_SAFE;
        registration.strategy = address(this);
        vm.expectRevert("STRATEGY_IS_CONTROLLER");
        registry.registerSubject(registration);

        registration.strategy = GOVERNANCE;
        vm.expectRevert("STRATEGY_IS_GOVERNANCE");
        registry.registerSubject(registration);

        registration.strategy = GUARDIAN;
        vm.expectRevert("STRATEGY_IS_GUARDIAN");
        registry.registerSubject(registration);

        registration.strategy = AGENT_SAFE;
        vm.expectRevert("STRATEGY_IS_AGENT_SAFE");
        registry.registerSubject(registration);
    }

    function testRegistrationIsExactlyOnceAndTokenUnique() external {
        vm.expectRevert("SUBJECT_EXISTS");
        registry.registerSubject(_registration(SUBJECT_ID, address(0xCAFE), strategy));

        vm.expectRevert("STAKE_TOKEN_ALREADY_LINKED");
        registry.registerSubject(_registration(keccak256("other"), TOKEN, strategy));
    }

    function testRegistrationRejectsZeroSafeRuntime() external {
        ISubjectRegistry.SubjectRegistration memory registration =
            _registration(keccak256("zero-runtime"), address(0xCAFE), strategy);
        registration.safeRuntime = address(0);

        vm.expectRevert("SAFE_RUNTIME_ZERO");
        registry.registerSubject(registration);
    }

    function testRegistrationRejectsUnsafeSafeRuntime() external {
        ISubjectRegistry.SubjectRegistration memory registration =
            _registration(keccak256("unsafe-runtime"), address(0xCAFE), strategy);

        registration.safeRuntime = address(this);
        vm.expectRevert("SAFE_RUNTIME_IS_CONTROLLER");
        registry.registerSubject(registration);

        registration.safeRuntime = GOVERNANCE;
        vm.expectRevert("SAFE_RUNTIME_IS_GOVERNANCE");
        registry.registerSubject(registration);

        registration.safeRuntime = GUARDIAN;
        vm.expectRevert("SAFE_RUNTIME_IS_GUARDIAN");
        registry.registerSubject(registration);

        registration.safeRuntime = AGENT_SAFE;
        vm.expectRevert("SAFE_RUNTIME_IS_AGENT_SAFE");
        registry.registerSubject(registration);

        registration.safeRuntime = strategy;
        vm.expectRevert("SAFE_RUNTIME_IS_STRATEGY");
        registry.registerSubject(registration);

        registration.safeRuntime = address(0xBAD);
        vm.expectRevert("SAFE_RUNTIME_OPERATOR_MISMATCH");
        registry.registerSubject(registration);
    }

    function testRegistrationFailsClosedWhenStrategyOperatorReverts() external {
        ISubjectRegistry.SubjectRegistration memory registration = _registration(
            keccak256("reverting-operator"), address(0xCA10), address(new RevertingOperatorTarget())
        );

        vm.expectRevert("OPERATOR_REVERT");
        registry.registerSubject(registration);

        _assertRegistrationFailureLeavesNoResidue(registration);
    }

    function testRegistrationFailsClosedWhenStrategyOperatorReturnsMalformedData() external {
        ISubjectRegistry.SubjectRegistration memory registration = _registration(
            keccak256("malformed-operator"), address(0xCA11), address(new MalformedOperatorTarget())
        );

        vm.expectRevert();
        registry.registerSubject(registration);

        _assertRegistrationFailureLeavesNoResidue(registration);
    }

    function testRegistrationFailsClosedWhenStrategyOperatorSelectorIsMissing() external {
        ISubjectRegistry.SubjectRegistration memory registration = _registration(
            keccak256("missing-operator"), address(0xCA12), address(new MissingOperatorTarget())
        );

        vm.expectRevert();
        registry.registerSubject(registration);

        _assertRegistrationFailureLeavesNoResidue(registration);
    }

    function testAgentSafeGovernanceAndGuardianCanQuarantine() external {
        vm.prank(AGENT_SAFE);
        registry.quarantineSubject(SUBJECT_ID);
        assertEq(
            uint256(registry.lifecycleOf(SUBJECT_ID)),
            uint256(ISubjectRegistry.Lifecycle.Quarantined)
        );

        bytes32 governanceSubject = keccak256("governance");
        registry.registerSubject(_registration(governanceSubject, address(0xCA01), strategy));
        vm.prank(GOVERNANCE);
        registry.quarantineSubject(governanceSubject);

        bytes32 guardianSubject = keccak256("guardian");
        registry.registerSubject(_registration(guardianSubject, address(0xCA02), strategy));
        vm.prank(GUARDIAN);
        registry.quarantineSubject(guardianSubject);
    }

    function testUnauthorizedCallerCannotQuarantine() external {
        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_QUARANTINE_AUTHORITY");
        registry.quarantineSubject(SUBJECT_ID);
    }

    function testOnlyAgentSafeMayRequestRestoration() external {
        vm.prank(GUARDIAN);
        registry.quarantineSubject(SUBJECT_ID);
        vm.prank(GOVERNANCE);
        vm.expectRevert("ONLY_AGENT_SAFE");
        registry.requestRestoration(SUBJECT_ID);
    }

    function testGuardianCannotExecuteRestoration() external {
        vm.prank(GUARDIAN);
        vm.expectRevert("ONLY_GOVERNANCE");
        registry.executeRestoration(SUBJECT_ID);
    }

    function testStrategyRetirementIsNarrowAndTerminal() external {
        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_STRATEGY");
        registry.retireSubject(SUBJECT_ID);
        vm.prank(strategy);
        registry.retireSubject(SUBJECT_ID);
        assertEq(
            uint256(registry.lifecycleOf(SUBJECT_ID)), uint256(ISubjectRegistry.Lifecycle.Retired)
        );
        vm.prank(AGENT_SAFE);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        registry.quarantineSubject(SUBJECT_ID);
        vm.prank(strategy);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        registry.retireSubject(SUBJECT_ID);
    }

    function testQuarantineBlocksRetirement() external {
        vm.prank(GUARDIAN);
        registry.quarantineSubject(SUBJECT_ID);
        vm.prank(strategy);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        registry.retireSubject(SUBJECT_ID);
    }

    function testLegacyRegistrationAuthorityAndDeathSelectorsAreDisabled() external {
        vm.expectRevert("LEGACY_AUTHORITY_DISABLED");
        registry.setAuthorizedRegistrar(address(this), true);
        vm.expectRevert("LEGACY_AUTHORITY_DISABLED");
        registry.setSubjectLifecycleAuthority(SUBJECT_ID, strategy);
        vm.expectRevert("LEGACY_DEATH_DISABLED");
        registry.markSubjectDead(SUBJECT_ID);
        vm.expectRevert("PERMISSIONLESS_REGISTRATION_DISABLED");
        registry.createPermissionlessSubject(
            keccak256("legacy"), address(1), address(2), address(3), address(4), true, "legacy"
        );
    }

    function testRedirectReplacementAndPostRegistrationLinkingAreDisabled() external {
        vm.expectRevert("SUBJECT_IMMUTABLE");
        registry.updateSubject(SUBJECT_ID, address(9), address(8), false, "redirect");
        vm.expectRevert("CANONICAL_REASSIGNMENT_DISABLED");
        registry.setCanonicalSubjectForStakeToken(TOKEN, keccak256("redirect"));
        vm.expectRevert("POST_REGISTRATION_LINK_DISABLED");
        registry.linkIdentity(SUBJECT_ID, 1, address(2), 3);
    }

    function testLifecycleTransitionsDoNotCallSubjectContracts() external {
        RevertingLifecycleTarget target = new RevertingLifecycleTarget();
        bytes32 id = keccak256("no-callback");
        ISubjectRegistry.SubjectRegistration memory registration =
            _registration(id, address(0xCA03), address(target));
        registration.splitter = address(target);
        registration.ingress = address(target);
        registry.registerSubject(registration);
        vm.prank(GUARDIAN);
        registry.quarantineSubject(id);
    }

    function _assertRegistrationFailureLeavesNoResidue(
        ISubjectRegistry.SubjectRegistration memory registration
    ) internal {
        vm.expectRevert("SUBJECT_NOT_FOUND");
        registry.getSubject(registration.subjectId);
        assertEq(registry.subjectOfStakeToken(registration.stakeToken), bytes32(0));
        assertEq(registry.subjectCountForStakeToken(registration.stakeToken), 0);
        assertEq(
            registry.subjectForIdentity(
                registration.identityChainId,
                registration.identityRegistry,
                registration.identityAgentId
            ),
            bytes32(0)
        );
    }

    function _registration(bytes32 id, address token, address strategy_)
        internal
        pure
        returns (ISubjectRegistry.SubjectRegistration memory)
    {
        return ISubjectRegistry.SubjectRegistration({
            subjectId: id,
            stakeToken: token,
            splitter: address(0x1001),
            agentSafe: AGENT_SAFE,
            ingress: address(0x1002),
            paymentLinkFactory: address(0x1003),
            strategy: strategy_,
            launchFeeRegistry: address(0x1004),
            feeVault: address(0x1005),
            feeHook: address(0x1006),
            identityChainId: 8453,
            identityRegistry: address(0x8004),
            identityAgentId: uint256(uint160(token)),
            label: "Atlas",
            safeRuntime: SAFE_RUNTIME
        });
    }
}
