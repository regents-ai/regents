// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ExampleCCADeploymentScript} from "script/ExampleCCADeploymentScript.s.sol";
import {IAutolaunchFactoryV1} from "src/autolaunch/interfaces/IAutolaunchFactoryV1.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";

contract PreparedLaunchFactoryMock is IAutolaunchFactoryV1 {
    uint256 public launchFee = 1_000_000e18;
    address public lastCaller;
    uint256 public lastAgentId;
    uint64 public lastStartBlock;
    uint256 public lastFloorPrice;
    uint128 public lastRequiredRegentRaised;
    uint256 public lastExpectedFee;
    bytes32 public lastHookSalt;

    function setLaunchFee(uint256 newLaunchFee) external {
        uint256 previousLaunchFee = launchFee;
        launchFee = newLaunchFee;
        emit LaunchFeeUpdated(previousLaunchFee, newLaunchFee);
    }

    function launch(LaunchParams calldata params) external returns (LaunchResult memory result) {
        lastCaller = msg.sender;
        lastAgentId = params.agentId;
        lastStartBlock = params.startBlock;
        lastFloorPrice = params.floorPrice;
        lastRequiredRegentRaised = params.requiredRegentRaised;
        lastExpectedFee = params.expectedFee;
        lastHookSalt = params.launchFeeHookSalt;
        result.subjectId = keccak256(abi.encode(block.chainid, msg.sender, params.agentId));
    }
}

contract AgentSafeCallMock {
    function execute(address to, bytes calldata data) external returns (bytes memory result) {
        (bool ok, bytes memory returned) = to.call(data);
        require(ok, "SAFE_CALL_FAILED");
        return returned;
    }
}

contract ExampleCCADeploymentScriptTest is Test {
    uint256 internal constant TICK = 79_228_162_514_264_337_593_543_950;

    ExampleCCADeploymentScript internal script;
    PreparedLaunchFactoryMock internal factory;
    AgentSafeCallMock internal agentSafe;
    LaunchFeeInfraDeployer internal feeInfraDeployer;

    function setUp() external {
        vm.chainId(8453);
        vm.roll(1000);
        script = new ExampleCCADeploymentScript();
        factory = new PreparedLaunchFactoryMock();
        agentSafe = new AgentSafeCallMock();
        feeInfraDeployer = new LaunchFeeInfraDeployer(address(factory));
    }

    function testPrepareProducesExactDirectSafeCall() external {
        factory.setLaunchFee(7);
        ExampleCCADeploymentScript.PreparedSafeCall memory prepared = script.prepare(_config());
        assertEq(prepared.from, address(agentSafe));
        assertEq(prepared.to, address(factory));
        assertEq(prepared.value, 0);
        assertEq(prepared.operation, 0);
        assertEq(bytes4(prepared.data), IAutolaunchFactoryV1.launch.selector);
        assertEq(prepared.feeInfraDeployerNonce, vm.getNonce(address(feeInfraDeployer)));

        agentSafe.execute(prepared.to, prepared.data);
        assertEq(factory.lastCaller(), address(agentSafe));
        assertEq(factory.lastAgentId(), 0);
        assertEq(factory.lastStartBlock(), 1300);
        assertEq(factory.lastFloorPrice(), TICK * 100);
        assertEq(factory.lastRequiredRegentRaised(), 100e18);
        assertEq(factory.lastExpectedFee(), 7);
        assertEq(factory.lastHookSalt(), prepared.launchFeeHookSalt);
    }

    function testPreparationMinesFreshWitnessFromCurrentNonce() external {
        ExampleCCADeploymentScript.PreparedSafeCall memory first = script.prepare(_config());
        vm.setNonce(address(feeInfraDeployer), first.feeInfraDeployerNonce + 2);
        ExampleCCADeploymentScript.PreparedSafeCall memory second = script.prepare(_config());
        assertEq(second.feeInfraDeployerNonce, first.feeInfraDeployerNonce + 2);
        assertTrue(second.launchFeeHookSalt != first.launchFeeHookSalt);
    }

    function testPreparationRejectsNonMainnetChain() external {
        vm.chainId(1);
        vm.expectRevert("BASE_MAINNET_ONLY");
        script.prepare(_config());
    }

    function testPreparationRejectsMisalignedFloorPrice() external {
        ExampleCCADeploymentScript.ScriptConfig memory cfg = _config();
        cfg.floorPrice++;
        vm.expectRevert("FLOOR_PRICE_TICK_MISALIGNED");
        script.prepare(cfg);
    }

    function _config() internal view returns (ExampleCCADeploymentScript.ScriptConfig memory) {
        return ExampleCCADeploymentScript.ScriptConfig({
            agentSafe: address(agentSafe),
            factory: address(factory),
            feeInfraDeployer: address(feeInfraDeployer),
            agentId: 0,
            tokenName: "Regent Agent Token",
            tokenSymbol: "RAGENT",
            startBlock: 1300,
            floorPrice: TICK * 100,
            requiredRegentRaised: 100e18
        });
    }
}
