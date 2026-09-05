// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RegentDailyDistributor} from "src/autolaunch/revenue/RegentDailyDistributor.sol";

/// @dev Minimal ERC20 sufficient for SafeTransferLib (returns bool, has code).
contract SnapshotterFixtureERC20 {
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

contract SnapshotterFixtureStakingReader {
    address public stakeToken;

    constructor(address stakeToken_) {
        stakeToken = stakeToken_;
    }
}

/// @notice Cross-checks the off-chain snapshotter (snapshotter/) against the REAL
///         contract: the committed fixture test/fixtures/snapshotter-epoch.json is
///         produced by `npm run generate-fixture` in snapshotter/ from synthetic
///         StakeUpdated and Deposited logs (algoVersion 2 — per-deposit supply-fraction
///         entitlements). This suite replays the fixture's deposit table through
///         `deposit()`, posts the fixture's root via `postRoot` with the fixture's
///         `allocated` (the sum of leaves, strictly less than gross), claims EVERY leaf
///         immediately with the fixture's proofs, and sweeps the treasury remainder —
///         proving the tool's leaf encoding, tree hashing, allocation accounting, and
///         inputsHash encoding all match RegentDailyDistributor exactly.
contract RegentDailyDistributorSnapshotterFixtureTest is Test {
    struct FixtureLeaf {
        uint256 index;
        address account;
        uint256 amount;
        bytes32[] proof;
    }

    RegentDailyDistributor internal distributor;
    SnapshotterFixtureERC20 internal regent;

    address internal owner = address(0xB0B);
    address internal poster = address(0x9057E5);
    address internal treasury = address(0x77EA5);
    address internal depositor = address(0xF00D);

    // Fixture data.
    bytes32 internal root;
    bytes32 internal inputsHash;
    uint256 internal deposited;
    uint256 internal allocated;
    uint64 internal fromBlock;
    uint64 internal toBlock;
    address internal fixtureStaking;
    uint256[] internal depositAmounts;
    FixtureLeaf[] internal leaves;
    uint256 internal epochId;

    function setUp() public {
        string memory json = vm.readFile("test/fixtures/snapshotter-epoch.json");
        root = vm.parseJsonBytes32(json, ".root");
        inputsHash = vm.parseJsonBytes32(json, ".inputsHash");
        deposited = vm.parseJsonUint(json, ".deposited");
        allocated = vm.parseJsonUint(json, ".allocated");
        fromBlock = uint64(vm.parseJsonUint(json, ".fromBlock"));
        toBlock = uint64(vm.parseJsonUint(json, ".toBlock"));
        fixtureStaking = vm.parseJsonAddress(json, ".staking");

        for (uint256 i = 0;; i++) {
            string memory base = string.concat(".deposits[", vm.toString(i), "]");
            if (!vm.keyExistsJson(json, base)) break;
            depositAmounts.push(vm.parseJsonUint(json, string.concat(base, ".amount")));
        }
        require(depositAmounts.length >= 2, "fixture must have multiple deposits");

        for (uint256 i = 0;; i++) {
            string memory base = string.concat(".leaves[", vm.toString(i), "]");
            if (!vm.keyExistsJson(json, base)) break;
            leaves.push(
                FixtureLeaf({
                    index: vm.parseJsonUint(json, string.concat(base, ".index")),
                    account: vm.parseJsonAddress(json, string.concat(base, ".account")),
                    amount: vm.parseJsonUint(json, string.concat(base, ".amount")),
                    proof: vm.parseJsonBytes32Array(json, string.concat(base, ".proof"))
                })
            );
        }
        require(leaves.length >= 2, "fixture must have at least two leaves");

        regent = new SnapshotterFixtureERC20();
        SnapshotterFixtureStakingReader staking =
            new SnapshotterFixtureStakingReader(address(regent));
        distributor =
            new RegentDailyDistributor(address(regent), address(staking), poster, owner, treasury);

        // postRoot requires the window to be finished history.
        vm.roll(uint256(toBlock) + 1000);

        // Replay the fixture's deposit table: revenue deposits ARE the funding.
        regent.mint(depositor, deposited);
        vm.prank(depositor);
        regent.approve(address(distributor), type(uint256).max);
        uint256 grossReplayed = 0;
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            vm.prank(depositor);
            distributor.deposit(depositAmounts[i]);
            grossReplayed += depositAmounts[i];
        }
        assertEq(grossReplayed, deposited, "fixture deposit table must sum to `deposited`");

        vm.prank(poster);
        epochId = distributor.postRoot(root, inputsHash, allocated, fromBlock, toBlock);
        // No challenge window: claims are live immediately. No warp.
    }

    /// @notice Every fixture leaf claims successfully with its proof, the claimed total
    ///         equals `allocated` (the sum of leaves) EXACTLY, and the remainder — the
    ///         unstaked supply's share plus rounding dust, which by design never enters
    ///         a leaf — sweeps to the immutable treasury.
    function test_EveryFixtureLeafClaimsAndRemainderSweepsToTreasury() public {
        assertLt(allocated, deposited, "fixture must leave a treasury remainder");

        uint256 claimedSum = 0;
        for (uint256 i = 0; i < leaves.length; i++) {
            FixtureLeaf storage leaf = leaves[i];
            assertEq(leaf.index, i, "fixture indexes must be dense 0..n-1");
            uint256 before = regent.balanceOf(leaf.account);
            distributor.claim(epochId, leaf.index, leaf.account, leaf.amount, leaf.proof);
            assertEq(regent.balanceOf(leaf.account) - before, leaf.amount);
            claimedSum += leaf.amount;
        }
        assertEq(claimedSum, allocated, "sum of leaf amounts must equal allocated exactly");
        assertEq(distributor.totalClaimed(), allocated);

        // The treasury remainder is sweepable — and only to the treasury.
        uint256 remainder = deposited - allocated;
        assertEq(distributor.uncommitted(), remainder);
        vm.prank(owner);
        distributor.sweep();
        assertEq(regent.balanceOf(treasury), remainder);
        assertEq(regent.balanceOf(address(distributor)), 0);
    }

    /// @notice A tampered proof must not verify.
    function test_TamperedProofReverts() public {
        FixtureLeaf storage leaf = leaves[0];
        require(leaf.proof.length > 0, "fixture leaf 0 must have a non-empty proof");
        bytes32[] memory tampered = new bytes32[](leaf.proof.length);
        for (uint256 i = 0; i < leaf.proof.length; i++) {
            tampered[i] = leaf.proof[i];
        }
        tampered[0] = tampered[0] ^ bytes32(uint256(1));

        vm.expectRevert(bytes("BAD_PROOF"));
        distributor.claim(epochId, leaf.index, leaf.account, leaf.amount, tampered);
    }

    /// @notice A leaf's proof cannot be reused with an inflated amount.
    function test_InflatedAmountReverts() public {
        FixtureLeaf storage leaf = leaves[0];
        vm.expectRevert(bytes("BAD_PROOF"));
        distributor.claim(epochId, leaf.index, leaf.account, leaf.amount + 1, leaf.proof);
    }

    /// @notice The tool's inputsHash matches the spec §5 abi.encode layout exactly:
    ///         keccak256(abi.encode(staking, uint64 fromBlock, uint64 toBlock,
    ///         allocated, chainId=8453, algoVersion=2)).
    function test_InputsHashMatchesSpecEncoding() public view {
        bytes32 expected = keccak256(
            abi.encode(fixtureStaking, fromBlock, toBlock, allocated, uint256(8453), uint256(2))
        );
        assertEq(inputsHash, expected, "inputsHash must follow the spec section 5 preimage");
    }
}
