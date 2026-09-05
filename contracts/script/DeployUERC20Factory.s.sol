// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {UERC20Factory} from "@uniswap/uerc20-factory/src/factories/UERC20Factory.sol";

contract DeployUERC20FactoryScript is Script {
    function deploy() public returns (UERC20Factory factory) {
        factory = new UERC20Factory();
    }

    function run() external {
        vm.startBroadcast();
        UERC20Factory factory = deploy();
        vm.stopBroadcast();

        console2.log(
            string.concat(
                "UERC20_FACTORY_RESULT_JSON:{\"factoryAddress\":\"",
                vm.toString(address(factory)),
                "\"}"
            )
        );
    }
}
