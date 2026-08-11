// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ExampleCCADeploymentScript} from "script/ExampleCCADeploymentScript.s.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";

contract ExampleConfigFactoryMock {
    uint256 public launchFee = 1_000_000e18;
}

contract ExampleConfigSafeMock {}

contract ExampleCCADeploymentScriptConfigTest is Test {
    uint256 internal constant TICK = 79_228_162_514_264_337_593_543_950;

    ExampleCCADeploymentScript internal script;
    ExampleConfigFactoryMock internal factory;
    ExampleConfigSafeMock internal agentSafe;
    LaunchFeeInfraDeployer internal feeInfraDeployer;

    function setUp() external {
        vm.chainId(8453);
        vm.roll(5000);
        script = new ExampleCCADeploymentScript();
        factory = new ExampleConfigFactoryMock();
        agentSafe = new ExampleConfigSafeMock();
        feeInfraDeployer = new LaunchFeeInfraDeployer(address(factory));
    }

    function testConfigAcceptsExactSevenLaunchInputsIncludingAgentIdZero() external view {
        ExampleCCADeploymentScript.PreparedSafeCall memory prepared = script.prepare(_config());
        assertEq(prepared.from, address(agentSafe));
        assertEq(prepared.to, address(factory));
        assertEq(prepared.value, 0);
        assertEq(prepared.operation, 0);
    }

    function testConfigRejectsStaleFactoryBinding() external {
        ExampleCCADeploymentScript.ScriptConfig memory cfg = _config();
        cfg.feeInfraDeployer = address(new LaunchFeeInfraDeployer(address(0xBEEF)));
        vm.expectRevert("FEE_DEPLOYER_FACTORY_MISMATCH");
        script.prepare(cfg);
    }

    function testConfigRejectsRequiredRegentZero() external {
        ExampleCCADeploymentScript.ScriptConfig memory cfg = _config();
        cfg.requiredRegentRaised = 0;
        vm.expectRevert("REQUIRED_REGENT_ZERO");
        script.prepare(cfg);
    }

    function _config() private view returns (ExampleCCADeploymentScript.ScriptConfig memory) {
        return ExampleCCADeploymentScript.ScriptConfig({
            agentSafe: address(agentSafe),
            factory: address(factory),
            feeInfraDeployer: address(feeInfraDeployer),
            agentId: 0,
            tokenName: "Regent Agent Token",
            tokenSymbol: "RAGENT",
            startBlock: 5300,
            floorPrice: TICK * 100,
            requiredRegentRaised: 100e18
        });
    }
}
