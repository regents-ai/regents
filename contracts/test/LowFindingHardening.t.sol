// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AgentTokenVestingWallet} from "src/autolaunch/AgentTokenVestingWallet.sol";
import {DeferredAutolaunchVestingWallet} from "src/autolaunch/DeferredAutolaunchVestingWallet.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

/// @notice Thin wrapper so the internal SafeTransferLib functions are externally callable.
contract SafeTransferHarness {
    using SafeTransferLib for address;

    function transfer(address token, address to, uint256 amount) external {
        token.safeTransfer(to, amount);
    }

    function transferFrom(address token, address from, address to, uint256 amount) external {
        token.safeTransferFrom(from, to, amount);
    }

    function forceApprove(address token, address spender, uint256 amount) external {
        token.forceApprove(spender, amount);
    }
}

/// @notice Regression tests for the LOW/INFO hardening pass:
///   - SafeTransferLib now reverts when the "token" address holds no code (a codeless address
///     silently returns success, which previously let a no-op "transfer" pass as if it moved
///     value). OZ/Solmate do the same.
///   - The vesting wallets reject a zero start timestamp (which would otherwise treat the whole
///     allocation as instantly fully vested).
contract LowFindingHardeningTest is Test {
    SafeTransferHarness internal harness;
    MintableERC20Mock internal token;

    address internal constant CODELESS = address(0x9999);
    address internal constant BENEFICIARY = address(0x1111);
    address internal constant SINK = address(0x2222);

    function setUp() external {
        harness = new SafeTransferHarness();
        token = new MintableERC20Mock("Token", "TKN");
    }

    function testSafeTransferRevertsOnCodelessToken() external {
        vm.expectRevert("TOKEN_NOT_CONTRACT");
        harness.transfer(CODELESS, SINK, 1);
    }

    function testSafeTransferFromRevertsOnCodelessToken() external {
        vm.expectRevert("TOKEN_NOT_CONTRACT");
        harness.transferFrom(CODELESS, address(this), SINK, 1);
    }

    function testForceApproveRevertsOnCodelessToken() external {
        vm.expectRevert("TOKEN_NOT_CONTRACT");
        harness.forceApprove(CODELESS, SINK, 1);
    }

    function testSafeTransferStillWorksForRealToken() external {
        token.mint(address(harness), 100);
        harness.transfer(address(token), SINK, 40);
        assertEq(token.balanceOf(SINK), 40, "real ERC20 transfer unaffected by the guard");
    }

    function testAgentVestingWalletRejectsZeroStart() external {
        vm.expectRevert("START_ZERO");
        new AgentTokenVestingWallet(BENEFICIARY, 0, 365 days, address(token));
    }

    function testAgentVestingWalletAcceptsNonZeroStart() external {
        AgentTokenVestingWallet w = new AgentTokenVestingWallet(
            BENEFICIARY, uint64(block.timestamp), 365 days, address(token)
        );
        assertEq(w.startTimestamp(), uint64(block.timestamp));
    }

    function testDeferredVestingWalletRejectsZeroStart() external {
        vm.expectRevert("START_ZERO");
        new DeferredAutolaunchVestingWallet(BENEFICIARY, 0, address(token));
    }

    function testDeferredVestingWalletAcceptsNonZeroStart() external {
        DeferredAutolaunchVestingWallet w = new DeferredAutolaunchVestingWallet(
            BENEFICIARY, uint64(block.timestamp), address(token)
        );
        assertEq(w.startTimestamp(), uint64(block.timestamp));
    }
}
