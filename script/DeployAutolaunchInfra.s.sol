// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {
    PermissionlessExistingTokenRevenueFactory
} from "src/autolaunch/revenue/PermissionlessExistingTokenRevenueFactory.sol";
import {DeferredAutolaunchFactory} from "src/autolaunch/revenue/DeferredAutolaunchFactory.sol";
import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";
import {RegentStakingRevenueRouter} from "src/autolaunch/revenue/RegentStakingRevenueRouter.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {BaseUsdc} from "src/shared/libraries/BaseUsdc.sol";

contract DeployAutolaunchInfraScript is Script {
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;

    struct ScriptConfig {
        address owner;
        address revenueUsdcToken;
        address regentRevenueStaking;
        address tokenFactory;
    }

    struct DeployedInfra {
        SubjectRegistry subjectRegistry;
        RevenueShareSplitterV2Deployer revenueShareSplitterDeployer;
        RevenueShareFactory revenueShareFactory;
        RevenueIngressFactory revenueIngressFactory;
        PermissionlessExistingTokenRevenueFactory existingTokenRevenueFactory;
        DeferredAutolaunchFactory deferredAutolaunchFactory;
        RegentStakingRevenueRouter stakingRevenueRouter;
        RegentLBPStrategyFactory strategyFactory;
    }

    function deployFromEnv() external returns (DeployedInfra memory infra) {
        ScriptConfig memory cfg = loadConfigFromEnv();

        return deploy(cfg);
    }

    function deploy(ScriptConfig memory cfg) public returns (DeployedInfra memory infra) {
        validateConfig(cfg);

        vm.startBroadcast(cfg.owner);
        infra.subjectRegistry = new SubjectRegistry(cfg.owner);
        infra.stakingRevenueRouter = new RegentStakingRevenueRouter(
            cfg.owner,
            cfg.revenueUsdcToken,
            address(infra.subjectRegistry),
            cfg.regentRevenueStaking
        );
        infra.revenueShareSplitterDeployer = new RevenueShareSplitterV2Deployer();
        infra.revenueShareFactory = new RevenueShareFactory(
            cfg.owner,
            cfg.revenueUsdcToken,
            infra.subjectRegistry,
            address(infra.stakingRevenueRouter),
            address(infra.revenueShareSplitterDeployer)
        );
        infra.revenueIngressFactory = new RevenueIngressFactory(
            cfg.revenueUsdcToken, address(infra.subjectRegistry), cfg.owner
        );
        infra.existingTokenRevenueFactory = new PermissionlessExistingTokenRevenueFactory(
            cfg.owner,
            cfg.revenueUsdcToken,
            address(infra.revenueIngressFactory),
            infra.subjectRegistry,
            IRegentStakingRevenueRouter(address(infra.stakingRevenueRouter))
        );
        infra.deferredAutolaunchFactory = new DeferredAutolaunchFactory(
            cfg.owner,
            infra.revenueShareFactory,
            infra.revenueIngressFactory,
            IRegentStakingRevenueRouter(address(infra.stakingRevenueRouter)),
            cfg.tokenFactory
        );
        infra.strategyFactory = new RegentLBPStrategyFactory(cfg.owner);
        infra.subjectRegistry.setAuthorizedRegistrar(address(infra.revenueShareFactory), true);
        infra.subjectRegistry
            .setAuthorizedRegistrar(address(infra.existingTokenRevenueFactory), true);
        infra.revenueIngressFactory.setAuthorizedCreator(address(infra.revenueShareFactory), true);
        infra.revenueIngressFactory
            .setAuthorizedCreator(address(infra.existingTokenRevenueFactory), true);
        infra.revenueIngressFactory
            .setAuthorizedCreator(address(infra.deferredAutolaunchFactory), true);
        infra.revenueShareFactory
            .setAuthorizedCreator(address(infra.deferredAutolaunchFactory), true);
        vm.stopBroadcast();
    }

    function validateConfig(ScriptConfig memory cfg) public view {
        require(cfg.owner != address(0), "OWNER_ZERO");
        require(cfg.revenueUsdcToken != address(0), "REVENUE_USDC_ZERO");
        require(cfg.regentRevenueStaking != address(0), "REGENT_STAKING_ZERO");
        require(cfg.tokenFactory != address(0), "TOKEN_FACTORY_ZERO");
        require(cfg.tokenFactory.code.length != 0, "TOKEN_FACTORY_NOT_DEPLOYED");
        require(block.chainid == BASE_MAINNET_CHAIN_ID, "BASE_MAINNET_ONLY");
        BaseUsdc.requireCanonical(cfg.revenueUsdcToken);
    }

    function loadConfigFromEnv() public view returns (ScriptConfig memory cfg) {
        cfg.owner = vm.envAddress("AUTOLAUNCH_INFRA_OWNER");
        cfg.revenueUsdcToken = vm.envAddress("AUTOLAUNCH_REVENUE_USDC_ADDRESS");
        cfg.regentRevenueStaking = vm.envAddress("REGENT_REVENUE_STAKING_ADDRESS");
        cfg.tokenFactory = vm.envAddress("AUTOLAUNCH_TOKEN_FACTORY_ADDRESS");
        validateConfig(cfg);
    }

    function run() external {
        ScriptConfig memory cfg = loadConfigFromEnv();

        DeployedInfra memory infra = deploy(cfg);

        console2.log(
            string.concat(
                _resultAddressJson(infra), _resultConfigJson(cfg), _resultOwnershipJson(infra, cfg)
            )
        );
    }

    function _resultAddressJson(DeployedInfra memory infra) internal view returns (string memory) {
        return string.concat(
            "AUTOLAUNCH_INFRA_RESULT_JSON:{\"subjectRegistryAddress\":\"",
            vm.toString(address(infra.subjectRegistry)),
            "\",\"revenueShareSplitterDeployerAddress\":\"",
            vm.toString(address(infra.revenueShareSplitterDeployer)),
            "\",\"revenueShareFactoryAddress\":\"",
            vm.toString(address(infra.revenueShareFactory)),
            "\",\"revenueIngressFactoryAddress\":\"",
            vm.toString(address(infra.revenueIngressFactory)),
            "\",\"existingTokenRevenueFactoryAddress\":\"",
            vm.toString(address(infra.existingTokenRevenueFactory)),
            "\",\"deferredAutolaunchFactoryAddress\":\"",
            vm.toString(address(infra.deferredAutolaunchFactory)),
            "\",\"stakingRevenueRouterAddress\":\"",
            vm.toString(address(infra.stakingRevenueRouter)),
            "\",\"strategyFactoryAddress\":\"",
            vm.toString(address(infra.strategyFactory))
        );
    }

    function _resultConfigJson(ScriptConfig memory cfg) internal view returns (string memory) {
        return string.concat(
            "\",\"revenueUsdcTokenAddress\":\"",
            vm.toString(cfg.revenueUsdcToken),
            "\",\"revenueTokenSymbol\":\"USDC\",\"revenueTokenDecimals\":6",
            ",\"regentRevenueStakingAddress\":\"",
            vm.toString(cfg.regentRevenueStaking),
            "\",\"trustedTokenFactoryAddress\":\"",
            vm.toString(cfg.tokenFactory)
        );
    }

    function _resultOwnershipJson(DeployedInfra memory infra, ScriptConfig memory cfg)
        internal
        view
        returns (string memory)
    {
        return string.concat(
            "\",\"revenueShareFactoryOwner\":\"",
            vm.toString(infra.revenueShareFactory.owner()),
            "\",\"revenueShareFactoryPendingOwner\":\"",
            vm.toString(infra.revenueShareFactory.pendingOwner()),
            "\",\"revenueIngressFactoryOwner\":\"",
            vm.toString(infra.revenueIngressFactory.owner()),
            "\",\"strategyFactoryOwner\":\"",
            vm.toString(infra.strategyFactory.owner()),
            "\",\"owner\":\"",
            vm.toString(cfg.owner),
            "\"}"
        );
    }
}
