// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AgentTokenVestingWallet} from "src/autolaunch/AgentTokenVestingWallet.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

/// @dev Minimal stand-in for the bound RegentLBPStrategy: exposes the `migrated` flag the
///      vesting wallet reads to gate release on a graduated+settled launch.
contract StrategyGraduationMock {
    bool public migrated;

    function setMigrated(bool value) external {
        migrated = value;
    }
}

contract AgentTokenVestingWalletTest is Test {
    address internal constant BENEFICIARY = address(0xBEEF);
    address internal constant NEXT_BENEFICIARY = address(0xCAFE);
    uint64 internal constant START = 1_700_000_000;
    uint64 internal constant DURATION = 365 days;
    uint64 internal constant ROTATION_DELAY = 3 days;

    MintableERC20Mock internal token;
    MintableERC20Mock internal other;
    AgentTokenVestingWallet internal vestingWallet;
    StrategyGraduationMock internal strategy;

    function setUp() external {
        token = new MintableERC20Mock("Launch Token", "LT");
        other = new MintableERC20Mock("Other", "OTHER");
        vestingWallet = new AgentTokenVestingWallet(BENEFICIARY, START, DURATION, address(token));
        token.mint(address(vestingWallet), 1000e18);

        // Bind a graduated strategy so the release-path tests exercise the happy path. The
        // gate-specific tests below override this flag to drive the pre-graduation case.
        strategy = new StrategyGraduationMock();
        strategy.setMigrated(true);
        vestingWallet.bindStrategy(address(strategy));
    }

    function testReleaseTransfersOnlyVestedAmount() external {
        vm.warp(START + DURATION / 2);

        uint256 released = vestingWallet.releaseLaunchToken();

        assertEq(released, 500e18);
        assertEq(token.balanceOf(BENEFICIARY), 500e18);
        assertEq(vestingWallet.releasedLaunchToken(), 500e18);
    }

    function testProposeBeneficiaryRotation() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        assertEq(vestingWallet.pendingBeneficiary(), NEXT_BENEFICIARY);
        assertEq(vestingWallet.pendingBeneficiaryEta(), START + ROTATION_DELAY);
    }

    function testCancelBeneficiaryRotation() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.prank(BENEFICIARY);
        vestingWallet.cancelBeneficiaryRotation();

        assertEq(vestingWallet.pendingBeneficiary(), address(0));
        assertEq(vestingWallet.pendingBeneficiaryEta(), 0);
    }

    function testExecuteBeneficiaryRotationAfterDelay() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.warp(START + ROTATION_DELAY);
        vestingWallet.executeBeneficiaryRotation();

        assertEq(vestingWallet.beneficiary(), NEXT_BENEFICIARY);
        assertEq(vestingWallet.pendingBeneficiary(), address(0));
        assertEq(vestingWallet.pendingBeneficiaryEta(), 0);
    }

    function testReleaseUsesOldBeneficiaryBeforeRotationExecutes() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.warp(START + DURATION / 2);
        uint256 released = vestingWallet.releaseLaunchToken();

        assertEq(released, 500e18);
        assertEq(token.balanceOf(BENEFICIARY), 500e18);
        assertEq(token.balanceOf(NEXT_BENEFICIARY), 0);
    }

    function testReleaseUsesNewBeneficiaryAfterRotationExecutes() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.warp(START + ROTATION_DELAY);
        vestingWallet.executeBeneficiaryRotation();

        vm.warp(START + DURATION / 2);
        uint256 released = vestingWallet.releaseLaunchToken();

        assertEq(released, 500e18);
        assertEq(token.balanceOf(BENEFICIARY), 0);
        assertEq(token.balanceOf(NEXT_BENEFICIARY), 500e18);
    }

    function testReleaseRevertsWhenNothingIsVested() external {
        vm.warp(START);

        vm.expectRevert("NOTHING_TO_RELEASE");
        vestingWallet.releaseLaunchToken();
    }

    function testBeneficiaryCanRescueUnsupportedTokenAndNative() external {
        other.mint(address(vestingWallet), 25e18);
        vm.deal(address(vestingWallet), 1 ether);

        vm.startPrank(BENEFICIARY);
        vestingWallet.rescueUnsupportedToken(address(other), 25e18, address(0x1234));
        vestingWallet.rescueNative(address(0x5678));
        vm.stopPrank();

        assertEq(other.balanceOf(address(0x1234)), 25e18);
        assertEq(address(vestingWallet).balance, 0);
        assertEq(address(0x5678).balance, 1 ether);
    }

    function testRescueBlocksLaunchToken() external {
        vm.prank(BENEFICIARY);
        vm.expectRevert("PROTECTED_TOKEN");
        vestingWallet.rescueUnsupportedToken(address(token), 1, BENEFICIARY);
    }

    function testBindStrategyIsDeployerGatedAndSetOnce() external {
        // A fresh, unbound wallet — setUp's wallet is already bound.
        AgentTokenVestingWallet fresh =
            new AgentTokenVestingWallet(BENEFICIARY, START, DURATION, address(token));
        assertEq(fresh.deployer(), address(this));

        vm.prank(BENEFICIARY);
        vm.expectRevert("ONLY_DEPLOYER");
        fresh.bindStrategy(address(0xF00D));

        vm.expectRevert("STRATEGY_ZERO");
        fresh.bindStrategy(address(0));

        fresh.bindStrategy(address(0xF00D));
        assertEq(fresh.strategy(), address(0xF00D));

        vm.expectRevert("STRATEGY_BOUND");
        fresh.bindStrategy(address(0xFEED));
    }

    function testReleaseRevertsBeforeLaunchGraduates() external {
        // A launch that has not yet settled: the strategy has not migrated. The beneficiary
        // must not be able to vest any of the 85% during the ~2-day auction window, so a failed
        // launch leaves nothing to withdraw before the burn.
        strategy.setMigrated(false);

        vm.warp(START + DURATION / 2);
        assertFalse(vestingWallet.launchGraduated());
        assertEq(vestingWallet.releasableLaunchToken(), 0);

        vm.prank(BENEFICIARY);
        vm.expectRevert("LAUNCH_NOT_GRADUATED");
        vestingWallet.releaseLaunchToken();

        // Once the launch settles, linear vesting resumes exactly as before.
        strategy.setMigrated(true);
        uint256 released = vestingWallet.releaseLaunchToken();
        assertEq(released, 500e18);
        assertEq(token.balanceOf(BENEFICIARY), 500e18);
    }

    function testReleaseRevertsWhenStrategyUnbound() external {
        AgentTokenVestingWallet unbound =
            new AgentTokenVestingWallet(BENEFICIARY, START, DURATION, address(token));
        token.mint(address(unbound), 1000e18);

        vm.warp(START + DURATION / 2);
        assertFalse(unbound.launchGraduated());
        assertEq(unbound.releasableLaunchToken(), 0);
        vm.expectRevert("LAUNCH_NOT_GRADUATED");
        unbound.releaseLaunchToken();
    }

    function testNonGraduatedLaunchReleasesNothingAndBurnsFullBalance() external {
        // End-to-end intent check: on a failed launch (strategy never migrates) the agent can
        // release nothing, and the strategy's failed-launch burn takes the entire balance.
        address deadAddress = 0x000000000000000000000000000000000000dEaD;
        strategy.setMigrated(false);

        vm.warp(START + 2 * DURATION);
        vm.prank(BENEFICIARY);
        vm.expectRevert("LAUNCH_NOT_GRADUATED");
        vestingWallet.releaseLaunchToken();

        vm.prank(address(strategy));
        uint256 burned = vestingWallet.burnOnFailedLaunch();

        assertEq(burned, 1000e18);
        assertEq(token.balanceOf(deadAddress), 1000e18);
        assertEq(token.balanceOf(BENEFICIARY), 0);
    }

    function testBurnOnFailedLaunchSendsFullBalanceToDeadAddress() external {
        address deadAddress = 0x000000000000000000000000000000000000dEaD;

        vm.prank(address(strategy));
        uint256 burned = vestingWallet.burnOnFailedLaunch();

        assertEq(burned, 1000e18);
        assertEq(token.balanceOf(deadAddress), 1000e18);
        assertEq(token.balanceOf(address(vestingWallet)), 0);
        assertTrue(vestingWallet.burnedOnFailedLaunch());

        // Nothing is releasable after the burn — even long past the vesting end.
        vm.warp(START + 2 * DURATION);
        assertEq(vestingWallet.releasableLaunchToken(), 0);
        vm.expectRevert("NOTHING_TO_RELEASE");
        vestingWallet.releaseLaunchToken();

        vm.prank(address(strategy));
        vm.expectRevert("ALREADY_BURNED");
        vestingWallet.burnOnFailedLaunch();
    }

    function testBurnOnFailedLaunchRejectsEveryoneButTheBoundStrategy() external {
        vm.prank(BENEFICIARY);
        vm.expectRevert("ONLY_STRATEGY");
        vestingWallet.burnOnFailedLaunch();

        vm.expectRevert("ONLY_STRATEGY");
        vestingWallet.burnOnFailedLaunch();
    }

    function testBurnAfterPartialReleaseBurnsOnlyRemainingBalance() external {
        vm.warp(START + DURATION / 2);
        vestingWallet.releaseLaunchToken();
        assertEq(token.balanceOf(BENEFICIARY), 500e18);

        vm.prank(address(strategy));
        uint256 burned = vestingWallet.burnOnFailedLaunch();

        assertEq(burned, 500e18);
        assertEq(vestingWallet.releasableLaunchToken(), 0);
    }
}
