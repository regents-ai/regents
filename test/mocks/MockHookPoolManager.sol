// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";

contract MockHookPoolManager {
    using SafeTransferLib for address;
    using CurrencyLibrary for Currency;

    address public lastTakeCurrency;
    address public lastTakeRecipient;
    uint256 public lastTakeAmount;

    function take(Currency currency, address to, uint256 amount) external {
        lastTakeCurrency = Currency.unwrap(currency);
        lastTakeRecipient = to;
        lastTakeAmount = amount;
        lastTakeCurrency.safeTransfer(to, amount);
    }

    function simulateSwap(
        address hook,
        address sender,
        PoolKey memory key,
        SwapParams memory params,
        int128 amount0,
        int128 amount1
    )
        external
        returns (
            bytes4 beforeSelector,
            BeforeSwapDelta beforeDelta,
            bytes4 afterSelector,
            int128 afterDelta
        )
    {
        (beforeSelector, beforeDelta,) = IHooks(hook).beforeSwap(sender, key, params, "");
        (afterSelector, afterDelta) =
            IHooks(hook).afterSwap(sender, key, params, toBalanceDelta(amount0, amount1), "");
    }
}
