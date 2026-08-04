// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Minimal} from "src/shared/interfaces/IERC20Minimal.sol";

library SafeTransferLib {
    function safeTransfer(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool nativeTransferSucceeded,) = to.call{value: amount}("");
            require(nativeTransferSucceeded, "NATIVE_TRANSFER_FAILED");
            return;
        }

        require(token.code.length != 0, "TOKEN_NOT_CONTRACT");
        (bool success, bytes memory data) =
            token.call(abi.encodeCall(IERC20Minimal.transfer, (to, amount)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        require(token != address(0), "NATIVE_TRANSFER_FROM_UNSUPPORTED");
        require(token.code.length != 0, "TOKEN_NOT_CONTRACT");
        (bool success, bytes memory data) =
            token.call(abi.encodeCall(IERC20Minimal.transferFrom, (from, to, amount)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    function forceApprove(address token, address spender, uint256 amount) internal {
        require(token != address(0), "NATIVE_APPROVE_UNSUPPORTED");
        require(token.code.length != 0, "TOKEN_NOT_CONTRACT");
        (bool success, bytes memory data) =
            token.call(abi.encodeCall(IERC20Minimal.approve, (spender, amount)));

        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            return;
        }

        (success, data) = token.call(abi.encodeCall(IERC20Minimal.approve, (spender, 0)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_RESET_FAILED");

        (success, data) = token.call(abi.encodeCall(IERC20Minimal.approve, (spender, amount)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }
}
