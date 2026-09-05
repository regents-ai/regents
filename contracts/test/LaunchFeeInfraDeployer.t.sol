// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "src/shared/libraries/HookMiner.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MockFeeSubjectRegistry} from "test/mocks/MockHookPoolManager.sol";

contract LaunchFeeInfraDeployerTest is Test {
    address internal constant AGENT_SAFE = address(0xA11CE);
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant POOL_MANAGER = address(0x5005);
    address internal constant LAUNCH_TOKEN = address(0x1001);
    address internal constant STRATEGY = address(0x7007);
    address internal constant ATTACKER = address(0xBAD);
    bytes32 internal constant SUBJECT_ID = keccak256("subject");
    uint160 internal constant FLAGS = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
        | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    LaunchFeeInfraDeployer internal deployer;
    MockFeeSubjectRegistry internal subjectRegistry;
    LaunchFeeRegistry internal registry;
    LaunchFeeVault internal vault;
    LaunchPoolFeeHook internal hook;

    function setUp() external {
        deployer = new LaunchFeeInfraDeployer(address(this));
        subjectRegistry = new MockFeeSubjectRegistry();
        bytes32 salt = _hookSalt();
        (registry, vault, hook) = deployer.deploy(
            AGENT_SAFE, address(subjectRegistry), SUBJECT_ID, POOL_MANAGER, REGENT, salt
        );
    }

    function testDeploysEveryContractDirectlyUnderFinalAgentSafe() external view {
        assertEq(deployer.authorizedController(), address(this));
        assertEq(registry.agentSafe(), AGENT_SAFE);
        assertEq(hook.feeInfraDeployer(), address(deployer));
        assertEq(vault.hookSetupAuthority(), address(0));
    }

    function testRejectsZeroAuthorizedController() external {
        vm.expectRevert("AUTHORIZED_CONTROLLER_ZERO");
        new LaunchFeeInfraDeployer(address(0));
    }

    function testCurrentSelectorCannotFrontRunAuthorizedController() external {
        _assertUnauthorizedFirstThenAuthorizedSuccess(bytes4(0x27ed253b));
    }

    function testRetiredSelectorCannotFrontRunAuthorizedController() external {
        _assertUnauthorizedFirstThenAuthorizedSuccess(bytes4(0xa1e7ac9e));
    }

    function testGenericOwnershipAndRescueSelectorsAreAbsent() external {
        _assertAuthoritySelectorsAbsent(address(registry));
        _assertAuthoritySelectorsAbsent(address(vault));
        _assertAuthoritySelectorsAbsent(address(hook));
        assertEq(registry.agentSafe(), AGENT_SAFE);
    }

    function testFinalConfigurationConsumesControllerAndVaultSetupAuthority() external {
        _setSubject();
        bytes32 poolId = registry.registerPool(
            LaunchFeeRegistry.PoolRegistration({
                launchToken: LAUNCH_TOKEN,
                quoteToken: REGENT,
                poolFee: 3000,
                tickSpacing: 60,
                poolManager: POOL_MANAGER,
                hook: address(hook),
                authorizedInitializer: STRATEGY
            })
        );
        vault.setCanonicalTokens(poolId);

        assertEq(registry.setupAuthority(), address(0));
        assertEq(vault.tokenSetupAuthority(), address(0));
        vm.expectRevert("ONLY_TOKEN_SETUP_AUTHORITY");
        vault.setCanonicalTokens(poolId);
    }

    function testRegistrationFailurePreservesSetupAuthorityAtomically() external {
        vm.expectRevert();
        registry.registerPool(
            LaunchFeeRegistry.PoolRegistration({
                launchToken: LAUNCH_TOKEN,
                quoteToken: REGENT,
                poolFee: 3000,
                tickSpacing: 60,
                poolManager: POOL_MANAGER,
                hook: address(hook),
                authorizedInitializer: STRATEGY
            })
        );
        assertEq(registry.setupAuthority(), address(this));
        assertEq(vault.tokenSetupAuthority(), address(this));
    }

    function _setSubject() internal {
        subjectRegistry.setSubject(
            SUBJECT_ID,
            ISubjectRegistry.SubjectConfig({
                stakeToken: LAUNCH_TOKEN,
                splitter: address(1),
                treasurySafe: AGENT_SAFE,
                ingress: address(2),
                paymentLinkFactory: address(3),
                strategy: STRATEGY,
                launchFeeRegistry: address(registry),
                feeVault: address(vault),
                feeHook: address(hook),
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                lifecycle: ISubjectRegistry.Lifecycle.Active,
                label: "subject",
                safeRuntime: address(4)
            })
        );
    }

    function _hookSalt() internal view returns (bytes32 salt) {
        address predictedRegistry = vm.computeCreateAddress(address(deployer), 1);
        address predictedVault = vm.computeCreateAddress(address(deployer), 2);
        (salt,) = HookMiner.find(
            address(deployer),
            FLAGS,
            type(LaunchPoolFeeHook).creationCode,
            abi.encode(address(deployer), POOL_MANAGER, predictedRegistry, predictedVault)
        );
    }

    function _assertUnauthorizedFirstThenAuthorizedSuccess(bytes4 selector) internal {
        MockFeeSubjectRegistry attackSubjectRegistry = new MockFeeSubjectRegistry();
        LaunchFeeInfraDeployer attackDeployer = new LaunchFeeInfraDeployer(address(this));
        address predictedRegistry = vm.computeCreateAddress(address(attackDeployer), 1);
        address predictedVault = vm.computeCreateAddress(address(attackDeployer), 2);
        (bytes32 salt, address predictedHook) = HookMiner.find(
            address(attackDeployer),
            FLAGS,
            type(LaunchPoolFeeHook).creationCode,
            abi.encode(address(attackDeployer), POOL_MANAGER, predictedRegistry, predictedVault)
        );
        bytes memory payload = selector == bytes4(0x27ed253b)
            ? abi.encodeWithSelector(
                selector,
                AGENT_SAFE,
                address(attackSubjectRegistry),
                SUBJECT_ID,
                POOL_MANAGER,
                REGENT,
                salt
            )
            : abi.encodeWithSelector(selector, AGENT_SAFE, POOL_MANAGER, REGENT, salt);
        uint64 nonceBefore = vm.getNonce(address(attackDeployer));

        vm.prank(ATTACKER);
        (bool success, bytes memory revertData) = address(attackDeployer).call(payload);

        assertFalse(success);
        if (selector == bytes4(0x27ed253b)) {
            assertEq(
                revertData, abi.encodeWithSignature("Error(string)", "ONLY_AUTHORIZED_CONTROLLER")
            );
        }
        assertEq(vm.getNonce(address(attackDeployer)), nonceBefore);
        assertEq(predictedRegistry.code.length, 0);
        assertEq(predictedVault.code.length, 0);
        assertEq(predictedHook.code.length, 0);

        (
            LaunchFeeRegistry authorizedRegistry,
            LaunchFeeVault authorizedVault,
            LaunchPoolFeeHook authorizedHook
        ) = attackDeployer.deploy(
            AGENT_SAFE, address(attackSubjectRegistry), SUBJECT_ID, POOL_MANAGER, REGENT, salt
        );

        assertEq(address(authorizedRegistry), predictedRegistry);
        assertEq(address(authorizedVault), predictedVault);
        assertEq(address(authorizedHook), predictedHook);
    }

    function _assertAuthoritySelectorsAbsent(address target) internal {
        (bool transferSuccess,) =
            target.call(abi.encodeWithSignature("transferOwnership(address)", address(0xBAD)));
        (bool acceptSuccess,) = target.call(abi.encodeWithSignature("acceptOwnership()"));
        (bool nativeSuccess,) =
            target.call(abi.encodeWithSignature("rescueNative(address)", address(0xBAD)));
        (bool tokenSuccess,) = target.call(
            abi.encodeWithSignature(
                "rescueUnsupportedToken(address,uint256,address)", address(0xBAD), 1, address(0xBAD)
            )
        );
        assertFalse(transferSuccess);
        assertFalse(acceptSuccess);
        assertFalse(nativeSuccess);
        assertFalse(tokenSuccess);
    }
}
