// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {RegentRevenueStaking} from "src/staking/RegentRevenueStaking.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";

contract RegentRevenueStakingHandler is Test {
    uint256 internal constant REGENT = 1e18;
    uint256 internal constant USDC = 1e6;
    uint256 internal constant SUPPLY_DENOMINATOR = 100_000_000_000 * REGENT;

    RegentRevenueStaking public immutable staking;
    MintableBurnableERC20Mock public immutable regent;
    MintableBurnableERC20Mock public immutable usdc;
    address public immutable owner;
    address public immutable treasury;
    uint256 public successfulUsdcDeposits;

    address[] internal actors;

    constructor(
        RegentRevenueStaking staking_,
        MintableBurnableERC20Mock regent_,
        MintableBurnableERC20Mock usdc_,
        address owner_,
        address treasury_
    ) {
        staking = staking_;
        regent = regent_;
        usdc = usdc_;
        owner = owner_;
        treasury = treasury_;

        actors.push(address(0xA1));
        actors.push(address(0xB2));
        actors.push(address(0xC3));
        actors.push(address(0xD4));

        for (uint256 i; i < actors.length; ++i) {
            vm.prank(actors[i]);
            regent.approve(address(staking), type(uint256).max);
            vm.prank(actors[i]);
            usdc.approve(address(staking), type(uint256).max);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 index) external view returns (address) {
        return actors[index];
    }

    function stake(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 amount = bound(amountSeed, 1, SUPPLY_DENOMINATOR / 20);
        regent.mint(actor, amount);

        vm.prank(actor);
        try staking.stake(amount, actor) {} catch {}
    }

    function unstake(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 balance = staking.stakedBalance(actor);
        if (balance == 0) return;

        uint256 amount = bound(amountSeed, 1, balance);
        vm.prank(actor);
        try staking.unstake(amount, actor) {} catch {}
    }

    function depositUsdc(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 amount = bound(amountSeed, 1, 10_000_000 * USDC);
        usdc.mint(actor, amount);

        vm.prank(actor);
        try staking.depositUSDC(amount, bytes32("invariant"), bytes32(uint256(uint160(actor)))) {}
        catch {
            return;
        }
        successfulUsdcDeposits += 1;
    }

    function fundRegent(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 amount = bound(amountSeed, 1, SUPPLY_DENOMINATOR / 10);
        regent.mint(actor, amount);

        vm.prank(actor);
        try staking.fundRegentRewards(amount) {} catch {}
    }

    function claimUsdc(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        vm.prank(actor);
        try staking.claimUSDC(actor) {} catch {}
    }

    function claimRegent(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        vm.prank(actor);
        try staking.claimRegent(actor) {} catch {}
    }

    function claimAndRestakeRegent(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        vm.prank(actor);
        try staking.claimAndRestakeRegent() {} catch {}
    }

    function withdrawTreasury(uint256 amountSeed) external {
        uint256 balance = staking.treasuryResidualUsdc();
        if (balance == 0) return;

        uint256 amount = bound(amountSeed, 1, balance);
        vm.prank(treasury);
        try staking.withdrawTreasuryResidual(amount, treasury) {} catch {}
    }

    function setApr(uint256 bpsSeed) external {
        uint16 bps = uint16(bound(bpsSeed, 0, staking.MAX_EMISSION_APR_BPS()));
        vm.prank(owner);
        staking.setEmissionAprBps(bps);
    }

    function warpForward(uint256 elapsedSeed) external {
        vm.warp(block.timestamp + bound(elapsedSeed, 0, 30 days));
    }

    function sumStakedBalances() external view returns (uint256 total) {
        for (uint256 i; i < actors.length; ++i) {
            total += staking.stakedBalance(actors[i]);
        }
    }

    function sumClaimableUsdc() external view returns (uint256 total) {
        for (uint256 i; i < actors.length; ++i) {
            total += staking.previewClaimableUSDC(actors[i]);
        }
    }

    function sumClaimableRegent() external view returns (uint256 total) {
        for (uint256 i; i < actors.length; ++i) {
            total += staking.previewClaimableRegent(actors[i]);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }
}

contract RegentRevenueStakingInvariantTest is StdInvariant, Test {
    uint256 internal constant REGENT = 1e18;
    uint256 internal constant SUPPLY_DENOMINATOR = 100_000_000_000 * REGENT;

    address internal constant OWNER = address(0xA11CE);
    address internal constant TREASURY = address(0xBEEF);

    MintableBurnableERC20Mock internal regent;
    MintableBurnableERC20Mock internal usdc;
    RegentRevenueStaking internal staking;
    RegentRevenueStakingHandler internal handler;

    function setUp() external {
        regent = new MintableBurnableERC20Mock("Regent", "REGENT", 18);
        usdc = new MintableBurnableERC20Mock("USD Coin", "USDC", 6);
        staking = new RegentRevenueStaking(
            address(regent), address(usdc), TREASURY, SUPPLY_DENOMINATOR, OWNER
        );
        handler = new RegentRevenueStakingHandler(staking, regent, usdc, OWNER, TREASURY);

        targetContract(address(handler));
    }

    function invariant_stakeNeverExceedsDenominator() external view {
        assertLe(staking.totalStaked(), SUPPLY_DENOMINATOR);
        assertEq(staking.totalStaked(), handler.sumStakedBalances());
    }

    function invariant_contractRegentBalanceAlwaysCoversPrincipal() external view {
        assertGe(regent.balanceOf(address(staking)), staking.totalStaked());
    }

    function invariant_regentRewardPoolMatchesBalanceAbovePrincipal() external view {
        uint256 balance = regent.balanceOf(address(staking));
        uint256 expectedPool = balance > staking.totalStaked() ? balance - staking.totalStaked() : 0;
        assertEq(staking.regentRewardPool(), expectedPool);
        assertEq(staking.availableRegentRewardInventory(), expectedPool);
    }

    function invariant_usdcBalanceCoversTrackedClaimsAndTreasury() external view {
        assertGe(usdc.balanceOf(address(staking)), staking.reservedUsdc());
    }

    function invariant_materializedRegentLiabilityMatchesSyncedActors() external view {
        assertLe(staking.unclaimedRegentLiability(), handler.sumClaimableRegent());
    }
}
