// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ITokenFactory} from "src/shared/interfaces/ITokenFactory.sol";

contract MockLaunchToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_
    ) {
        require(owner_ != address(0), "OWNER_ZERO");
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        totalSupply = totalSupply_;
        balanceOf[owner_] = totalSupply_;
        emit Transfer(address(0), owner_, totalSupply_);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE_LOW");

        if (allowed != type(uint256).max) {
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "TO_ZERO");
        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= amount, "BALANCE_LOW");

        unchecked {
            balanceOf[from] = fromBalance - amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }
}

contract MockTokenFactory is ITokenFactory {
    address public lastToken;
    string public lastName;
    string public lastSymbol;
    uint8 public lastDecimals;
    uint256 public lastTotalSupply;
    address public lastOwner;
    bytes public lastConfigData;
    bytes32 public lastSalt;

    function createToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 totalSupply,
        address owner,
        bytes calldata configData,
        bytes32 salt
    ) external returns (address token) {
        token = address(new MockLaunchToken(name, symbol, decimals, totalSupply, owner));
        lastToken = token;
        lastName = name;
        lastSymbol = symbol;
        lastDecimals = decimals;
        lastTotalSupply = totalSupply;
        lastOwner = owner;
        lastConfigData = configData;
        lastSalt = salt;
    }
}
