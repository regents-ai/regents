// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {AuctionParameters} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {AgentTokenVestingWallet} from "src/autolaunch/AgentTokenVestingWallet.sol";
import {RegentLBPStrategy} from "src/autolaunch/RegentLBPStrategy.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {
    MockContinuousClearingAuctionFactory,
    MockDistributionContract
} from "test/mocks/MockContinuousClearingAuctionFactory.sol";

contract RegentLBPStrategyHandler is Test {
    RegentLBPStrategy internal immutable strategy;
    SubjectRegistry internal immutable registry;
    bytes32 internal immutable subjectId;
    address internal immutable operator;
    address internal immutable agentSafe;
    MockDistributionContract internal immutable auction;
    bool public maxBoundSucceeded;
    bool public maxBoundMutatedLifecycle;

    constructor(
        RegentLBPStrategy strategy_,
        SubjectRegistry registry_,
        bytes32 subjectId_,
        address operator_,
        address agentSafe_
    ) {
        strategy = strategy_;
        registry = registry_;
        subjectId = subjectId_;
        operator = operator_;
        agentSafe = agentSafe_;
        auction = MockDistributionContract(strategy_.auctionAddress());
    }

    function progress(uint256 tickBound) external {
        vm.prank(operator);
        try strategy.progressFinalization(bound(tickBound, 2, type(uint128).max)) {} catch {}
    }

    function rejectMaxBound() external {
        uint64 checkpointBefore = auction.lastCheckpointedBlock();
        bool migratedBefore = strategy.migrated();
        bool retiredBefore = strategy.failedAuctionRecovered();

        vm.prank(operator);
        try strategy.progressFinalization(type(uint256).max) {
            maxBoundSucceeded = true;
        } catch {}

        if (
            auction.lastCheckpointedBlock() != checkpointBefore
                || strategy.migrated() != migratedBefore
                || strategy.failedAuctionRecovered() != retiredBefore
        ) maxBoundMutatedLifecycle = true;
    }

    function migrate() external {
        vm.prank(operator);
        try strategy.migrate() {} catch {}
    }

    function retire() external {
        vm.prank(operator);
        try strategy.recoverFailedAuction() {} catch {}
    }

    function quarantine() external {
        vm.prank(agentSafe);
        try registry.quarantineSubject(subjectId) {} catch {}
    }
}

contract RegentLBPStrategyInvariant is StdInvariant, Test {
    address internal constant AGENT_SAFE = address(0x1234);
    address internal constant OPERATOR = address(0x9ABC);
    address internal constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint128 internal constant AUCTION_AMOUNT = 100e18;
    uint128 internal constant RESERVE_AMOUNT = 50e18;
    uint256 internal constant REFUND_INVENTORY = 5e18;

    MintableERC20Mock internal token;
    MintableERC20Mock internal quoteToken;
    MockContinuousClearingAuctionFactory internal auctionFactory;
    MockDistributionContract internal auction;
    RegentLBPStrategy internal strategy;
    SubjectRegistry internal registry;
    RegentLBPStrategyHandler internal handler;
    bytes32 internal subjectId;

    function setUp() external {
        token = new MintableERC20Mock("Launch Token", "LT");
        quoteToken = new MintableERC20Mock("REGENT", "REGENT");
        auctionFactory = new MockContinuousClearingAuctionFactory();
        auctionFactory.configureFinalization(3);
        registry = new SubjectRegistry(address(this), address(0xA11CE), address(0x600D));
        AgentTokenVestingWallet vesting =
            new AgentTokenVestingWallet(AGENT_SAFE, 1_700_000_000, 365 days, address(token));

        AuctionParameters memory parameters = AuctionParameters({
            currency: address(quoteToken),
            tokensRecipient: address(0),
            fundsRecipient: address(0),
            startBlock: 1,
            endBlock: 101,
            claimBlock: 101,
            tickSpacing: 1000,
            validationHook: address(0),
            floorPrice: 1000,
            requiredCurrencyRaised: 100e18,
            auctionStepsData: bytes("")
        });
        strategy = new RegentLBPStrategy(
            RegentLBPStrategy.StrategyConfig({
                token: address(token),
                quoteToken: address(quoteToken),
                auctionInitializerFactory: address(auctionFactory),
                auctionParameters: parameters,
                officialPoolHook: address(0x4444),
                agentSafe: AGENT_SAFE,
                vestingWallet: address(vesting),
                operator: OPERATOR,
                positionManager: address(0x7777),
                poolManager: address(0x8888),
                subjectRegistry: address(registry),
                officialPoolFee: 3000,
                officialPoolTickSpacing: 60,
                auctionCreator: address(this),
                migrationBlock: 202,
                sweepBlock: 303,
                tokenSplitToAuctionMps: 6_666_666,
                totalStrategySupply: AUCTION_AMOUNT + RESERVE_AMOUNT,
                auctionTokenAmount: AUCTION_AMOUNT,
                reserveTokenAmount: RESERVE_AMOUNT
            })
        );

        token.mint(address(strategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
        strategy.onTokensReceived();
        auction = MockDistributionContract(strategy.auctionAddress());
        quoteToken.mint(address(auction), REFUND_INVENTORY);
        vesting.bindStrategy(address(strategy));
        subjectId = strategy.subjectId();
        registry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: subjectId,
                stakeToken: address(token),
                splitter: address(0x1111),
                agentSafe: AGENT_SAFE,
                ingress: address(0x2222),
                paymentLinkFactory: address(0x3333),
                strategy: address(strategy),
                launchFeeRegistry: address(0x4444),
                feeVault: address(0x5555),
                feeHook: address(0x6666),
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                label: "Launch Token",
                safeRuntime: OPERATOR
            })
        );

        vm.roll(303);
        handler = new RegentLBPStrategyHandler(strategy, registry, subjectId, OPERATOR, AGENT_SAFE);
        targetContract(address(handler));
    }

    function invariantNoClassificationBeforeFinalCheckpoint() external view {
        if (auction.lastCheckpointedBlock() != auction.endBlock()) {
            assertFalse(strategy.migrated());
            assertFalse(strategy.failedAuctionRecovered());
        }
    }

    function invariantMaxBoundCannotAdvanceLifecycle() external view {
        assertFalse(handler.maxBoundSucceeded());
        assertFalse(handler.maxBoundMutatedLifecycle());
    }

    function invariantMigrationAndRetirementAreMutuallyExclusive() external view {
        assertFalse(strategy.migrated() && strategy.failedAuctionRecovered());
    }

    function invariantQuarantineBlocksMigrationAndRetirement() external view {
        if (registry.lifecycleOf(subjectId) == ISubjectRegistry.Lifecycle.Quarantined) {
            assertFalse(strategy.migrated());
            assertFalse(strategy.failedAuctionRecovered());
        }
    }

    function invariantRetirementPreservesRefundsAndUsesFixedBurn() external view {
        assertEq(quoteToken.balanceOf(address(auction)), REFUND_INVENTORY);
        assertEq(quoteToken.balanceOf(AGENT_SAFE), 0);
        if (strategy.failedAuctionRecovered()) {
            assertEq(token.balanceOf(BURN_ADDRESS), AUCTION_AMOUNT + RESERVE_AMOUNT);
            assertEq(
                uint256(registry.lifecycleOf(subjectId)),
                uint256(ISubjectRegistry.Lifecycle.Retired)
            );
        }
    }
}
