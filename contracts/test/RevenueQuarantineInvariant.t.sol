// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {RevenueIngressAccount} from "src/autolaunch/revenue/RevenueIngressAccount.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {RegentStakingRevenueRouter} from "src/autolaunch/revenue/RegentStakingRevenueRouter.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

contract RevenueQuarantineInvariant is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("quarantine-subject");
    address internal constant AGENT_SAFE = address(0x1111);
    address internal constant STAKER = address(0x2222);
    address internal constant REDIRECT = address(0x3333);
    uint256 internal constant STAKE_AMOUNT = 100e18;
    uint256 internal constant DEPOSIT_AMOUNT = 100e6;

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal regent;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal registry;
    RevenueIngressFactory internal ingressFactory;
    RegentRevenueStaking internal staking;
    RegentStakingRevenueRouter internal router;
    RevenueShareSplitterV2 internal splitter;
    RevenueIngressAccount internal ingress;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        regent = new MintableERC20Mock("REGENT", "REGENT");
        stakeToken = new MintableERC20Mock("Agent", "AGENT");
        registry = new SubjectRegistry(address(this), address(0xA11CE), address(0x600D));
        ingressFactory = new RevenueIngressFactory(address(usdc), address(registry), address(this));
        staking = new RegentRevenueStaking(
            address(regent), address(usdc), AGENT_SAFE, 1_000_000e18, address(this)
        );
        router = new RegentStakingRevenueRouter(
            address(this), address(usdc), address(registry), address(staking)
        );
        splitter = new RevenueShareSplitterV2(
            address(stakeToken),
            address(usdc),
            address(ingressFactory),
            address(registry),
            SUBJECT_ID,
            AGENT_SAFE,
            address(router),
            1000e18,
            "Subject",
            AGENT_SAFE
        );

        address predictedIngress = ingressFactory.predictDefaultIngress(SUBJECT_ID, AGENT_SAFE);
        vm.mockCall(
            address(0x1003), abi.encodeWithSignature("operator()"), abi.encode(address(0x7007))
        );
        registry.registerSubject(
            ISubjectRegistry.SubjectRegistration({
                subjectId: SUBJECT_ID,
                stakeToken: address(stakeToken),
                splitter: address(splitter),
                agentSafe: AGENT_SAFE,
                ingress: predictedIngress,
                paymentLinkFactory: address(0x1002),
                strategy: address(0x1003),
                launchFeeRegistry: address(0x1004),
                feeVault: address(0x1005),
                feeHook: address(0x1006),
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                label: "Subject",
                safeRuntime: address(0x7007)
            })
        );
        ingress = RevenueIngressAccount(
            payable(ingressFactory.createDefaultIngressAccount(SUBJECT_ID, "default-usdc-ingress"))
        );

        stakeToken.mint(STAKER, STAKE_AMOUNT);
        vm.startPrank(STAKER);
        stakeToken.approve(address(splitter), STAKE_AMOUNT);
        splitter.stake(STAKE_AMOUNT, STAKER);
        vm.stopPrank();

        usdc.mint(address(this), DEPOSIT_AMOUNT);
        usdc.approve(address(splitter), DEPOSIT_AMOUNT);
        splitter.depositUSDC(DEPOSIT_AMOUNT, bytes32("direct"), bytes32("pre-quarantine"));
        usdc.mint(address(ingress), 50e6);
        usdc.mint(address(splitter), 1);

        vm.prank(AGENT_SAFE);
        splitter.proposeTreasuryRecipientRotation(REDIRECT);
        vm.prank(AGENT_SAFE);
        registry.quarantineSubject(SUBJECT_ID);
    }

    function testQuarantineBlocksNewMovementButPreservesFixedClaimsAndExit() external {
        usdc.mint(address(this), 1e6);
        usdc.approve(address(splitter), 1e6);
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.depositUSDC(1e6, bytes32("blocked"), bytes32("blocked"));

        vm.expectRevert("SUBJECT_NOT_ACTIVE");
        ingress.sweepUSDC(bytes32("blocked"));

        vm.prank(STAKER);
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.stake(1, STAKER);

        vm.startPrank(AGENT_SAFE);
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.proposeTreasuryRecipientRotation(address(0x4444));
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.executeTreasuryRecipientRotation();
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.reassignUndistributedDustToTreasury(1);
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.redepositSurplusUSDC(1, bytes32("blocked"), bytes32("blocked"));
        vm.expectRevert("SUBJECT_INACTIVE");
        splitter.sweepSurplusUSDC(1, AGENT_SAFE);
        vm.stopPrank();

        vm.startPrank(STAKER);
        vm.expectRevert("RECIPIENT_NOT_ACCOUNT");
        splitter.claimUSDC(REDIRECT);
        uint256 claimed = splitter.claimUSDC(STAKER);
        vm.expectRevert("RECIPIENT_NOT_ACCOUNT");
        splitter.unstake(STAKE_AMOUNT, REDIRECT);
        splitter.unstake(STAKE_AMOUNT, STAKER);
        vm.stopPrank();

        uint256 treasuryClaim = splitter.treasuryResidualUsdc();
        vm.prank(AGENT_SAFE);
        splitter.sweepTreasuryResidualUSDC(treasuryClaim);

        assertEq(claimed, 9_800_000);
        assertEq(usdc.balanceOf(STAKER), claimed);
        assertEq(stakeToken.balanceOf(STAKER), STAKE_AMOUNT);
        assertEq(usdc.balanceOf(AGENT_SAFE), treasuryClaim);
        assertEq(usdc.balanceOf(address(staking)), 2e6);
        assertEq(usdc.balanceOf(address(ingress)), 50e6);
        assertEq(splitter.surplusUsdc(), 1);
    }

    function invariantQuarantineKeepsCreationTimeDestinationsFixed() external view {
        assertEq(
            uint256(registry.lifecycleOf(SUBJECT_ID)),
            uint256(ISubjectRegistry.Lifecycle.Quarantined)
        );
        assertEq(splitter.treasuryRecipient(), AGENT_SAFE);
        assertEq(ingress.destination(), address(splitter));
        assertEq(ingress.splitter(), address(splitter));
        assertEq(router.maxUsdcPerSettlement(), 2000e6);
    }
}
