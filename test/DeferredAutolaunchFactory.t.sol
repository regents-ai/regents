// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {
    IDeferredAutolaunchFactory
} from "src/autolaunch/revenue/interfaces/IDeferredAutolaunchFactory.sol";
import {DeferredAutolaunchFactory} from "src/autolaunch/revenue/DeferredAutolaunchFactory.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";
import {ITokenFactory} from "src/shared/interfaces/ITokenFactory.sol";
import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";

contract CountingDeferredTokenFactory is ITokenFactory {
    uint256 public calls;

    function createToken(
        string calldata,
        string calldata,
        uint8,
        uint256,
        address,
        bytes calldata,
        bytes32
    ) external returns (address) {
        ++calls;
        return address(0xBEEF);
    }
}

contract DeferredAutolaunchFactoryTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant TREASURY = address(0x1111);
    address internal constant CONTROLLER = address(0xC011);
    address internal constant GUARDIAN = address(0x600D);

    DeferredAutolaunchFactory internal factory;
    CountingDeferredTokenFactory internal tokenFactory;

    function setUp() external {
        MintableERC20Mock usdc = new MintableERC20Mock("USD Coin", "USDC");
        SubjectRegistry registry = new SubjectRegistry(CONTROLLER, OWNER, GUARDIAN);
        MockRegentStakingRevenueRouter router =
            new MockRegentStakingRevenueRouter(address(usdc), address(0x8888));
        RevenueShareFactory revenueFactory = new RevenueShareFactory(
            OWNER,
            address(usdc),
            registry,
            address(router),
            address(new RevenueShareSplitterV2Deployer())
        );
        RevenueIngressFactory ingressFactory =
            new RevenueIngressFactory(address(usdc), address(registry), OWNER);
        tokenFactory = new CountingDeferredTokenFactory();
        factory = new DeferredAutolaunchFactory(
            OWNER, revenueFactory, ingressFactory, router, address(tokenFactory)
        );
    }

    function testValidConfigurationIsDisabledImmediately() external {
        vm.expectRevert("DEFERRED_AUTOLAUNCH_DISABLED");
        factory.createDeferredAutolaunch(_config());
    }

    function testInvalidConfigurationHitsTheSameImmediateDisable() external {
        IDeferredAutolaunchFactory.DeferredAutolaunchConfig memory cfg = _config();
        cfg.tokenName = "";
        cfg.totalSupply = 0;
        cfg.treasury = address(0);
        vm.expectRevert("DEFERRED_AUTOLAUNCH_DISABLED");
        factory.createDeferredAutolaunch(cfg);
    }

    function testDisabledSelectorMakesZeroExternalCalls() external {
        vm.expectRevert("DEFERRED_AUTOLAUNCH_DISABLED");
        factory.createDeferredAutolaunch(_config());
        assertEq(tokenFactory.calls(), 0);
    }

    function testDisabledSelectorCreatesNoCode() external {
        uint64 nonceBefore = vm.getNonce(address(factory));
        address nextCreateAddress = vm.computeCreateAddress(address(factory), nonceBefore);
        vm.expectRevert("DEFERRED_AUTOLAUNCH_DISABLED");
        factory.createDeferredAutolaunch(_config());
        assertEq(vm.getNonce(address(factory)), nonceBefore);
        assertEq(nextCreateAddress.code.length, 0);
    }

    function testDisabledSelectorChangesNoFactoryState() external {
        bytes32[8] memory beforeSlots;
        for (uint256 i; i < beforeSlots.length; ++i) {
            beforeSlots[i] = vm.load(address(factory), bytes32(i));
        }
        vm.expectRevert("DEFERRED_AUTOLAUNCH_DISABLED");
        factory.createDeferredAutolaunch(_config());
        for (uint256 i; i < beforeSlots.length; ++i) {
            assertEq(vm.load(address(factory), bytes32(i)), beforeSlots[i]);
        }
    }

    function testConstructorStillRejectsCodelessTokenFactory() external {
        address codelessTokenFactory = makeAddr("deferred-codeless-token-factory");
        assertEq(codelessTokenFactory.code.length, 0);
        RevenueShareFactory revenueFactory = factory.revenueShareFactory();
        RevenueIngressFactory ingressFactory = factory.revenueIngressFactory();
        IRegentStakingRevenueRouter stakingRouter = factory.stakingRevenueRouter();
        vm.expectRevert("TOKEN_FACTORY_NOT_CONTRACT");
        new DeferredAutolaunchFactory(
            OWNER, revenueFactory, ingressFactory, stakingRouter, codelessTokenFactory
        );
    }

    function _config()
        internal
        pure
        returns (IDeferredAutolaunchFactory.DeferredAutolaunchConfig memory)
    {
        return IDeferredAutolaunchFactory.DeferredAutolaunchConfig({
            tokenName: "Deferred Agent",
            tokenSymbol: "DAGENT",
            totalSupply: 1_000_000e18,
            treasury: TREASURY,
            tokenFactoryData: abi.encode("config"),
            tokenFactorySalt: keccak256("salt"),
            subjectLabel: "Deferred agent",
            identityChainId: 8453,
            identityRegistry: address(0x8004),
            identityAgentId: 7
        });
    }
}
