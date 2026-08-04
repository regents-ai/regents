// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeferredAutolaunchVestingWallet} from "src/autolaunch/DeferredAutolaunchVestingWallet.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

contract DeferredAutolaunchVestingWalletTest is Test {
    address internal constant BENEFICIARY = address(0x1111);
    address internal constant NEXT_BENEFICIARY = address(0x2222);
    uint64 internal constant START = 1_000_000;
    uint256 internal constant SUPPLY = 1000e18;

    MintableERC20Mock internal launchToken;
    DeferredAutolaunchVestingWallet internal vestingWallet;

    function setUp() external {
        launchToken = new MintableERC20Mock("Launch", "LAUNCH");
        vestingWallet =
            new DeferredAutolaunchVestingWallet(BENEFICIARY, START, address(launchToken));
        launchToken.mint(address(vestingWallet), SUPPLY);
    }

    function testNothingReleasableBeforeDayTen() external {
        vm.warp(START + 10 days - 1);

        assertEq(vestingWallet.releasableLaunchToken(), 0);
        assertEq(vestingWallet.vestedLaunchToken(), 0);

        vm.expectRevert("NOTHING_TO_RELEASE");
        vestingWallet.releaseLaunchToken();
    }

    function testExactlyFifteenPercentReleasableAtDayTen() external {
        vm.warp(START + 10 days);

        assertEq(vestingWallet.releasableLaunchToken(), 150e18);

        vestingWallet.releaseLaunchToken();

        assertEq(launchToken.balanceOf(BENEFICIARY), 150e18);
        assertEq(vestingWallet.releasedLaunchToken(), 150e18);
    }

    function testRemainingEightyFivePercentVestsLinearly() external {
        vm.warp(START + 10 days + ((365 days - 10 days) / 2));

        assertEq(vestingWallet.vestedLaunchToken(), 575e18);
        assertEq(vestingWallet.releasableLaunchToken(), 575e18);
    }

    function testFullSupplyReleasableAtDay365() external {
        vm.warp(START + 365 days);

        assertEq(vestingWallet.releasableLaunchToken(), SUPPLY);

        vestingWallet.releaseLaunchToken();

        assertEq(launchToken.balanceOf(BENEFICIARY), SUPPLY);
        assertEq(launchToken.balanceOf(address(vestingWallet)), 0);
    }

    function testBeneficiaryRotationPreservesVestingMath() external {
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.warp(START + 3 days);
        vestingWallet.executeBeneficiaryRotation();

        vm.warp(START + 365 days);
        vestingWallet.releaseLaunchToken();

        assertEq(launchToken.balanceOf(BENEFICIARY), 0);
        assertEq(launchToken.balanceOf(NEXT_BENEFICIARY), SUPPLY);
    }

    function testLaunchTokenCannotBeRescued() external {
        vm.prank(BENEFICIARY);
        vm.expectRevert("PROTECTED_TOKEN");
        vestingWallet.rescueUnsupportedToken(address(launchToken), 1e18, BENEFICIARY);
    }
}
