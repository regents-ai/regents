// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {MerkleProofLib} from "@solady/src/utils/MerkleProofLib.sol";

interface IERC20BalanceOf {
    function balanceOf(address) external view returns (uint256);
}

/// @dev Read-only view of the immutable staking contract, used only for the
///      constructor sanity-check that this distributor pays the same token stakers
///      stake. Deliberately NOT read during accrual or claim.
interface IRegentRevenueStakingReader {
    function stakeToken() external view returns (address);
}

/// @title RegentDailyDistributor
/// @notice Distributes protocol REGENT revenue to stakers of the immutable, un-hooked
///         `RegentRevenueStaking` contract on Base mainnet
///         (0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5) via daily Merkle roots, at each
///         staker's fixed supply fraction: for every deposit, a staker earns
///         deposit × stake_at_deposit_moment / 1e29 (100B total supply, the live USDC
///         lane's own `revenueShareSupplyDenominator`). The unstaked supply's share plus
///         rounding dust stays uncommitted and is swept to the protocol treasury — by
///         design, exactly like the USDC lane.
///
/// @dev PRE-DEPLOYMENT — NOT YET AUDITED BY HUMANS. Do not deploy without a human
///      audit of both this contract and the off-chain snapshotter that produces roots.
///
///      WHY A SNAPSHOT MODEL (not a live-read accumulator):
///      The staking contract has no stake/unstake hook and no unstake cooldown, and
///      exposes no monotonic stake-change nonce. Any companion that credits rewards off
///      a *live* balance read is drainable by flash-staking. Rewards must therefore be
///      a pure function of FIXED PAST chain positions: an off-chain snapshotter splits
///      each `Deposited` log by the `StakeUpdated`-reconstructed balances at that exact
///      (blockNumber, logIndex), sums per staker across the day, and posts one Merkle
///      root per day; stakers claim by proof. Deterministic algorithm + leaf format:
///      docs/regent-daily-distributor.md.
///
///      DISPOSABLE BY DESIGN — the security model in four lines:
///      1. Everything is immutable: no governance, no parameter setters, no pause, no
///         poster rotation, no rescue. There is no admin surface to compromise.
///      2. A root's `allocated` must fit inside the UNCOMMITTED balance
///         (deposits − allocated − swept), and prior roots' unclaimed balances are
///         segregated forever — no new root, sweep, or any other path can touch them.
///      3. The owner sweeps the uncommitted remainder to the immutable treasury after
///         each day's root. Regular sweeps keep the uncommitted balance — the only
///         thing a stolen poster key can misallocate — at roughly one day's revenue.
///      4. Recovery from any compromise or bug: stop depositing revenue and deploy a
///         fresh instance. Nothing here custodies stake or more than days of revenue.
contract RegentDailyDistributor {
    using SafeTransferLib for address;

    /// @notice REGENT token distributed to stakers (== staking.stakeToken()).
    address public immutable regent;
    /// @notice The immutable USDC staking contract whose positions define shares.
    address public immutable staking;
    /// @notice Automated key authorized to post daily roots. Immutable: a compromised
    ///         poster is bounded by the uncommitted envelope and retired by redeploying.
    address public immutable poster;
    /// @notice Treasury multisig; its only right is `sweep()`. Owner-gated (not
    ///         permissionless) so nobody can race the day's `postRoot` and divert the
    ///         stakers' not-yet-posted share to the treasury.
    address public immutable owner;
    /// @notice Protocol treasury — the ONLY destination `sweep` can pay, fixed at
    ///         deployment. The unstaked supply's share of each deposit plus rounding
    ///         dust belongs to the treasury by design.
    address public immutable treasury;

    /// @notice Cumulative REGENT received via `deposit`. Deposits are both the funding
    ///         and the accounting moments: each `Deposited` log is a pot the snapshotter
    ///         splits at that exact chain position.
    uint256 public totalDeposited;
    /// @notice Cumulative REGENT committed to posted roots. Once committed, an epoch's
    ///         unclaimed balance is reserved for its claimants forever (no expiry).
    uint256 public totalAllocated;
    /// @notice Cumulative REGENT paid out via `claim`.
    uint256 public totalClaimed;
    /// @notice Cumulative REGENT swept to the treasury.
    uint256 public totalSwept;

    /// @notice Last block covered by a posted root. Windows must strictly advance, so
    ///         no two roots can account the same deposit.
    uint64 public lastToBlock;
    /// @notice Sequential id assigned to the next posted root.
    uint256 public nextEpochId;

    struct Epoch {
        bytes32 root;
        bytes32 inputsHash;
        uint256 allocated;
        uint256 claimed;
        uint64 fromBlock;
        uint64 toBlock;
    }

    mapping(uint256 => Epoch) public epochs;
    /// @dev epochId => wordIndex => bitmap of claimed leaf indices.
    mapping(uint256 => mapping(uint256 => uint256)) private _claimedBitmap;

    uint256 private _reentrancyGuard = 1;

    event Deposited(address indexed from, uint256 amount);
    event RootPosted(
        uint256 indexed epochId,
        bytes32 root,
        bytes32 inputsHash,
        uint256 allocated,
        uint64 fromBlock,
        uint64 toBlock,
        address staking
    );
    event Claimed(
        uint256 indexed epochId, uint256 indexed index, address indexed account, uint256 amount
    );
    event Swept(address indexed treasury, uint256 amount);

    modifier onlyPoster() {
        require(msg.sender == poster, "ONLY_POSTER");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    constructor(
        address regent_,
        address staking_,
        address poster_,
        address owner_,
        address treasury_
    ) {
        require(regent_ != address(0), "REGENT_ZERO");
        require(staking_ != address(0), "STAKING_ZERO");
        require(poster_ != address(0), "POSTER_ZERO");
        require(owner_ != address(0), "OWNER_ZERO");
        require(treasury_ != address(0), "TREASURY_ZERO");
        require(treasury_ != address(this), "TREASURY_IS_SELF");
        require(
            IRegentRevenueStakingReader(staking_).stakeToken() == regent_, "STAKE_TOKEN_MISMATCH"
        );

        regent = regent_;
        staking = staking_;
        poster = poster_;
        owner = owner_;
        treasury = treasury_;
    }

    // -------------------------------------------------------------------------
    // Deposits
    // -------------------------------------------------------------------------

    /// @notice Deposit protocol REGENT revenue. Permissionless, mirroring the live
    ///         lane's `depositUSDC`. The `Deposited` log's (blockNumber, logIndex) is
    ///         the accounting moment: the snapshotter splits this amount by the stake
    ///         balances at exactly that position. REGENT must enter via `deposit`,
    ///         never by direct transfer — direct transfers emit no accounting event,
    ///         are credited to nobody, and are unrecoverable.
    function deposit(uint256 amount) external nonReentrant returns (uint256 received) {
        require(amount != 0, "AMOUNT_ZERO");
        uint256 before = IERC20BalanceOf(regent).balanceOf(address(this));
        regent.safeTransferFrom(msg.sender, address(this), amount);
        received = IERC20BalanceOf(regent).balanceOf(address(this)) - before;
        require(received == amount, "FEE_ON_TRANSFER");
        totalDeposited += received;
        emit Deposited(msg.sender, received);
    }

    // -------------------------------------------------------------------------
    // Daily roots
    // -------------------------------------------------------------------------

    /// @notice REGENT deposited but not yet committed to a root nor swept. This is the
    ///         entire blast radius of a hostile root, and what `sweep` pays out.
    function uncommitted() public view returns (uint256) {
        return totalDeposited - totalAllocated - totalSwept;
    }

    /// @notice Post the day's allocation root (poster only). `allocated` is the sum of
    ///         the day's leaves — the stakers' collective share of the window's
    ///         deposits, always strictly accounted within the uncommitted envelope so
    ///         prior roots' unclaimed balances can never be re-committed.
    /// @param root        Merkle root over (index, account, amount) leaves.
    /// @param inputsHash  Commitment to the exact off-chain inputs (see spec doc §5).
    /// @param allocated   REGENT committed to this root (must equal Σ leaf amounts).
    /// @param fromBlock   First block of the window (inclusive); must be past
    ///                    `lastToBlock` so windows never overlap or double-count.
    /// @param toBlock     Last block of the window (inclusive); must be history.
    function postRoot(
        bytes32 root,
        bytes32 inputsHash,
        uint256 allocated,
        uint64 fromBlock,
        uint64 toBlock
    ) external onlyPoster returns (uint256 epochId) {
        require(root != bytes32(0), "ROOT_ZERO");
        require(inputsHash != bytes32(0), "INPUTS_HASH_ZERO");
        require(allocated != 0, "ALLOCATED_ZERO");
        require(fromBlock <= toBlock, "BLOCK_RANGE_INVALID");
        require(toBlock < block.number, "BLOCK_RANGE_UNFINALIZED");
        require(fromBlock > lastToBlock, "WINDOW_OVERLAP");
        require(allocated <= uncommitted(), "EXCEEDS_UNCOMMITTED");

        epochId = nextEpochId++;
        epochs[epochId] = Epoch({
            root: root,
            inputsHash: inputsHash,
            allocated: allocated,
            claimed: 0,
            fromBlock: fromBlock,
            toBlock: toBlock
        });
        lastToBlock = toBlock;
        totalAllocated += allocated;

        emit RootPosted(epochId, root, inputsHash, allocated, fromBlock, toBlock, staking);
    }

    // -------------------------------------------------------------------------
    // Claims
    // -------------------------------------------------------------------------

    function isClaimed(uint256 epochId, uint256 index) public view returns (bool) {
        uint256 word = _claimedBitmap[epochId][index >> 8];
        return (word >> (index & 0xff)) & 1 == 1;
    }

    /// @notice Claim REGENT for `account` in `epochId` against the posted root.
    ///         Claimable immediately after posting, forever — no window, no expiry.
    /// @dev Leaf = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount)))),
    ///      the OpenZeppelin double-hash standard (second-preimage safe). CEI: all state
    ///      is written before the single external transfer, and the immutable staking
    ///      contract's live state is never read here, so there is no read-only or
    ///      cross-contract reentrancy surface.
    function claim(
        uint256 epochId,
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant {
        Epoch storage e = epochs[epochId];
        require(e.root != bytes32(0), "EPOCH_UNKNOWN");
        require(amount != 0, "AMOUNT_ZERO");
        require(!isClaimed(epochId, index), "ALREADY_CLAIMED");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
        require(MerkleProofLib.verifyCalldata(proof, e.root, leaf), "BAD_PROOF");

        // Per-epoch cap bounds the blast radius of a faulty root to its own allocation.
        // Cannot touch other epochs' unclaimed balances or the uncommitted pool.
        require(e.claimed + amount <= e.allocated, "EPOCH_OVERCLAIM");

        _claimedBitmap[epochId][index >> 8] |= (1 << (index & 0xff));
        e.claimed += amount;
        totalClaimed += amount;

        emit Claimed(epochId, index, account, amount);
        regent.safeTransfer(account, amount);
    }

    // -------------------------------------------------------------------------
    // Treasury sweep
    // -------------------------------------------------------------------------

    /// @notice Sweep the entire uncommitted balance to the immutable treasury. Owner
    ///         only, destination fixed at deployment — even a compromised owner key can
    ///         only move inventory to the treasury. SWEEP CADENCE IS THE SECURITY
    ///         MODEL: sweeping right after each day's root keeps the uncommitted
    ///         balance (a hostile root's maximum take) at about one day's revenue.
    function sweep() external onlyOwner nonReentrant returns (uint256 amount) {
        amount = uncommitted();
        require(amount != 0, "NOTHING_TO_SWEEP");
        totalSwept += amount;
        emit Swept(treasury, amount);
        regent.safeTransfer(treasury, amount);
    }
}
