// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeployAutolaunchInfraScript} from "script/DeployAutolaunchInfra.s.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {
    PermissionlessExistingTokenRevenueFactory
} from "src/autolaunch/revenue/PermissionlessExistingTokenRevenueFactory.sol";
import {DeferredAutolaunchFactory} from "src/autolaunch/revenue/DeferredAutolaunchFactory.sol";
import {RegentStakingRevenueRouter} from "src/autolaunch/revenue/RegentStakingRevenueRouter.sol";
import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {UERC20Factory} from "@uniswap/uerc20-factory/src/factories/UERC20Factory.sol";

contract DeployAutolaunchInfraScriptTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant DEPLOYER = address(0xBEEF);
    address internal constant TEST_TOKEN_FACTORY = address(uint160(0xFACA0));
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    DeployAutolaunchInfraScript internal script;
    MintableERC20Mock internal regent;
    RegentRevenueStaking internal staking;
    UERC20Factory internal tokenFactory;

    function setUp() external {
        script = new DeployAutolaunchInfraScript();
        vm.chainId(8453);
        regent = new MintableERC20Mock("REGENT", "REGENT");
        staking = new RegentRevenueStaking(address(regent), USDC, address(0xCAFE), 1e29, OWNER);
        tokenFactory = UERC20Factory(TEST_TOKEN_FACTORY);
        vm.etch(address(tokenFactory), type(UERC20Factory).runtimeCode);
    }

    function testDeployCreatesInfraAndAuthorizesSubjectFactories() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg =
            DeployAutolaunchInfraScript.ScriptConfig({
                owner: OWNER,
                revenueUsdcToken: USDC,
                regentRevenueStaking: address(staking),
                tokenFactory: address(tokenFactory)
            });

        DeployAutolaunchInfraScript.DeployedInfra memory infra = script.deploy(cfg);

        assertEq(infra.subjectRegistry.owner(), OWNER);
        assertTrue(address(infra.revenueShareSplitterDeployer) != address(0));
        assertTrue(infra.subjectRegistry.canRegisterSubject(address(infra.revenueShareFactory)));
        assertTrue(
            infra.subjectRegistry.canRegisterSubject(address(infra.existingTokenRevenueFactory))
        );
        assertEq(infra.revenueShareFactory.owner(), OWNER);
        assertEq(infra.revenueShareFactory.pendingOwner(), address(0));
        assertEq(infra.revenueIngressFactory.owner(), OWNER);
        assertEq(infra.existingTokenRevenueFactory.owner(), OWNER);
        assertEq(infra.deferredAutolaunchFactory.owner(), OWNER);
        assertEq(infra.strategyFactory.owner(), OWNER);
        assertEq(infra.revenueShareFactory.usdc(), USDC);
        assertEq(infra.revenueIngressFactory.usdc(), USDC);
        assertEq(infra.existingTokenRevenueFactory.usdc(), USDC);
        assertEq(
            address(infra.revenueShareFactory.subjectRegistry()), address(infra.subjectRegistry)
        );
        assertEq(infra.revenueIngressFactory.subjectRegistry(), address(infra.subjectRegistry));
        assertEq(
            infra.revenueShareFactory.stakingRevenueRouter(), address(infra.stakingRevenueRouter)
        );
        assertEq(
            address(infra.existingTokenRevenueFactory.stakingRevenueRouter()),
            address(infra.stakingRevenueRouter)
        );
        assertEq(
            address(infra.deferredAutolaunchFactory.stakingRevenueRouter()),
            address(infra.stakingRevenueRouter)
        );
        assertEq(infra.deferredAutolaunchFactory.trustedTokenFactory(), address(tokenFactory));
        assertEq(infra.stakingRevenueRouter.regentRevenueStaking(), address(staking));
        assertTrue(
            infra.revenueShareFactory.authorizedCreators(address(infra.deferredAutolaunchFactory))
        );
        assertTrue(
            infra.revenueIngressFactory.authorizedCreators(address(infra.revenueShareFactory))
        );
        assertTrue(
            infra.revenueIngressFactory
                .authorizedCreators(address(infra.existingTokenRevenueFactory))
        );
        assertTrue(
            infra.revenueIngressFactory.authorizedCreators(address(infra.deferredAutolaunchFactory))
        );
        assertTrue(address(infra.strategyFactory) != address(0));
    }

    function testDeploySupportsAnyConfiguredOwner() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg =
            DeployAutolaunchInfraScript.ScriptConfig({
                owner: DEPLOYER,
                revenueUsdcToken: USDC,
                regentRevenueStaking: address(staking),
                tokenFactory: address(tokenFactory)
            });

        DeployAutolaunchInfraScript.DeployedInfra memory infra = script.deploy(cfg);

        assertEq(infra.revenueShareFactory.owner(), DEPLOYER);
        assertEq(infra.revenueShareFactory.pendingOwner(), address(0));
        assertEq(infra.revenueIngressFactory.owner(), DEPLOYER);
        assertEq(infra.existingTokenRevenueFactory.owner(), DEPLOYER);
        assertEq(infra.deferredAutolaunchFactory.owner(), DEPLOYER);
        assertEq(infra.strategyFactory.owner(), DEPLOYER);
    }

    function testLoadConfigFromEnvReadsExplicitOwnerAndRevenueUsdc() external {
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_REVENUE_USDC_ADDRESS", vm.toString(USDC));
        vm.setEnv("REGENT_REVENUE_STAKING_ADDRESS", vm.toString(address(staking)));
        vm.setEnv("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS", vm.toString(address(tokenFactory)));

        DeployAutolaunchInfraScript.ScriptConfig memory cfg = script.loadConfigFromEnv();

        assertEq(cfg.owner, OWNER);
        assertEq(cfg.revenueUsdcToken, USDC);
        assertEq(cfg.regentRevenueStaking, address(staking));
        assertEq(cfg.tokenFactory, address(tokenFactory));
    }

    function testDeployFromEnvUsesLoadedConfig() external {
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_REVENUE_USDC_ADDRESS", vm.toString(USDC));
        vm.setEnv("REGENT_REVENUE_STAKING_ADDRESS", vm.toString(address(staking)));
        vm.setEnv("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS", vm.toString(address(tokenFactory)));

        DeployAutolaunchInfraScript.DeployedInfra memory infra = script.deployFromEnv();

        assertEq(infra.subjectRegistry.owner(), OWNER);
        assertTrue(address(infra.revenueShareSplitterDeployer) != address(0));
        assertTrue(infra.subjectRegistry.canRegisterSubject(address(infra.revenueShareFactory)));
        assertTrue(
            infra.subjectRegistry.canRegisterSubject(address(infra.existingTokenRevenueFactory))
        );
        assertEq(infra.revenueShareFactory.owner(), OWNER);
        assertEq(infra.revenueShareFactory.pendingOwner(), address(0));
        assertEq(infra.revenueIngressFactory.owner(), OWNER);
        assertEq(infra.existingTokenRevenueFactory.owner(), OWNER);
        assertEq(infra.deferredAutolaunchFactory.owner(), OWNER);
        assertEq(infra.strategyFactory.owner(), OWNER);
        assertEq(infra.revenueShareFactory.usdc(), USDC);
        assertTrue(address(infra.strategyFactory) != address(0));
    }

    function testRunUsesSingleBroadcastPath() external {
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_REVENUE_USDC_ADDRESS", vm.toString(USDC));
        vm.setEnv("REGENT_REVENUE_STAKING_ADDRESS", vm.toString(address(staking)));
        vm.setEnv("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS", vm.toString(address(tokenFactory)));

        script.run();
    }

    function testValidateConfigRejectsWrongBaseMainnetUsdc() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg =
            DeployAutolaunchInfraScript.ScriptConfig({
                owner: OWNER,
                revenueUsdcToken: address(0xC0FFEE),
                regentRevenueStaking: address(staking),
                tokenFactory: address(tokenFactory)
            });

        vm.expectRevert("USDC_NOT_CANONICAL");
        script.validateConfig(cfg);
    }

    function testLoadConfigFromEnvRejectsNonMainnetChain() external {
        vm.chainId(1);
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_REVENUE_USDC_ADDRESS", vm.toString(USDC));
        vm.setEnv("REGENT_REVENUE_STAKING_ADDRESS", vm.toString(address(staking)));
        vm.setEnv("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS", vm.toString(address(tokenFactory)));

        vm.expectRevert("BASE_MAINNET_ONLY");
        script.loadConfigFromEnv();
    }
}
