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
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";
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
    address internal constant CONTROLLER = address(0xC011);
    address internal constant GUARDIAN = address(0x600D);
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
                tokenFactory: address(tokenFactory),
                controller: CONTROLLER,
                guardian: GUARDIAN
            });

        DeployAutolaunchInfraScript.DeployedInfra memory infra = script.deploy(cfg);

        assertEq(infra.subjectRegistry.owner(), OWNER);
        assertTrue(address(infra.revenueShareSplitterDeployer) != address(0));
        assertTrue(infra.subjectRegistry.canRegisterSubject(CONTROLLER));
        assertFalse(infra.subjectRegistry.canRegisterSubject(address(infra.revenueShareFactory)));
        PermissionlessExistingTokenRevenueFactory existingTokenFactory = new PermissionlessExistingTokenRevenueFactory(
            OWNER,
            USDC,
            address(infra.revenueIngressFactory),
            infra.subjectRegistry,
            IRegentStakingRevenueRouter(address(infra.stakingRevenueRouter))
        );
        assertFalse(infra.subjectRegistry.canRegisterSubject(address(existingTokenFactory)));
        assertEq(infra.revenueShareFactory.owner(), OWNER);
        assertEq(infra.revenueShareFactory.pendingOwner(), address(0));
        assertEq(infra.revenueIngressFactory.owner(), OWNER);
        assertEq(infra.deferredAutolaunchFactory.owner(), OWNER);
        assertEq(infra.strategyFactory.owner(), OWNER);
        assertEq(infra.revenueShareFactory.usdc(), USDC);
        assertEq(infra.revenueIngressFactory.usdc(), USDC);
        assertEq(
            address(infra.revenueShareFactory.subjectRegistry()), address(infra.subjectRegistry)
        );
        assertEq(infra.revenueIngressFactory.subjectRegistry(), address(infra.subjectRegistry));
        assertEq(
            infra.revenueShareFactory.stakingRevenueRouter(), address(infra.stakingRevenueRouter)
        );
        assertEq(
            address(infra.deferredAutolaunchFactory.stakingRevenueRouter()),
            address(infra.stakingRevenueRouter)
        );
        assertEq(infra.deferredAutolaunchFactory.trustedTokenFactory(), address(tokenFactory));
        assertEq(infra.stakingRevenueRouter.regentRevenueStaking(), address(staking));
        assertFalse(
            infra.revenueShareFactory.authorizedCreators(address(infra.deferredAutolaunchFactory))
        );
        assertFalse(
            infra.revenueIngressFactory.authorizedCreators(address(infra.revenueShareFactory))
        );
        assertFalse(infra.revenueIngressFactory.authorizedCreators(address(existingTokenFactory)));
        assertFalse(
            infra.revenueIngressFactory.authorizedCreators(address(infra.deferredAutolaunchFactory))
        );
        assertEq(infra.subjectRegistry.controller(), CONTROLLER);
        assertEq(infra.subjectRegistry.guardian(), GUARDIAN);
        assertEq(infra.paymentLinkFactory.controller(), CONTROLLER);
        assertTrue(address(infra.strategyFactory) != address(0));
    }

    function testDeploySupportsAnyConfiguredOwner() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg =
            DeployAutolaunchInfraScript.ScriptConfig({
                owner: DEPLOYER,
                revenueUsdcToken: USDC,
                regentRevenueStaking: address(staking),
                tokenFactory: address(tokenFactory),
                controller: CONTROLLER,
                guardian: GUARDIAN
            });

        DeployAutolaunchInfraScript.DeployedInfra memory infra = script.deploy(cfg);

        assertEq(infra.revenueShareFactory.owner(), DEPLOYER);
        assertEq(infra.revenueShareFactory.pendingOwner(), address(0));
        assertEq(infra.revenueIngressFactory.owner(), DEPLOYER);
        assertEq(infra.deferredAutolaunchFactory.owner(), DEPLOYER);
        assertEq(infra.strategyFactory.owner(), DEPLOYER);
    }

    function testLoadConfigFromEnvReadsExplicitOwnerAndRevenueUsdc() external {
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_REVENUE_USDC_ADDRESS", vm.toString(USDC));
        vm.setEnv("REGENT_REVENUE_STAKING_ADDRESS", vm.toString(address(staking)));
        vm.setEnv("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS", vm.toString(address(tokenFactory)));
        vm.setEnv("AUTOLAUNCH_CONTROLLER_ADDRESS", vm.toString(CONTROLLER));
        vm.setEnv("AUTOLAUNCH_GUARDIAN_ADDRESS", vm.toString(GUARDIAN));

        DeployAutolaunchInfraScript.ScriptConfig memory cfg = script.loadConfigFromEnv();

        assertEq(cfg.owner, OWNER);
        assertEq(cfg.revenueUsdcToken, USDC);
        assertEq(cfg.regentRevenueStaking, address(staking));
        assertEq(cfg.tokenFactory, address(tokenFactory));
        assertEq(cfg.controller, CONTROLLER);
        assertEq(cfg.guardian, GUARDIAN);
    }

    function testDeployFromEnvUsesLoadedConfig() external {
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_REVENUE_USDC_ADDRESS", vm.toString(USDC));
        vm.setEnv("REGENT_REVENUE_STAKING_ADDRESS", vm.toString(address(staking)));
        vm.setEnv("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS", vm.toString(address(tokenFactory)));
        vm.setEnv("AUTOLAUNCH_CONTROLLER_ADDRESS", vm.toString(CONTROLLER));
        vm.setEnv("AUTOLAUNCH_GUARDIAN_ADDRESS", vm.toString(GUARDIAN));

        DeployAutolaunchInfraScript.DeployedInfra memory infra = script.deployFromEnv();

        assertEq(infra.subjectRegistry.owner(), OWNER);
        assertTrue(address(infra.revenueShareSplitterDeployer) != address(0));
        assertTrue(infra.subjectRegistry.canRegisterSubject(CONTROLLER));
        assertEq(infra.revenueShareFactory.owner(), OWNER);
        assertEq(infra.revenueShareFactory.pendingOwner(), address(0));
        assertEq(infra.revenueIngressFactory.owner(), OWNER);
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
        vm.setEnv("AUTOLAUNCH_CONTROLLER_ADDRESS", vm.toString(CONTROLLER));
        vm.setEnv("AUTOLAUNCH_GUARDIAN_ADDRESS", vm.toString(GUARDIAN));

        string memory resultJson = script.run();

        assertTrue(vm.keyExistsJson(resultJson, ".subjectRegistryAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueShareSplitterDeployerAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueShareFactoryAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueIngressFactoryAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".deferredAutolaunchFactoryAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".paymentLinkFactoryAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".stakingRevenueRouterAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".strategyFactoryAddress"));
        assertFalse(vm.keyExistsJson(resultJson, ".existingTokenRevenueFactoryAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueUsdcTokenAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueTokenSymbol"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueTokenDecimals"));
        assertTrue(vm.keyExistsJson(resultJson, ".regentRevenueStakingAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".trustedTokenFactoryAddress"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueShareFactoryOwner"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueShareFactoryPendingOwner"));
        assertTrue(vm.keyExistsJson(resultJson, ".revenueIngressFactoryOwner"));
        assertTrue(vm.keyExistsJson(resultJson, ".strategyFactoryOwner"));
        assertTrue(vm.keyExistsJson(resultJson, ".owner"));

        assertTrue(vm.parseJsonAddress(resultJson, ".subjectRegistryAddress") != address(0));
        assertTrue(
            vm.parseJsonAddress(resultJson, ".revenueShareSplitterDeployerAddress") != address(0)
        );
        assertTrue(vm.parseJsonAddress(resultJson, ".revenueShareFactoryAddress") != address(0));
        assertTrue(vm.parseJsonAddress(resultJson, ".revenueIngressFactoryAddress") != address(0));
        assertTrue(
            vm.parseJsonAddress(resultJson, ".deferredAutolaunchFactoryAddress") != address(0)
        );
        assertTrue(vm.parseJsonAddress(resultJson, ".stakingRevenueRouterAddress") != address(0));
        assertTrue(vm.parseJsonAddress(resultJson, ".strategyFactoryAddress") != address(0));
        assertEq(vm.parseJsonAddress(resultJson, ".revenueUsdcTokenAddress"), USDC);
        assertEq(vm.parseJsonString(resultJson, ".revenueTokenSymbol"), "USDC");
        assertEq(vm.parseJsonUint(resultJson, ".revenueTokenDecimals"), 6);
        assertEq(vm.parseJsonAddress(resultJson, ".regentRevenueStakingAddress"), address(staking));
        assertEq(
            vm.parseJsonAddress(resultJson, ".trustedTokenFactoryAddress"), address(tokenFactory)
        );
        assertEq(vm.parseJsonAddress(resultJson, ".revenueShareFactoryOwner"), OWNER);
        assertEq(vm.parseJsonAddress(resultJson, ".revenueShareFactoryPendingOwner"), address(0));
        assertEq(vm.parseJsonAddress(resultJson, ".revenueIngressFactoryOwner"), OWNER);
        assertEq(vm.parseJsonAddress(resultJson, ".strategyFactoryOwner"), OWNER);
        assertEq(vm.parseJsonAddress(resultJson, ".owner"), OWNER);
    }

    function testValidateConfigRejectsWrongBaseMainnetUsdc() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg =
            DeployAutolaunchInfraScript.ScriptConfig({
                owner: OWNER,
                revenueUsdcToken: address(0xC0FFEE),
                regentRevenueStaking: address(staking),
                tokenFactory: address(tokenFactory),
                controller: CONTROLLER,
                guardian: GUARDIAN
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
        vm.setEnv("AUTOLAUNCH_CONTROLLER_ADDRESS", vm.toString(CONTROLLER));
        vm.setEnv("AUTOLAUNCH_GUARDIAN_ADDRESS", vm.toString(GUARDIAN));

        vm.expectRevert("BASE_MAINNET_ONLY");
        script.loadConfigFromEnv();
    }
}
