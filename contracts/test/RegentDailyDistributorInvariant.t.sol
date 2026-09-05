// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RegentDailyDistributor} from "src/autolaunch/revenue/RegentDailyDistributor.sol";

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

    constructor(address t) {
        stakeToken = t;
    }
}

/// @dev Drives the distributor through randomized deposit/post/claim/sweep sequences
///      while the invariant harness checks conservation and solvency after every call.
///      Uses one fixed 2-leaf tree so claims can submit real Merkle proofs.
contract Handler is Test {
    RegentDailyDistributor public distributor;
    MockERC20 public regent;

    address internal owner;
    address internal poster;
    address internal depositor = address(0xF00D);

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B0);
    uint256 internal constant A_AMT = 40 ether;
    uint256 internal constant B_AMT = 30 ether;

    bytes32 public root;
    bytes32 internal leafA;
    bytes32 internal leafB;
    bytes32 internal constant INPUTS_HASH = keccak256("inv-v2");

    constructor(RegentDailyDistributor d, MockERC20 r, address owner_, address poster_) {
        distributor = d;
        regent = r;
        owner = owner_;
        poster = poster_;

        leafA = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), alice, A_AMT))));
        leafB = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), bob, B_AMT))));
        root = leafA < leafB
            ? keccak256(abi.encode(leafA, leafB))
            : keccak256(abi.encode(leafB, leafA));

        regent.mint(depositor, 1e30);
        vm.prank(depositor);
        regent.approve(address(distributor), type(uint256).max);
    }

    function deposit(uint96 amount) external {
        amount = uint96(bound(amount, 1, 1000 ether));
        vm.prank(depositor);
        distributor.deposit(amount);
    }

    function post(uint96 alloc) external {
        uint256 free = distributor.uncommitted();
        if (free == 0) return;
        alloc = uint96(bound(alloc, 1, free));
        uint64 from = distributor.lastToBlock() + 1;
        // NOTE: never re-read block.number after vm.roll in the same frame — the
        // via-IR optimizer CSE-caches the NUMBER opcode, returning the stale value.
        uint256 bn = block.number;
        uint64 to;
        if (bn > from) {
            to = uint64(bn - 1);
        } else {
            vm.roll(uint256(from) + 10); // forward: bn <= from here
            to = from + 9;
        }
        vm.prank(poster);
        distributor.postRoot(root, INPUTS_HASH, alloc, from, to);
    }

    function claimA(uint256 id) external {
        _claim(id, 0, alice, A_AMT, leafB);
    }

    function claimB(uint256 id) external {
        _claim(id, 1, bob, B_AMT, leafA);
    }

    function _claim(uint256 id, uint256 index, address acct, uint256 amt, bytes32 sibling)
        internal
    {
        uint256 next = distributor.nextEpochId();
        if (next == 0) return;
        id = bound(id, 0, next - 1);
        (bytes32 r,, uint256 alloc, uint256 claimed,,) = distributor.epochs(id);
        if (r == bytes32(0)) return;
        if (distributor.isClaimed(id, index)) return;
        if (claimed + amt > alloc) return; // would hit EPOCH_OVERCLAIM (bad-root case)
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;
        distributor.claim(id, index, acct, amt, proof);
    }

    function sweep() external {
        if (distributor.uncommitted() == 0) return;
        vm.prank(owner);
        distributor.sweep();
    }

    function roll(uint16 blocks_) external {
        vm.roll(block.number + bound(blocks_, 1, 5000));
    }
}

contract RegentDailyDistributorInvariantTest is Test {
    RegentDailyDistributor internal distributor;
    MockERC20 internal regent;
    Handler internal handler;

    address internal owner = address(0xB0B);
    address internal poster = address(0x9057E5);
    address internal treasury = address(0x77EA5);

    function setUp() public {
        regent = new MockERC20();
        MockStakingReader staking = new MockStakingReader(address(regent));
        distributor =
            new RegentDailyDistributor(address(regent), address(staking), poster, owner, treasury);
        vm.roll(1000);
        handler = new Handler(distributor, regent, owner, poster);
        targetContract(address(handler));
    }

    /// @notice Conservation and solvency, checked after every randomized op:
    ///         claims + sweeps + residual balance == deposits exactly (nothing leaks,
    ///         nothing is minted); committed-but-unclaimed reserves are always
    ///         physically backed; roots never over-commit; and every swept wei landed
    ///         at the immutable treasury.
    function invariant_conservationAndSolvency() public view {
        uint256 deposited = distributor.totalDeposited();
        uint256 allocated = distributor.totalAllocated();
        uint256 claimed = distributor.totalClaimed();
        uint256 swept = distributor.totalSwept();
        uint256 balance = regent.balanceOf(address(distributor));

        // No root sequence can over-commit; claims never exceed commitments.
        assertLe(allocated + swept, deposited);
        assertLe(claimed, allocated);

        // Conservation: every deposited wei is claimed, swept, or still here.
        assertEq(balance, deposited - claimed - swept);

        // Solvency: outstanding committed claims are always physically backed.
        assertGe(balance, allocated - claimed);

        // Sweeps only ever reach the treasury.
        assertEq(regent.balanceOf(treasury), swept);
    }
}
