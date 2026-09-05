// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RegentEmissionVault} from "src/autolaunch/revenue/RegentEmissionVault.sol";
import {TransferFeeERC20Mock} from "test/mocks/TransferFeeERC20Mock.sol";

contract ReentrantRegentToken {
    uint256 public totalSupply;

    RegentEmissionVault public vault;
    bool public reenterOnTransferFrom;
    bool public reentrantCallSucceeded;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function name() external pure returns (string memory) {
        return "Regent";
    }

    function symbol() external pure returns (string memory) {
        return "REGENT";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function setVault(RegentEmissionVault vault_) external {
        vault = vault_;
        allowance[address(this)][address(vault_)] = type(uint256).max;
    }

    function setReenterOnTransferFrom(bool enabled) external {
        reenterOnTransferFrom = enabled;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (reenterOnTransferFrom) {
            reenterOnTransferFrom = false;
            (reentrantCallSucceeded,) =
                address(vault).call(abi.encodeCall(RegentEmissionVault.fundRegent, (1)));
        }

        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE_LOW");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 balance = balanceOf[from];
        require(balance >= amount, "BALANCE_LOW");
        unchecked {
            balanceOf[from] = balance - amount;
            balanceOf[to] += amount;
        }
    }
}

contract RegentEmissionVaultTest is Test {
    ReentrantRegentToken internal regent;
    RegentEmissionVault internal vault;

    function setUp() external {
        regent = new ReentrantRegentToken();
        vault = new RegentEmissionVault(address(regent), address(this));
        regent.setVault(vault);
    }

    function testFundRegentReceivesExactAmount() external {
        regent.mint(address(this), 100e18);
        regent.approve(address(vault), 100e18);

        uint256 received = vault.fundRegent(100e18);

        assertEq(received, 100e18);
        assertEq(vault.availableRegent(), 100e18);
    }

    function testFundRegentRejectsReentrantTokenCallback() external {
        regent.mint(address(this), 100e18);
        regent.mint(address(regent), 1);
        regent.approve(address(vault), 100e18);
        regent.setReenterOnTransferFrom(true);

        uint256 received = vault.fundRegent(100e18);

        assertEq(received, 100e18);
        assertFalse(regent.reentrantCallSucceeded());
        assertEq(vault.availableRegent(), 100e18);
    }

    function testFundRegentRejectsInboundFeeOnTransferToken() external {
        TransferFeeERC20Mock taxed =
            new TransferFeeERC20Mock("Taxed Regent", "tREG", 18, address(0));
        RegentEmissionVault taxedVault = new RegentEmissionVault(address(taxed), address(this));

        taxed.mint(address(this), 100e18);
        taxed.setFeeBps(500);
        taxed.setFeeTriggers(address(taxedVault), false, true);
        taxed.approve(address(taxedVault), 100e18);

        vm.expectRevert("REGENT_IN_EXACT");
        taxedVault.fundRegent(100e18);

        assertEq(taxed.balanceOf(address(taxedVault)), 0);
    }
}
