// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AuctionParameters} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {RegentLBPStrategy} from "src/autolaunch/RegentLBPStrategy.sol";
import {RegentLBPStrategyFactory} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {AutolaunchBindingsTest} from "test/AutolaunchBindings.t.sol";
import {
    IContinuousClearingAuctionFactory
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuctionFactory.sol";

contract RegentLBPStrategyFactoryTest is Test {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address internal constant CCA_FACTORY = 0x000000001F26a0044BaA66024e7b6599c61963F8;

    function setUp() external {
        vm.chainId(8453);
        MintableERC20Mock implementation = new MintableERC20Mock("REGENT", "REGENT");
        vm.etch(REGENT, address(implementation).code);
        AutolaunchBindingsTest bindingsFixture = new AutolaunchBindingsTest();
        bindingsFixture.setUp();
    }

    function testInitializeDistributionCreatesStrategy() external {
        RegentLBPStrategyFactory factory = new RegentLBPStrategyFactory(address(this));

        RegentLBPStrategyFactory.RegentLBPStrategyConfig memory cfg =
            RegentLBPStrategyFactory.RegentLBPStrategyConfig({
                quoteToken: REGENT,
                auctionInitializerFactory: CCA_FACTORY,
                auctionParameters: AuctionParameters({
                    currency: REGENT,
                    tokensRecipient: address(0),
                    fundsRecipient: address(0),
                    startBlock: 1,
                    endBlock: 10,
                    claimBlock: 10,
                    tickSpacing: 100,
                    validationHook: address(0),
                    floorPrice: 100,
                    requiredCurrencyRaised: 0,
                    auctionStepsData: bytes("")
                }),
                officialPoolHook: address(0x4444),
                agentSafe: address(0x5555),
                vestingWallet: address(0x6666),
                operator: address(0x7777),
                positionManager: POSITION_MANAGER,
                poolManager: POOL_MANAGER,
                subjectRegistry: address(0x9999),
                officialPoolFee: 3000,
                officialPoolTickSpacing: 60,
                migrationBlock: 20,
                sweepBlock: 30,
                tokenSplitToAuctionMps: 6_666_666,
                auctionTokenAmount: 100,
                reserveTokenAmount: 50
            });

        address strategyAddress = address(
            factory.initializeDistribution(address(0x1111), 150, abi.encode(cfg), bytes32(0))
        );

        RegentLBPStrategy strategy = RegentLBPStrategy(strategyAddress);
        assertEq(strategy.token(), address(0x1111));
        assertEq(strategy.quoteToken(), REGENT);
        assertEq(strategy.auctionInitializerFactory(), CCA_FACTORY);
        assertEq(strategy.agentSafe(), address(0x5555));
        assertEq(strategy.vestingWallet(), address(0x6666));
        assertEq(strategy.auctionCreator(), address(this));
        assertEq(strategy.operator(), address(0x7777));
        assertEq(strategy.officialPoolFee(), 3000);
        assertEq(strategy.officialPoolTickSpacing(), 60);
        assertEq(strategy.subjectRegistry(), address(0x9999));
        assertEq(strategy.subjectId(), keccak256(abi.encode(block.chainid, address(0x1111))));
        assertEq(strategy.LP_CURRENCY_BPS(), 4000);
        assertEq(strategy.totalStrategySupply(), 150);
        assertEq(strategy.auctionTokenAmount(), 100);
        assertEq(strategy.reserveTokenAmount(), 50);
    }

    function testRejectsUnauthorizedCreator() external {
        RegentLBPStrategyFactory factory = new RegentLBPStrategyFactory(address(this));

        RegentLBPStrategyFactory.RegentLBPStrategyConfig memory cfg =
            RegentLBPStrategyFactory.RegentLBPStrategyConfig({
                quoteToken: REGENT,
                auctionInitializerFactory: CCA_FACTORY,
                auctionParameters: AuctionParameters({
                    currency: REGENT,
                    tokensRecipient: address(0),
                    fundsRecipient: address(0),
                    startBlock: 1,
                    endBlock: 10,
                    claimBlock: 10,
                    tickSpacing: 100,
                    validationHook: address(0),
                    floorPrice: 100,
                    requiredCurrencyRaised: 0,
                    auctionStepsData: bytes("")
                }),
                officialPoolHook: address(0x4444),
                agentSafe: address(0x5555),
                vestingWallet: address(0x6666),
                operator: address(0x7777),
                positionManager: POSITION_MANAGER,
                poolManager: POOL_MANAGER,
                subjectRegistry: address(0x9999),
                officialPoolFee: 3000,
                officialPoolTickSpacing: 60,
                migrationBlock: 20,
                sweepBlock: 30,
                tokenSplitToAuctionMps: 6_666_666,
                auctionTokenAmount: 100,
                reserveTokenAmount: 50
            });

        vm.prank(address(0xBAD));
        vm.expectRevert("ONLY_AUTHORIZED_CREATOR");
        factory.initializeDistribution(address(0x1111), 150, abi.encode(cfg), bytes32(0));
    }

    function testRejectsNoncanonicalCcaFactoryAndRuntime() external {
        RegentLBPStrategyFactory factory = new RegentLBPStrategyFactory(address(this));
        RegentLBPStrategyFactory.RegentLBPStrategyConfig memory cfg = _validConfig();

        cfg.auctionInitializerFactory = address(0x3333);
        vm.expectRevert("CCA_FACTORY_MISMATCH");
        factory.initializeDistribution(address(0x1111), 150, abi.encode(cfg), bytes32(0));

        cfg.auctionInitializerFactory = CCA_FACTORY;
        vm.etch(CCA_FACTORY, hex"00");
        vm.expectRevert("CCA_FACTORY_RUNTIME_SIZE");
        factory.initializeDistribution(address(0x1111), 150, abi.encode(cfg), bytes32(0));
    }

    function testRejectsNonzeroCcaProtocolFeeController() external {
        RegentLBPStrategyFactory factory = new RegentLBPStrategyFactory(address(this));
        vm.mockCall(
            CCA_FACTORY,
            abi.encodeWithSelector(
                IContinuousClearingAuctionFactory.protocolFeeController.selector
            ),
            abi.encode(address(0xFEE))
        );

        vm.expectRevert("CCA_PROTOCOL_FEE_CONTROLLER");
        factory.initializeDistribution(address(0x1111), 150, abi.encode(_validConfig()), bytes32(0));
    }

    function _validConfig()
        internal
        pure
        returns (RegentLBPStrategyFactory.RegentLBPStrategyConfig memory cfg)
    {
        cfg = RegentLBPStrategyFactory.RegentLBPStrategyConfig({
            quoteToken: REGENT,
            auctionInitializerFactory: CCA_FACTORY,
            auctionParameters: AuctionParameters({
                currency: REGENT,
                tokensRecipient: address(0),
                fundsRecipient: address(0),
                startBlock: 1,
                endBlock: 10,
                claimBlock: 10,
                tickSpacing: 100,
                validationHook: address(0),
                floorPrice: 100,
                requiredCurrencyRaised: 0,
                auctionStepsData: bytes("")
            }),
            officialPoolHook: address(0x4444),
            agentSafe: address(0x5555),
            vestingWallet: address(0x6666),
            operator: address(0x7777),
            positionManager: POSITION_MANAGER,
            poolManager: POOL_MANAGER,
            subjectRegistry: address(0x9999),
            officialPoolFee: 3000,
            officialPoolTickSpacing: 60,
            migrationBlock: 20,
            sweepBlock: 30,
            tokenSplitToAuctionMps: 6_666_666,
            auctionTokenAmount: 100,
            reserveTokenAmount: 50
        });
    }
}
