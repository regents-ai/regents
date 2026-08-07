// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// NON-PRODUCTION: current source is not proven to reproduce deployed singleton
// 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5; certification is deployed-runtime-bound.
// The broadcast-recorded commit object is not present in the retained archive Git object set.

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {BaseUsdc} from "src/shared/libraries/BaseUsdc.sol";

contract DeployRegentRevenueStakingScript is Script {
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;
    address internal constant BASE_MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    struct ScriptConfig {
        address regentToken;
        address usdc;
        address treasuryRecipient;
        uint256 revenueShareSupplyDenominator;
        address owner;
    }

    function deployFromEnv() external returns (RegentRevenueStaking staking) {
        _requireNonProductionDeploy();
        return deploy(loadConfigFromEnv());
    }

    function deploy(ScriptConfig memory cfg) public returns (RegentRevenueStaking staking) {
        _requireNonProductionDeploy();
        validateConfig(cfg);

        vm.startBroadcast();
        staking = new RegentRevenueStaking(
            cfg.regentToken,
            cfg.usdc,
            cfg.treasuryRecipient,
            cfg.revenueShareSupplyDenominator,
            cfg.owner
        );
        vm.stopBroadcast();
    }

    function validateConfig(ScriptConfig memory cfg) public view {
        require(cfg.regentToken != address(0), "REGENT_TOKEN_ZERO");
        require(cfg.regentToken.code.length != 0, "REGENT_TOKEN_NO_CODE");
        require(cfg.usdc != address(0), "USDC_ZERO");
        require(cfg.regentToken != cfg.usdc, "REGENT_TOKEN_IS_USDC");
        require(cfg.usdc == BASE_MAINNET_USDC, "USDC_NOT_CANONICAL");
        require(cfg.usdc.code.length != 0, "USDC_NO_CODE");
        BaseUsdc.requireCanonical(cfg.usdc);
        require(cfg.treasuryRecipient != address(0), "TREASURY_ZERO");
        require(cfg.owner != address(0), "OWNER_ZERO");
        require(cfg.revenueShareSupplyDenominator != 0, "SUPPLY_DENOMINATOR_ZERO");
    }

    function loadConfigFromEnv() public view returns (ScriptConfig memory cfg) {
        require(block.chainid == BASE_MAINNET_CHAIN_ID, "BASE_MAINNET_ONLY");

        cfg.regentToken = vm.envAddress("BASE_REGENT_TOKEN_ADDRESS");
        require(cfg.regentToken != address(0), "REGENT_TOKEN_ZERO");

        cfg.usdc = vm.envAddress("BASE_USDC_ADDRESS");
        require(cfg.usdc != address(0), "USDC_ZERO");

        cfg.treasuryRecipient = vm.envAddress("REGENT_REVENUE_TREASURY_ADDRESS");
        require(cfg.treasuryRecipient != address(0), "TREASURY_ZERO");

        cfg.owner = vm.envAddress("REGENT_REVENUE_GOVERNANCE_SAFE_ADDRESS");
        require(cfg.owner != address(0), "OWNER_ZERO");

        cfg.revenueShareSupplyDenominator = vm.envUint("REGENT_REVENUE_SUPPLY_DENOMINATOR");
        require(cfg.revenueShareSupplyDenominator != 0, "SUPPLY_DENOMINATOR_ZERO");

        validateConfig(cfg);
    }

    function run() external {
        _requireNonProductionDeploy();
        ScriptConfig memory cfg = loadConfigFromEnv();
        RegentRevenueStaking staking = deploy(cfg);

        console2.log(
            string.concat(
                "REGENT_REVENUE_STAKING_RESULT_JSON:{\"contractAddress\":\"",
                vm.toString(address(staking)),
                "\",\"regentTokenAddress\":\"",
                vm.toString(cfg.regentToken),
                "\",\"usdcAddress\":\"",
                vm.toString(cfg.usdc),
                "\",\"treasuryRecipient\":\"",
                vm.toString(cfg.treasuryRecipient),
                "\",\"owner\":\"",
                vm.toString(cfg.owner),
                "\",\"revenueShareSupplyDenominator\":",
                vm.toString(cfg.revenueShareSupplyDenominator),
                "}"
            )
        );
    }

    function _requireNonProductionDeploy() internal view {
        require(
            vm.envOr("ALLOW_NON_PRODUCTION_STAKING_DEPLOY", false),
            "NON_PRODUCTION_STAKING_DEPLOY_DISABLED"
        );
    }
}
