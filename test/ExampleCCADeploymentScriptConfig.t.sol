// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {LaunchDeploymentController} from "src/autolaunch/LaunchDeploymentController.sol";
import {ExampleCCADeploymentScript} from "script/ExampleCCADeploymentScript.s.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

contract ExampleCCADeploymentScriptConfigHarness is ExampleCCADeploymentScript {
    ScriptConfig private harnessCfg;

    function convexAuctionStepsForTest(
        uint256 durationBlocks,
        uint256 prebidBlocks,
        uint256 finalBlockBps
    ) external pure returns (bytes memory) {
        return _convexAuctionSteps(durationBlocks, prebidBlocks, finalBlockBps);
    }

    function requireBaseMainnetUsdcForTest(address usdc) external view {
        _requireBaseMainnetUsdc(usdc);
    }

    function requireBaseMainnetRegentForTest(address token) external view {
        _requireBaseMainnetRegent(token);
    }

    function resultJsonForTest(
        address factoryAddress,
        LaunchDeploymentController.DeploymentResult memory result,
        ScriptConfig memory cfg
    ) external returns (string memory) {
        harnessCfg = cfg;
        return _resultJson(factoryAddress, result, harnessCfg);
    }
}

contract ExampleCCADeploymentScriptConfigTest is Test {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 internal constant CCA_TICK_SPACING_Q96 = 79_228_162_514_264_337_593_543_950;
    uint256 internal constant CCA_FLOOR_PRICE_Q96 = 7_922_816_251_426_433_759_354_395_000;
    uint256 internal constant CCA_MAX_TARGET_PRICE_Q96 = CCA_TICK_SPACING_Q96 * 10_000_000;

    ExampleCCADeploymentScriptConfigHarness internal scheduleHarness;

    function setUp() external {
        vm.chainId(8453);
        _installCanonicalRegentMock();
        scheduleHarness = new ExampleCCADeploymentScriptConfigHarness();
    }

    function testDefaultRegentPriceGridCoversTargetUsdRange() external pure {
        assertEq(CCA_FLOOR_PRICE_Q96 % CCA_TICK_SPACING_Q96, 0);
        assertEq(CCA_FLOOR_PRICE_Q96 / CCA_TICK_SPACING_Q96, 100);
        assertEq(CCA_MAX_TARGET_PRICE_Q96 / CCA_TICK_SPACING_Q96, 10_000_000);
        assertGe(CCA_TICK_SPACING_Q96, CCA_FLOOR_PRICE_Q96 / 10_000);
    }

    function testDeployFromEnvPrependsPrebidBlocks() external view {
        bytes memory steps = scheduleHarness.convexAuctionStepsForTest(86_400, 100, 3000);
        assertEq(steps, abi.encodePacked(uint24(0), uint40(100), _defaultConvexAuctionSteps()));
        _assertScheduleTotals(steps, 86_501);
    }

    function testDeployFromEnvAcceptsMinimumConvexDuration() external view {
        bytes memory steps = scheduleHarness.convexAuctionStepsForTest(13, 0, 3000);
        _assertScheduleTotals(steps, 14);
    }

    function testDeployFromEnvRejectsTooShortConvexDuration() external {
        vm.expectRevert("AUCTION_STEP_BLOCKS_ZERO");
        scheduleHarness.convexAuctionStepsForTest(12, 0, 3000);
    }

    function testDeployFromEnvAcceptsFinalBlockBpsBounds() external view {
        _assertFinalBlockBpsAccepted(2000);
        _assertFinalBlockBpsAccepted(3000);
        _assertFinalBlockBpsAccepted(4000);
    }

    function testDeployFromEnvRejectsFinalBlockBpsBelowRange() external {
        vm.expectRevert("CCA_FINAL_BLOCK_BPS_INVALID");
        scheduleHarness.convexAuctionStepsForTest(86_400, 0, 1999);
    }

    function testDeployFromEnvRejectsFinalBlockBpsAboveRange() external {
        vm.expectRevert("CCA_FINAL_BLOCK_BPS_INVALID");
        scheduleHarness.convexAuctionStepsForTest(86_400, 0, 4001);
    }

    function testDeployFromEnvRejectsWrongBaseMainnetUsdc() external {
        vm.expectRevert("USDC_NOT_CANONICAL");
        scheduleHarness.requireBaseMainnetUsdcForTest(address(0xC0FFEE));
    }

    function testDeployFromEnvRejectsWrongBaseMainnetRegent() external {
        vm.expectRevert("REGENT_NOT_CANONICAL");
        scheduleHarness.requireBaseMainnetRegentForTest(USDC);
    }

    function testResultJsonKeepsPoolIdAfterNumericDecimals() external {
        ExampleCCADeploymentScript.ScriptConfig memory cfg;
        cfg.auctionQuoteToken = REGENT;
        cfg.revenueUsdcToken = USDC;

        LaunchDeploymentController.DeploymentResult memory result =
            LaunchDeploymentController.DeploymentResult({
                tokenAddress: address(0x1001),
                auctionAddress: address(0x1002),
                strategyAddress: address(0x1003),
                vestingWalletAddress: address(0x1004),
                hookAddress: address(0x1005),
                feeVaultAddress: address(0x1006),
                launchFeeRegistryAddress: address(0x1007),
                subjectRegistryAddress: address(0x1008),
                revenueShareSplitterAddress: address(0x1009),
                defaultIngressAddress: address(0x1010),
                subjectId: bytes32(uint256(0x42)),
                poolId: bytes32(uint256(0x99))
            });

        string memory resultJson = scheduleHarness.resultJsonForTest(address(0xCAFE), result, cfg);

        assertTrue(_contains(resultJson, "\"revenueDecimals\":6,\"poolId\":\""));
        assertFalse(_contains(resultJson, "\"revenueDecimals\":6\",\"poolId\":\""));
    }

    function _assertFinalBlockBpsAccepted(uint256 finalBlockBps) internal view {
        bytes memory steps = scheduleHarness.convexAuctionStepsForTest(86_400, 0, finalBlockBps);
        _assertScheduleTotals(steps, 86_401);
    }

    function _installCanonicalRegentMock() internal {
        MintableERC20Mock implementation = new MintableERC20Mock("REGENT", "REGENT");
        vm.etch(REGENT, address(implementation).code);
    }

    function _defaultConvexAuctionSteps() internal pure returns (bytes memory) {
        return hex"0000360000002a8e000044000000214500004b0000001e7b00004f0000001ccd0000530000001b9c0000550000001ab300005800000019f700005a000000195a00005c00000018d400005e000000185e00005f00000017f8000061000000179b2d97e60000000001";
    }

    function _assertScheduleTotals(bytes memory steps, uint256 expectedBlocks) internal pure {
        uint256 totalMps;
        uint256 totalBlocks;

        for (uint256 offset; offset < steps.length; offset += 8) {
            uint256 packed;
            assembly ("memory-safe") {
                packed := shr(192, mload(add(add(steps, 0x20), offset)))
            }

            uint256 stepMps = packed >> 40;
            uint256 blockDelta = packed & type(uint40).max;
            totalMps += stepMps * blockDelta;
            totalBlocks += blockDelta;
        }

        assertEq(totalMps, 10_000_000);
        assertEq(totalBlocks, expectedBlocks);
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length == 0) return true;
        if (needleBytes.length > haystackBytes.length) return false;

        for (uint256 i; i <= haystackBytes.length - needleBytes.length; i++) {
            bool matches = true;

            for (uint256 j; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    matches = false;
                    break;
                }
            }

            if (matches) return true;
        }

        return false;
    }
}
