// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RegentDailyDistributor} from "src/autolaunch/revenue/RegentDailyDistributor.sol";

/// @dev Minimal ERC20 sufficient for SafeTransferLib (returns bool, has code).
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockStakingReader {
    address public stakeToken;

    constructor(address stakeToken_) {
        stakeToken = stakeToken_;
    }
}

contract RegentDailyDistributorTest is Test {
    RegentDailyDistributor internal distributor;
    MockERC20 internal regent;
    MockStakingReader internal staking;

    address internal owner = address(0xB0B);
    address internal poster = address(0x9057E5);
    address internal treasury = address(0x77EA5);
    address internal depositor = address(0xF00D);

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B0);
    address internal carol = address(0xCA401);
    address internal dave = address(0xDA5E);

    uint256 internal constant A_AMT = 40 ether;
    uint256 internal constant B_AMT = 30 ether;
    uint256 internal constant C_AMT = 20 ether;
    uint256 internal constant D_AMT = 10 ether;
    uint256 internal constant LEAVES_TOTAL = 100 ether;
    // The stakers' share is a supply fraction of gross revenue, never the full pot.
    uint256 internal constant GROSS = 250 ether;

    bytes32 internal leafA;
    bytes32 internal leafB;
    bytes32 internal leafC;
    bytes32 internal leafD;
    bytes32 internal root;
    bytes32 internal constant INPUTS_HASH = keccak256("inputs-v2");

    uint64 internal snapFrom;
    uint64 internal snapTo;

    function _leaf(uint256 index, address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
    }

    function setUp() public {
        regent = new MockERC20();
        staking = new MockStakingReader(address(regent));
        distributor =
            new RegentDailyDistributor(address(regent), address(staking), poster, owner, treasury);

        leafA = _leaf(0, alice, A_AMT);
        leafB = _leaf(1, bob, B_AMT);
        leafC = _leaf(2, carol, C_AMT);
        leafD = _leaf(3, dave, D_AMT);
        root = _hashPair(_hashPair(leafA, leafB), _hashPair(leafC, leafD));

        vm.roll(1000);
        snapFrom = 100;
        snapTo = 900;

        regent.mint(depositor, 100_000 ether);
        vm.prank(depositor);
        regent.approve(address(distributor), type(uint256).max);
    }

    function _proofA() internal view returns (bytes32[] memory p) {
        p = new bytes32[](2);
        p[0] = leafB;
        p[1] = _hashPair(leafC, leafD);
    }

    function _proofB() internal view returns (bytes32[] memory p) {
        p = new bytes32[](2);
        p[0] = leafA;
        p[1] = _hashPair(leafC, leafD);
    }

    function _proofC() internal view returns (bytes32[] memory p) {
        p = new bytes32[](2);
        p[0] = leafD;
        p[1] = _hashPair(leafA, leafB);
    }

    function _deposit(uint256 amount) internal {
        vm.prank(depositor);
        distributor.deposit(amount);
    }

    function _post(uint256 allocated) internal returns (uint256 epochId) {
        vm.prank(poster);
        epochId = distributor.postRoot(root, INPUTS_HASH, allocated, snapFrom, snapTo);
    }

    // --- Constructor validation ---------------------------------------------

    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert(bytes("REGENT_ZERO"));
        new RegentDailyDistributor(address(0), address(staking), poster, owner, treasury);
        vm.expectRevert(bytes("STAKING_ZERO"));
        new RegentDailyDistributor(address(regent), address(0), poster, owner, treasury);
        vm.expectRevert(bytes("POSTER_ZERO"));
        new RegentDailyDistributor(address(regent), address(staking), address(0), owner, treasury);
        vm.expectRevert(bytes("OWNER_ZERO"));
        new RegentDailyDistributor(address(regent), address(staking), poster, address(0), treasury);
        vm.expectRevert(bytes("TREASURY_ZERO"));
        new RegentDailyDistributor(address(regent), address(staking), poster, owner, address(0));
    }

    function test_ConstructorRejectsSelfTreasury() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(bytes("TREASURY_IS_SELF"));
        new RegentDailyDistributor(address(regent), address(staking), poster, owner, predicted);
    }

    function test_ConstructorRejectsStakeTokenMismatch() public {
        MockStakingReader bad = new MockStakingReader(address(0xdead));
        vm.expectRevert(bytes("STAKE_TOKEN_MISMATCH"));
        new RegentDailyDistributor(address(regent), address(bad), poster, owner, treasury);
    }

    function test_ImmutablesMatchConstructorArgs() public view {
        assertEq(distributor.regent(), address(regent));
        assertEq(distributor.staking(), address(staking));
        assertEq(distributor.poster(), poster);
        assertEq(distributor.owner(), owner);
        assertEq(distributor.treasury(), treasury);
    }

    // --- Deposits -------------------------------------------------------------

    function test_DepositCreditsAndEmits() public {
        vm.expectEmit(true, false, false, true, address(distributor));
        emit RegentDailyDistributor.Deposited(depositor, GROSS);
        _deposit(GROSS);
        assertEq(distributor.totalDeposited(), GROSS);
        assertEq(distributor.uncommitted(), GROSS);
        assertEq(regent.balanceOf(address(distributor)), GROSS);
    }

    function test_DepositRejectsZero() public {
        vm.prank(depositor);
        vm.expectRevert(bytes("AMOUNT_ZERO"));
        distributor.deposit(0);
    }

    function test_DepositIsPermissionless() public {
        address anyone = address(0xFEED);
        regent.mint(anyone, 1 ether);
        vm.prank(anyone);
        regent.approve(address(distributor), 1 ether);
        vm.prank(anyone);
        distributor.deposit(1 ether);
        assertEq(distributor.totalDeposited(), 1 ether);
    }

    /// @notice Direct transfers are NOT deposits: no accounting event, no credit, and
    ///         no path — post, claim, or sweep — can move them.
    function test_DirectTransferIsNotCreditedAnywhere() public {
        vm.prank(depositor);
        regent.transfer(address(distributor), 5 ether);
        assertEq(distributor.totalDeposited(), 0);
        assertEq(distributor.uncommitted(), 0);
        vm.prank(owner);
        vm.expectRevert(bytes("NOTHING_TO_SWEEP"));
        distributor.sweep();
    }

    // --- Daily roots ----------------------------------------------------------

    function test_HonestPathPostsClaimsImmediatelyAndSweeps() public {
        _deposit(GROSS);
        uint256 epochId = _post(LEAVES_TOTAL);
        assertEq(epochId, 0);

        // Claims open immediately: no challenge window, no wait.
        distributor.claim(epochId, 0, alice, A_AMT, _proofA());
        distributor.claim(epochId, 1, bob, B_AMT, _proofB());
        assertEq(regent.balanceOf(alice), A_AMT);
        assertEq(regent.balanceOf(bob), B_AMT);

        // The treasury remainder sweeps; unclaimed leaves stay reserved.
        vm.prank(owner);
        uint256 swept = distributor.sweep();
        assertEq(swept, GROSS - LEAVES_TOTAL);
        assertEq(regent.balanceOf(treasury), GROSS - LEAVES_TOTAL);

        distributor.claim(epochId, 2, carol, C_AMT, _proofC());
        assertEq(regent.balanceOf(carol), C_AMT);
    }

    function test_RootCommitmentEmittedAndStored() public {
        _deposit(GROSS);
        vm.expectEmit(true, false, false, true, address(distributor));
        emit RegentDailyDistributor.RootPosted(
            0, root, INPUTS_HASH, LEAVES_TOTAL, snapFrom, snapTo, address(staking)
        );
        _post(LEAVES_TOTAL);

        (bytes32 r, bytes32 ih, uint256 alloc, uint256 claimed, uint64 fb, uint64 tb) =
            distributor.epochs(0);
        assertEq(r, root);
        assertEq(ih, INPUTS_HASH);
        assertEq(alloc, LEAVES_TOTAL);
        assertEq(claimed, 0);
        assertEq(fb, snapFrom);
        assertEq(tb, snapTo);
        assertEq(distributor.nextEpochId(), 1);
        assertEq(distributor.lastToBlock(), snapTo);
    }

    function test_OnlyPosterPosts() public {
        _deposit(GROSS);
        vm.prank(owner);
        vm.expectRevert(bytes("ONLY_POSTER"));
        distributor.postRoot(root, INPUTS_HASH, LEAVES_TOTAL, snapFrom, snapTo);
    }

    function test_PostValidations() public {
        _deposit(GROSS);
        vm.startPrank(poster);
        vm.expectRevert(bytes("ROOT_ZERO"));
        distributor.postRoot(bytes32(0), INPUTS_HASH, LEAVES_TOTAL, snapFrom, snapTo);
        vm.expectRevert(bytes("INPUTS_HASH_ZERO"));
        distributor.postRoot(root, bytes32(0), LEAVES_TOTAL, snapFrom, snapTo);
        vm.expectRevert(bytes("ALLOCATED_ZERO"));
        distributor.postRoot(root, INPUTS_HASH, 0, snapFrom, snapTo);
        vm.expectRevert(bytes("BLOCK_RANGE_INVALID"));
        distributor.postRoot(root, INPUTS_HASH, LEAVES_TOTAL, snapTo, snapFrom);
        vm.expectRevert(bytes("BLOCK_RANGE_UNFINALIZED"));
        distributor.postRoot(root, INPUTS_HASH, LEAVES_TOTAL, snapFrom, uint64(block.number));
        vm.stopPrank();
    }

    /// @notice The funded-envelope check: a root can never commit more than the
    ///         uncommitted balance, so a stolen poster key is bounded to roughly one
    ///         day's revenue (assuming regular sweeps).
    function test_RootCannotExceedUncommitted() public {
        _deposit(LEAVES_TOTAL - 1);
        vm.prank(poster);
        vm.expectRevert(bytes("EXCEEDS_UNCOMMITTED"));
        distributor.postRoot(root, INPUTS_HASH, LEAVES_TOTAL, snapFrom, snapTo);
    }

    /// @notice Prior roots' unclaimed balances are segregated: a new root can only
    ///         draw on NEW deposits, never on an earlier epoch's unclaimed reserve.
    function test_NewRootCannotTouchPriorUnclaimed() public {
        _deposit(LEAVES_TOTAL);
        _post(LEAVES_TOTAL); // epoch 0 commits the entire balance; nothing claimed yet
        assertEq(distributor.uncommitted(), 0);

        // No new deposits: any further root must fail, whatever epoch 0's claims state.
        vm.prank(poster);
        vm.expectRevert(bytes("EXCEEDS_UNCOMMITTED"));
        distributor.postRoot(root, INPUTS_HASH, 1, snapTo + 1, snapTo + 2);

        // New deposits open exactly that much new envelope — not a wei of epoch 0's.
        _deposit(7 ether);
        vm.prank(poster);
        vm.expectRevert(bytes("EXCEEDS_UNCOMMITTED"));
        distributor.postRoot(root, INPUTS_HASH, 7 ether + 1, snapTo + 1, snapTo + 2);
        vm.prank(poster);
        distributor.postRoot(root, INPUTS_HASH, 7 ether, snapTo + 1, snapTo + 2);
    }

    /// @notice Windows must strictly advance: no two roots can account the same
    ///         deposit positions.
    function test_OverlappingWindowReverts() public {
        _deposit(GROSS);
        _post(LEAVES_TOTAL);
        vm.startPrank(poster);
        vm.expectRevert(bytes("WINDOW_OVERLAP"));
        distributor.postRoot(root, INPUTS_HASH, 1 ether, snapTo, snapTo + 40);
        vm.expectRevert(bytes("WINDOW_OVERLAP"));
        distributor.postRoot(root, INPUTS_HASH, 1 ether, snapFrom, snapTo);
        // Strictly-later window is fine (gaps allowed: dust days can be skipped).
        distributor.postRoot(root, INPUTS_HASH, 1 ether, snapTo + 50, snapTo + 60);
        vm.stopPrank();
    }

    function test_SequentialEpochIds() public {
        _deposit(GROSS);
        assertEq(_post(LEAVES_TOTAL), 0);
        vm.prank(poster);
        assertEq(distributor.postRoot(root, INPUTS_HASH, 1 ether, snapTo + 1, snapTo + 2), 1);
        assertEq(distributor.nextEpochId(), 2);
    }

    // --- Claims -----------------------------------------------------------------

    function test_AttackerNotInRootCannotClaim() public {
        _deposit(GROSS);
        _post(LEAVES_TOTAL);
        address attacker = address(0xBAD);
        vm.expectRevert(bytes("BAD_PROOF"));
        distributor.claim(0, 0, attacker, A_AMT, _proofA());
        vm.expectRevert(bytes("BAD_PROOF"));
        distributor.claim(0, 4, attacker, 999 ether, _proofA());
    }

    function test_ParticipantCannotInflateAmount() public {
        _deposit(GROSS);
        _post(LEAVES_TOTAL);
        vm.expectRevert(bytes("BAD_PROOF"));
        distributor.claim(0, 0, alice, A_AMT + 1 ether, _proofA());
    }

    function test_DoubleClaimReverts() public {
        _deposit(GROSS);
        _post(LEAVES_TOTAL);
        distributor.claim(0, 0, alice, A_AMT, _proofA());
        vm.expectRevert(bytes("ALREADY_CLAIMED"));
        distributor.claim(0, 0, alice, A_AMT, _proofA());
    }

    function test_UnknownEpochClaimReverts() public {
        vm.expectRevert(bytes("EPOCH_UNKNOWN"));
        distributor.claim(42, 0, alice, A_AMT, _proofA());
    }

    /// @notice A faulty root's blast radius is its own allocation: claims against it
    ///         stop at the epoch cap and can never reach other epochs' reserves.
    function test_FaultyRootBlastRadiusBoundedToItsAllocation() public {
        _deposit(GROSS);
        vm.prank(poster);
        distributor.postRoot(root, INPUTS_HASH, 60 ether, snapFrom, snapTo); // < leaves sum

        distributor.claim(0, 0, alice, A_AMT, _proofA()); // 40 ok
        vm.expectRevert(bytes("EPOCH_OVERCLAIM")); // 40+30 > 60
        distributor.claim(0, 1, bob, B_AMT, _proofB());
        assertEq(distributor.uncommitted(), GROSS - 60 ether);
    }

    // --- Sweep -------------------------------------------------------------------

    function test_OnlyOwnerSweeps() public {
        _deposit(GROSS);
        vm.prank(poster);
        vm.expectRevert(bytes("ONLY_OWNER"));
        distributor.sweep();
    }

    /// @notice Sweeps pay ONLY the treasury fixed at deployment: no destination
    ///         parameter exists. Even the owner cannot pick another target.
    function test_SweepPaysOnlyImmutableTreasury() public {
        _deposit(GROSS);
        vm.expectEmit(true, false, false, true, address(distributor));
        emit RegentDailyDistributor.Swept(treasury, GROSS);
        vm.prank(owner);
        distributor.sweep();
        assertEq(regent.balanceOf(treasury), GROSS);
        assertEq(regent.balanceOf(owner), 0);
        assertEq(regent.balanceOf(address(distributor)), 0);
        assertEq(distributor.totalSwept(), GROSS);
    }

    /// @notice Sweeping never touches committed reserves: every posted root's unclaimed
    ///         balance remains fully payable after any number of sweeps.
    function test_SweepLeavesCommittedReservesIntact() public {
        _deposit(GROSS);
        _post(LEAVES_TOTAL);
        vm.prank(owner);
        assertEq(distributor.sweep(), GROSS - LEAVES_TOTAL);

        // All four leaves still claimable in full.
        distributor.claim(0, 0, alice, A_AMT, _proofA());
        distributor.claim(0, 1, bob, B_AMT, _proofB());
        distributor.claim(0, 2, carol, C_AMT, _proofC());
        bytes32[] memory proofD = new bytes32[](2);
        proofD[0] = leafC;
        proofD[1] = _hashPair(leafA, leafB);
        distributor.claim(0, 3, dave, D_AMT, proofD);
        assertEq(distributor.totalClaimed(), LEAVES_TOTAL);
        assertEq(regent.balanceOf(address(distributor)), 0);

        vm.prank(owner);
        vm.expectRevert(bytes("NOTHING_TO_SWEEP"));
        distributor.sweep();
    }
}
