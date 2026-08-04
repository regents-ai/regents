// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeployRegentRevenueStakingScript} from "script/DeployRegentRevenueStaking.s.sol";
import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";

contract DeployRegentRevenueStakingScriptTest is Test {
    uint256 internal constant SUPPLY_DENOMINATOR = 100_000_000_000e18;
    address internal constant TREASURY = address(0xBEEF);
    address internal constant OWNER = address(0xA11CE);
    address internal constant BASE_MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    DeployRegentRevenueStakingScript internal script;
    MintableBurnableERC20Mock internal regent;
    MintableBurnableERC20Mock internal usdc;

    function setUp() external {
        script = new DeployRegentRevenueStakingScript();
        regent = new MintableBurnableERC20Mock("Regent", "REGENT", 18);
        vm.chainId(8453);
        usdc = _installCanonicalUsdcMock();
    }

    function testDeployFromEnvRequiresBaseMainnet() external {
        _setRequiredEnv();
        vm.chainId(1);

        vm.expectRevert("BASE_MAINNET_ONLY");
        script.loadConfigFromEnv();
    }

    function testDeployFromEnvLoadsCurrentRegentConfig() external {
        _setRequiredEnv();

        DeployRegentRevenueStakingScript.ScriptConfig memory cfg = script.loadConfigFromEnv();

        assertEq(cfg.regentToken, address(regent));
        assertEq(cfg.usdc, address(usdc));
        assertEq(cfg.treasuryRecipient, TREASURY);
        assertEq(cfg.owner, OWNER);
        assertEq(cfg.revenueShareSupplyDenominator, SUPPLY_DENOMINATOR);
    }

    function testValidateConfigRejectsWrongBaseMainnetUsdc() external {
        DeployRegentRevenueStakingScript.ScriptConfig memory cfg = _defaultScriptConfig();
        cfg.usdc = address(0xC0FFEE);

        vm.expectRevert("USDC_NOT_CANONICAL");
        script.validateConfig(cfg);
    }

    function testValidateConfigRejectsMissingTokenCode() external {
        DeployRegentRevenueStakingScript.ScriptConfig memory cfg = _defaultScriptConfig();
        cfg.regentToken = address(0xC0FFEE);

        vm.expectRevert("REGENT_TOKEN_NO_CODE");
        script.validateConfig(cfg);
    }

    function testValidateConfigRejectsRegentTokenAsUsdc() external {
        DeployRegentRevenueStakingScript.ScriptConfig memory cfg = _defaultScriptConfig();
        cfg.regentToken = address(usdc);

        vm.expectRevert("REGENT_TOKEN_IS_USDC");
        script.validateConfig(cfg);
    }

    function testDeployCreatesConfiguredStakingContract() external {
        RegentRevenueStaking staking = script.deploy(_defaultScriptConfig());

        assertEq(staking.stakeToken(), address(regent));
        assertEq(staking.usdc(), address(usdc));
        assertEq(staking.treasuryRecipient(), TREASURY);
        assertEq(staking.owner(), OWNER);
        assertEq(staking.revenueShareSupplyDenominator(), SUPPLY_DENOMINATOR);
    }

    function _setRequiredEnv() internal {
        vm.setEnv("BASE_REGENT_TOKEN_ADDRESS", vm.toString(address(regent)));
        vm.setEnv("BASE_USDC_ADDRESS", vm.toString(address(usdc)));
        vm.setEnv("REGENT_REVENUE_TREASURY_ADDRESS", vm.toString(TREASURY));
        vm.setEnv("REGENT_REVENUE_GOVERNANCE_SAFE_ADDRESS", vm.toString(OWNER));
        vm.setEnv("REGENT_REVENUE_SUPPLY_DENOMINATOR", vm.toString(SUPPLY_DENOMINATOR));
    }

    function _defaultScriptConfig()
        internal
        view
        returns (DeployRegentRevenueStakingScript.ScriptConfig memory cfg)
    {
        cfg.regentToken = address(regent);
        cfg.usdc = address(usdc);
        cfg.treasuryRecipient = TREASURY;
        cfg.revenueShareSupplyDenominator = SUPPLY_DENOMINATOR;
        cfg.owner = OWNER;
    }

    function _installCanonicalUsdcMock() internal returns (MintableBurnableERC20Mock mock) {
        MintableBurnableERC20Mock implementation =
            new MintableBurnableERC20Mock("USD Coin", "USDC", 6);
        vm.etch(BASE_MAINNET_USDC, address(implementation).code);
        mock = MintableBurnableERC20Mock(BASE_MAINNET_USDC);
    }
}
