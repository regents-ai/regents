// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MockFeeSubjectRegistry} from "test/mocks/MockHookPoolManager.sol";

contract LaunchFeeRegistryTest is Test {
    address internal constant AGENT_SAFE = address(0xA11CE);
    address internal constant SETUP_AUTHORITY = address(0xC0117);
    address internal constant LAUNCH_TOKEN = address(0x1001);
    address internal constant QUOTE_TOKEN = address(0x2002);
    address internal constant POOL_MANAGER = address(0x5005);
    address internal constant HOOK = address(0x6006);
    address internal constant VAULT = address(0x6007);
    address internal constant INITIALIZER = address(0x7007);
    bytes32 internal constant SUBJECT_ID = keccak256("subject");
    uint24 internal constant POOL_FEE = 3000;
    int24 internal constant TICK_SPACING = 60;

    LaunchFeeRegistry internal registry;
    MockFeeSubjectRegistry internal subjectRegistry;

    function setUp() external {
        subjectRegistry = new MockFeeSubjectRegistry();
        registry = new LaunchFeeRegistry(
            AGENT_SAFE, SETUP_AUTHORITY, address(subjectRegistry), SUBJECT_ID, QUOTE_TOKEN
        );
        _setSubject(ISubjectRegistry.Lifecycle.Active, AGENT_SAFE, LAUNCH_TOKEN, INITIALIZER, HOOK);
    }

    function testConstructsDirectlyUnderFinalAgentSafe() external view {
        assertEq(registry.agentSafe(), AGENT_SAFE);
        assertEq(address(registry.subjectRegistry()), address(subjectRegistry));
        assertEq(registry.subjectId(), SUBJECT_ID);
    }

    function testOnlyImmutableAgentSafeCanToggleHookStatus() external {
        vm.prank(SETUP_AUTHORITY);
        bytes32 poolId = registry.registerPool(_registration());

        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_AGENT_SAFE");
        registry.setHookEnabled(poolId, false);

        vm.prank(AGENT_SAFE);
        registry.setHookEnabled(poolId, false);
        assertFalse(registry.getPoolConfig(poolId).hookEnabled);
        assertEq(registry.agentSafe(), AGENT_SAFE);
    }

    function testRegisterPoolStoresOnlyFixedDestinationsAndConsumesSetupAuthority() external {
        vm.prank(SETUP_AUTHORITY);
        bytes32 poolId = registry.registerPool(_registration());
        LaunchFeeRegistry.PoolConfig memory config = registry.getPoolConfig(poolId);

        assertEq(config.launchToken, LAUNCH_TOKEN);
        assertEq(config.quoteToken, QUOTE_TOKEN);
        assertEq(config.poolFee, POOL_FEE);
        assertEq(config.tickSpacing, TICK_SPACING);
        assertEq(config.poolManager, POOL_MANAGER);
        assertEq(config.hook, HOOK);
        assertEq(config.authorizedInitializer, INITIALIZER);
        assertTrue(config.hookEnabled);
        assertEq(registry.treasuryRecipient(poolId), AGENT_SAFE);
        assertEq(registry.regentRecipient(poolId), registry.REGENT_REVENUE_STAKING());
        assertEq(registry.setupAuthority(), address(0));

        vm.prank(SETUP_AUTHORITY);
        vm.expectRevert("ONLY_SETUP_AUTHORITY");
        registry.registerPool(_registration());
    }

    function testRegistrationRequiresExactActiveSubjectTuple() external {
        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_SETUP_AUTHORITY");
        registry.registerPool(_registration());

        _setSubject(
            ISubjectRegistry.Lifecycle.Quarantined, AGENT_SAFE, LAUNCH_TOKEN, INITIALIZER, HOOK
        );
        vm.prank(SETUP_AUTHORITY);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        registry.registerPool(_registration());

        _setSubject(
            ISubjectRegistry.Lifecycle.Active, address(0xBAD), LAUNCH_TOKEN, INITIALIZER, HOOK
        );
        vm.prank(SETUP_AUTHORITY);
        vm.expectRevert("AGENT_SAFE_MISMATCH");
        registry.registerPool(_registration());
    }

    function testRejectsEqualPoolCurrencies() external {
        _setSubject(ISubjectRegistry.Lifecycle.Active, AGENT_SAFE, QUOTE_TOKEN, INITIALIZER, HOOK);
        LaunchFeeRegistry.PoolRegistration memory registration = _registration();
        registration.launchToken = QUOTE_TOKEN;

        vm.prank(SETUP_AUTHORITY);
        vm.expectRevert("POOL_CURRENCIES_EQUAL");
        registry.registerPool(registration);
    }

    function testRejectsNonCanonicalQuoteToken() external {
        LaunchFeeRegistry.PoolRegistration memory registration = _registration();
        registration.quoteToken = address(0xBAD);

        vm.prank(SETUP_AUTHORITY);
        vm.expectRevert("QUOTE_TOKEN_NOT_CANONICAL");
        registry.registerPool(registration);
    }

    function testRejectsZeroAuthorizedInitializer() external {
        _setSubject(ISubjectRegistry.Lifecycle.Active, AGENT_SAFE, LAUNCH_TOKEN, address(0), HOOK);
        LaunchFeeRegistry.PoolRegistration memory registration = _registration();
        registration.authorizedInitializer = address(0);

        vm.prank(SETUP_AUTHORITY);
        vm.expectRevert("INITIALIZER_ZERO");
        registry.registerPool(registration);
    }

    function testQuarantineBlocksReEnableButAgentSafeCanDisable() external {
        vm.prank(SETUP_AUTHORITY);
        bytes32 poolId = registry.registerPool(_registration());

        vm.prank(AGENT_SAFE);
        registry.setHookEnabled(poolId, false);
        assertFalse(registry.getPoolConfig(poolId).hookEnabled);

        subjectRegistry.setLifecycle(SUBJECT_ID, ISubjectRegistry.Lifecycle.Quarantined);
        vm.prank(AGENT_SAFE);
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        registry.setHookEnabled(poolId, true);
    }

    function _registration() internal pure returns (LaunchFeeRegistry.PoolRegistration memory) {
        return LaunchFeeRegistry.PoolRegistration({
            launchToken: LAUNCH_TOKEN,
            quoteToken: QUOTE_TOKEN,
            poolFee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            poolManager: POOL_MANAGER,
            hook: HOOK,
            authorizedInitializer: INITIALIZER
        });
    }

    function _setSubject(
        ISubjectRegistry.Lifecycle lifecycle,
        address agentSafe,
        address launchToken,
        address strategy,
        address hook
    ) internal {
        subjectRegistry.setSubject(
            SUBJECT_ID,
            ISubjectRegistry.SubjectConfig({
                stakeToken: launchToken,
                splitter: address(1),
                treasurySafe: agentSafe,
                ingress: address(2),
                paymentLinkFactory: address(3),
                strategy: strategy,
                launchFeeRegistry: address(registry),
                feeVault: VAULT,
                feeHook: hook,
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                lifecycle: lifecycle,
                label: "subject",
                safeRuntime: address(4)
            })
        );
    }
}
