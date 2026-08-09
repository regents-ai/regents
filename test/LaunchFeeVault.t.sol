// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockHookDeployer} from "test/mocks/MockHookDeployer.sol";
import {MockFeeSubjectRegistry} from "test/mocks/MockHookPoolManager.sol";

contract MockRegentFundingTarget {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    uint256 public totalFundedRegent;
    uint8 public mode;
    address public callbackVault;
    bytes32 public callbackPoolId;

    function setMode(uint8 mode_) external {
        mode = mode_;
    }

    function setCallback(address vault_, bytes32 poolId_) external {
        callbackVault = vault_;
        callbackPoolId = poolId_;
    }

    function fundRegentRewards(uint256 amount) external returns (uint256 received) {
        if (mode == 1) revert("STAKING_FAILED");
        if (mode == 5) {
            (bool success,) = callbackVault.call(
                abi.encodeCall(LaunchFeeVault.withdrawTreasury, (callbackPoolId))
            );
            require(success, "CALLBACK_FAILED");
        }
        if (mode != 4) {
            MintableERC20Mock(REGENT).transferFrom(msg.sender, address(this), amount);
        }
        if (mode != 3) totalFundedRegent += amount;
        return mode == 2 ? amount - 1 : amount;
    }
}

contract LaunchFeeVaultTest is Test {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;
    address internal constant AGENT_SAFE = address(0xA11CE);
    address internal constant LAUNCH_TOKEN = address(0x1001);
    address internal constant INITIALIZER = address(0x7007);
    bytes32 internal constant SUBJECT_ID = keccak256("subject");
    uint256 internal constant SUBJECT_SHARE = 10e18;
    uint256 internal constant PROTOCOL_SHARE = 10e18;

    LaunchFeeRegistry internal registry;
    LaunchFeeVault internal vault;
    LaunchPoolFeeHook internal hook;
    MockFeeSubjectRegistry internal subjectRegistry;
    MintableERC20Mock internal regent;
    MockRegentFundingTarget internal staking;
    bytes32 internal poolId;

    function setUp() external {
        MintableERC20Mock tokenImplementation = new MintableERC20Mock("REGENT", "REGENT");
        vm.etch(REGENT, address(tokenImplementation).code);
        regent = MintableERC20Mock(REGENT);
        MockRegentFundingTarget stakingImplementation = new MockRegentFundingTarget();
        vm.etch(STAKING, address(stakingImplementation).code);
        staking = MockRegentFundingTarget(STAKING);

        subjectRegistry = new MockFeeSubjectRegistry();
        registry = new LaunchFeeRegistry(
            AGENT_SAFE, address(this), address(subjectRegistry), SUBJECT_ID, REGENT
        );
        vault = new LaunchFeeVault(address(registry));
        MockHookDeployer hookDeployer = new MockHookDeployer();
        hook = hookDeployer.deploy(address(0x5005), address(registry), address(vault));
        vault.setHook(address(hook));
        _setSubject(ISubjectRegistry.Lifecycle.Active);
        poolId = registry.registerPool(
            LaunchFeeRegistry.PoolRegistration({
                launchToken: LAUNCH_TOKEN,
                quoteToken: REGENT,
                poolFee: 3000,
                tickSpacing: 60,
                poolManager: address(0x5005),
                hook: address(hook),
                authorizedInitializer: INITIALIZER
            })
        );
        vault.setCanonicalTokens(poolId);
    }

    function testFinalSetupAuthoritiesAreConsumed() external view {
        assertEq(vault.hookSetupAuthority(), address(0));
        assertEq(vault.tokenSetupAuthority(), address(0));
        assertEq(vault.canonicalLaunchToken(), LAUNCH_TOKEN);
        assertEq(vault.canonicalQuoteToken(), REGENT);
    }

    function testConsumedHookSetupAuthorityRejectsStaleCaller() external {
        vm.expectRevert("ONLY_HOOK_SETUP_AUTHORITY");
        vault.setHook(address(0x1234));
    }

    function testRejectsNativeEthDeposits() external {
        vm.deal(address(this), 1 ether);
        (bool success,) = payable(address(vault)).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(vault).balance, 0);
    }

    function testForcedEthRemainsHeldWithoutRecoverySurface() external {
        vm.deal(address(vault), 1 ether);
        (bool success,) =
            address(vault).call(abi.encodeWithSignature("rescueNative(address)", AGENT_SAFE));
        assertFalse(success);
        assertEq(address(vault).balance, 1 ether);
    }

    function testDirectTransferNeverBecomesStoredAccrual() external {
        regent.mint(address(vault), 7e18);
        assertEq(vault.treasuryAccrued(poolId, REGENT), 0);
        assertEq(vault.regentAccrued(poolId, REGENT), 0);
        vm.expectRevert("NOTHING_ACCRUED");
        vault.withdrawTreasury(poolId);
    }

    function testFixedSubjectClaimAlwaysDrainsToAgentSafe() external {
        _accrueAndFundVault();
        vault.withdrawTreasury(poolId);
        assertEq(regent.balanceOf(AGENT_SAFE), SUBJECT_SHARE);
        assertEq(vault.treasuryAccrued(poolId, REGENT), 0);
    }

    function testProtocolShareFundsOnlyFrozenStakingWithExactAccounting() external {
        _accrueAndFundVault();
        uint256 vaultBefore = regent.balanceOf(address(vault));

        vault.fundRegentShare(poolId);

        assertEq(regent.balanceOf(STAKING), PROTOCOL_SHARE);
        assertEq(staking.totalFundedRegent(), PROTOCOL_SHARE);
        assertEq(regent.balanceOf(address(vault)), vaultBefore - PROTOCOL_SHARE);
        assertEq(regent.allowance(address(vault), STAKING), 0);
        assertEq(vault.regentAccrued(poolId, REGENT), 0);
    }

    function testQuarantineBlocksNewAccrualButAllowsStoredFixedClaims() external {
        _accrueAndFundVault();
        subjectRegistry.setLifecycle(SUBJECT_ID, ISubjectRegistry.Lifecycle.Quarantined);

        vm.prank(address(hook));
        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        vault.recordAccrual(poolId, REGENT, 1, 1);

        vault.withdrawTreasury(poolId);
        vault.fundRegentShare(poolId);
        assertEq(regent.balanceOf(AGENT_SAFE), SUBJECT_SHARE);
        assertEq(regent.balanceOf(STAKING), PROTOCOL_SHARE);
    }

    function testEveryStakingMismatchRollsBackAccrualBalanceAndAllowance() external {
        for (uint8 mode = 1; mode <= 4; ++mode) {
            _accrueAndFundVault();
            staking.setMode(mode);
            uint256 vaultBefore = regent.balanceOf(address(vault));
            uint256 stakingBefore = regent.balanceOf(STAKING);
            uint256 fundedBefore = staking.totalFundedRegent();

            vm.expectRevert();
            vault.fundRegentShare(poolId);

            assertEq(vault.regentAccrued(poolId, REGENT), PROTOCOL_SHARE);
            assertEq(regent.balanceOf(address(vault)), vaultBefore);
            assertEq(regent.balanceOf(STAKING), stakingBefore);
            assertEq(staking.totalFundedRegent(), fundedBefore);
            assertEq(regent.allowance(address(vault), STAKING), 0);

            staking.setMode(0);
            vault.fundRegentShare(poolId);
        }
    }

    function testStakingCallbackCannotReenterSubjectClaimAndEverythingRollsBack() external {
        _accrueAndFundVault();
        staking.setMode(5);
        staking.setCallback(address(vault), poolId);
        uint256 vaultBefore = regent.balanceOf(address(vault));
        uint256 stakingBefore = regent.balanceOf(STAKING);
        uint256 fundedBefore = staking.totalFundedRegent();

        vm.expectRevert("CALLBACK_FAILED");
        vault.fundRegentShare(poolId);

        assertEq(vault.treasuryAccrued(poolId, REGENT), SUBJECT_SHARE);
        assertEq(vault.regentAccrued(poolId, REGENT), PROTOCOL_SHARE);
        assertEq(regent.balanceOf(address(vault)), vaultBefore);
        assertEq(regent.balanceOf(STAKING), stakingBefore);
        assertEq(staking.totalFundedRegent(), fundedBefore);
        assertEq(regent.allowance(address(vault), STAKING), 0);
    }

    function testNonzeroInitialStakingAllowanceRejectsBeforeStateChange() external {
        _accrueAndFundVault();
        vm.prank(address(vault));
        regent.approve(STAKING, 1);

        vm.expectRevert("ALLOWANCE_NOT_ZERO");
        vault.fundRegentShare(poolId);
        assertEq(vault.regentAccrued(poolId, REGENT), PROTOCOL_SHARE);
        assertEq(regent.balanceOf(STAKING), 0);
    }

    function testUnsupportedAndProtectedTokensRemainHeldWithoutRecoverySurface() external {
        MintableERC20Mock junk = new MintableERC20Mock("Junk", "JUNK");
        junk.mint(address(vault), 3e18);
        (bool junkSuccess,) = address(vault)
            .call(
                abi.encodeWithSignature(
                    "rescueUnsupportedToken(address,uint256,address)",
                    address(junk),
                    3e18,
                    AGENT_SAFE
                )
            );
        (bool regentSuccess,) = address(vault)
            .call(
                abi.encodeWithSignature(
                    "rescueUnsupportedToken(address,uint256,address)", REGENT, 1, AGENT_SAFE
                )
            );
        assertFalse(junkSuccess);
        assertFalse(regentSuccess);
        assertEq(junk.balanceOf(address(vault)), 3e18);
    }

    function _accrueAndFundVault() internal {
        vm.prank(address(hook));
        vault.recordAccrual(poolId, REGENT, SUBJECT_SHARE, PROTOCOL_SHARE);
        regent.mint(address(vault), SUBJECT_SHARE + PROTOCOL_SHARE);
    }

    function _setSubject(ISubjectRegistry.Lifecycle lifecycle) internal {
        subjectRegistry.setSubject(
            SUBJECT_ID,
            ISubjectRegistry.SubjectConfig({
                stakeToken: LAUNCH_TOKEN,
                splitter: address(1),
                treasurySafe: AGENT_SAFE,
                ingress: address(2),
                paymentLinkFactory: address(3),
                strategy: INITIALIZER,
                launchFeeRegistry: address(registry),
                feeVault: address(vault),
                feeHook: address(hook),
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
