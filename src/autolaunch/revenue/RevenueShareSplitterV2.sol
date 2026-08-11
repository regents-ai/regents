// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {Owned} from "src/shared/auth/Owned.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol";
import {
    IRevenueIngressFactoryMinimal
} from "src/autolaunch/revenue/interfaces/IRevenueIngressFactoryMinimal.sol";
import {IRevenueShareSplitter} from "src/autolaunch/revenue/interfaces/IRevenueShareSplitter.sol";
import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";
import {
    ISubjectPaymentReceiver
} from "src/autolaunch/revenue/interfaces/ISubjectPaymentReceiver.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {InputBounds} from "src/autolaunch/revenue/libraries/InputBounds.sol";

contract RevenueShareSplitterV2 is Owned, IRevenueShareSplitter {
    using SafeTransferLib for address;

    error SubjectBindingMismatch();
    error SubjectFeeVaultUnauthorized();
    error SubjectFeeVaultBindingMismatch();
    error SubjectLookupFailed();
    error RegentTransferInexact();

    enum RevenueSourceKind {
        DirectDeposit,
        AuthorizedIngress,
        SurplusRedeposit
    }

    struct RevenueAccounting {
        uint256 received;
        uint256 protocolAmount;
        uint256 stakerEligibleAmount;
        uint256 treasuryReservedAmount;
        uint256 stakerEntitlement;
        uint256 treasuryResidualAmount;
        uint256 creditedByAccumulator;
    }

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant ACC_PRECISION = 1e27;
    address public constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    uint16 public constant MIN_ELIGIBLE_REVENUE_SHARE_BPS = 1000;
    uint16 public constant MAX_ELIGIBLE_REVENUE_SHARE_STEP_BPS = 2000;
    uint16 public constant DEFAULT_ELIGIBLE_REVENUE_SHARE_BPS = 10_000;
    uint64 internal constant DEFAULT_TREASURY_ROTATION_DELAY = 3 days;
    uint64 internal constant ELIGIBLE_REVENUE_SHARE_DELAY = 30 days;

    address public immutable override stakeToken;
    address public immutable override usdc;
    address public immutable ingressFactory;
    address public immutable subjectRegistry;
    bytes32 public immutable override subjectId;
    uint256 public immutable revenueShareSupplyDenominator;
    IRegentStakingRevenueRouter public immutable stakingRevenueRouter;

    string public label;
    address public override treasuryRecipient;
    address public pendingTreasuryRecipient;
    uint64 public pendingTreasuryRecipientEta;
    uint64 public immutable treasuryRotationDelay;
    uint16 public eligibleRevenueShareBps;
    uint16 public pendingEligibleRevenueShareBps;
    uint64 public pendingEligibleRevenueShareEta;
    uint64 public eligibleRevenueShareCooldownEnd;

    bool public paused;
    uint256 public override totalStaked;
    uint256 public accRewardPerTokenUsdc;
    uint256 public treasuryResidualUsdc;
    uint256 public treasuryReservedUsdc;
    uint256 public protocolFeeUsdc;
    uint256 public totalProtocolUsdcDepositedToRegentStaking;
    uint256 public undistributedDustUsdc;
    /// @dev Reserves accumulator-rounding owed to stakers in aggregate so
    ///      `sweepTreasuryResidualUSDC` and `reassignUndistributedDustToTreasury`
    ///      cannot withdraw it. It is drawn down only when a claim's rounding
    ///      overage fires in `_recordUsdcClaim`; therefore wei-scale reserved dust
    ///      can remain locked if revenue stops before per-account claims round up
    ///      to a claimable unit, an accepted conservative tradeoff favoring stakers
    ///      over the treasury.
    uint256 public claimRoundingReserveUsdc;
    uint256 public totalUsdcReceived;
    uint256 public directDepositUsdc;
    uint256 public verifiedIngressUsdc;
    uint256 public surplusRedepositUsdc;
    uint256 public stakerEligibleInflowUsdc;
    uint256 public treasuryReservedInflowUsdc;
    uint256 public totalUsdcCreditedToStakers;
    uint256 public totalClaimedUsdc;
    uint256 public totalSurplusUsdcRedeposited;
    uint256 public totalSurplusUsdcSwept;
    uint256 public accRewardPerTokenRegent;
    uint256 private _totalRegentReceived;
    uint256 private _totalClaimedRegent;
    uint256 private _undistributedRegent;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public rewardDebtUsdc;
    mapping(address => uint256) public storedClaimableUsdc;
    mapping(address => uint256) private _rewardDebtRegent;
    mapping(address => uint256) private _storedClaimableRegent;

    uint256 private _reentrancyGuard = 1;

    event PausedSet(bool paused);
    event TreasuryRecipientRotationProposed(
        address indexed currentRecipient, address indexed pendingRecipient, uint64 eta
    );
    event TreasuryRecipientRotationCancelled(
        address indexed currentRecipient, address indexed cancelledRecipient
    );
    event TreasuryRecipientRotationExecuted(
        address indexed oldRecipient, address indexed newRecipient
    );
    event LabelSet(string label);
    event EligibleRevenueShareProposed(
        uint16 indexed currentBps, uint16 indexed pendingBps, uint64 eta
    );
    event EligibleRevenueShareCancelled(uint16 indexed cancelledBps, uint64 cooldownEnd);
    event EligibleRevenueShareActivated(
        uint16 indexed previousBps, uint16 indexed newBps, uint64 activatedAt, uint64 cooldownEnd
    );
    event StakeUpdated(address indexed account, uint256 newStakeBalance, uint256 totalStaked);
    event USDCRevenueDeposited(
        uint256 amountReceived,
        uint256 protocolAmount,
        uint16 eligibleShareBps,
        uint256 stakerEligibleAmount,
        uint256 treasuryReservedAmount,
        uint256 stakerEntitlement,
        uint256 treasuryResidualAmount,
        RevenueSourceKind indexed sourceKind,
        address indexed depositor,
        bytes32 sourceTag,
        bytes32 indexed sourceRef
    );
    event USDCRewardClaimed(address indexed account, uint256 amount, address recipient);
    event USDCSurplusRedeposited(
        uint256 amount,
        uint256 stakerRewardsCredited,
        uint256 treasuryResidualIncrease,
        address indexed caller,
        bytes32 sourceTag,
        bytes32 indexed sourceRef
    );
    event USDCSurplusSwept(uint256 amount, address indexed recipient);
    event USDCTreasuryResidualWithdrawn(uint256 amount, address indexed recipient);
    event USDCTreasuryReservedWithdrawn(uint256 amount, address indexed recipient);
    event USDCDustReassigned(uint256 amount, address indexed recipient);
    event AccountSynced(address indexed account);
    event RegentRewardsFunded(
        uint256 amountReceived, uint256 creditedToStakers, uint256 protectedDust
    );
    event RegentRewardClaimed(address indexed account, uint256 amount, address recipient);

    constructor(
        address stakeToken_,
        address usdc_,
        address ingressFactory_,
        address subjectRegistry_,
        bytes32 subjectId_,
        address treasuryRecipient_,
        address stakingRevenueRouter_,
        uint256 revenueShareSupplyDenominator_,
        string memory label_,
        address owner_
    ) Owned(owner_) {
        require(stakeToken_ != address(0), "STAKE_TOKEN_ZERO");
        require(usdc_ != address(0), "USDC_ZERO");
        require(stakeToken_ != usdc_, "STAKE_TOKEN_IS_USDC");
        require(ingressFactory_ != address(0), "INGRESS_FACTORY_ZERO");
        require(subjectRegistry_ != address(0), "SUBJECT_REGISTRY_ZERO");
        require(subjectId_ != bytes32(0), "SUBJECT_ZERO");
        require(treasuryRecipient_ != address(0), "TREASURY_ZERO");
        require(treasuryRecipient_ != address(this), "TREASURY_IS_SELF");
        require(stakingRevenueRouter_ != address(0), "STAKING_ROUTER_ZERO");
        require(owner_ != address(0), "OWNER_ZERO");
        require(revenueShareSupplyDenominator_ != 0, "SUPPLY_DENOMINATOR_ZERO");
        require(
            IRegentStakingRevenueRouter(stakingRevenueRouter_).usdc() == usdc_,
            "STAKING_ROUTER_USDC_MISMATCH"
        );
        InputBounds.requireStringMax(label_, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");

        stakeToken = stakeToken_;
        usdc = usdc_;
        ingressFactory = ingressFactory_;
        subjectRegistry = subjectRegistry_;
        subjectId = subjectId_;
        revenueShareSupplyDenominator = revenueShareSupplyDenominator_;
        treasuryRecipient = treasuryRecipient_;
        treasuryRotationDelay = DEFAULT_TREASURY_ROTATION_DELAY;
        stakingRevenueRouter = IRegentStakingRevenueRouter(stakingRevenueRouter_);
        label = label_;
        eligibleRevenueShareBps = DEFAULT_ELIGIBLE_REVENUE_SHARE_BPS;
    }

    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    modifier onlyActiveSubject() {
        require(_subjectIsActive(), "SUBJECT_INACTIVE");
        _;
    }

    modifier onlyTreasurySweepCaller() {
        require(msg.sender == owner || msg.sender == treasuryRecipient, "ONLY_TREASURY");
        _;
    }

    function protocolRecipient() external view override returns (address) {
        return address(stakingRevenueRouter);
    }

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedSet(paused_);
    }

    function proposeTreasuryRecipientRotation(address newRecipient)
        external
        onlyOwner
        onlyActiveSubject
    {
        require(newRecipient != address(0), "TREASURY_ZERO");
        require(newRecipient != address(this), "TREASURY_IS_SELF");
        require(newRecipient != treasuryRecipient, "TREASURY_UNCHANGED");

        uint64 eta = uint64(block.timestamp) + treasuryRotationDelay;
        pendingTreasuryRecipient = newRecipient;
        pendingTreasuryRecipientEta = eta;
        emit TreasuryRecipientRotationProposed(treasuryRecipient, newRecipient, eta);
    }

    function cancelTreasuryRecipientRotation() external onlyOwner {
        address cancelledRecipient = pendingTreasuryRecipient;
        require(cancelledRecipient != address(0), "PENDING_TREASURY_ZERO");
        pendingTreasuryRecipient = address(0);
        pendingTreasuryRecipientEta = 0;
        emit TreasuryRecipientRotationCancelled(treasuryRecipient, cancelledRecipient);
    }

    // Reviewed in slither.db.json: the timestamp enforces the configured rotation delay.
    // slither-disable-next-line timestamp
    function executeTreasuryRecipientRotation() external onlyActiveSubject {
        address newRecipient = pendingTreasuryRecipient;
        require(newRecipient != address(0), "PENDING_TREASURY_ZERO");
        require(block.timestamp >= pendingTreasuryRecipientEta, "ROTATION_NOT_READY");
        address oldRecipient = treasuryRecipient;
        treasuryRecipient = newRecipient;
        pendingTreasuryRecipient = address(0);
        pendingTreasuryRecipientEta = 0;
        emit TreasuryRecipientRotationExecuted(oldRecipient, newRecipient);
    }

    // Reviewed in slither.db.json: timestamps enforce pending-change and cooldown policy.
    // slither-disable-next-line timestamp
    function proposeEligibleRevenueShare(uint16 newBps) external onlyOwner {
        require(pendingEligibleRevenueShareEta == 0, "PENDING_SHARE_EXISTS");
        require(block.timestamp >= eligibleRevenueShareCooldownEnd, "SHARE_COOLDOWN_ACTIVE");
        require(newBps >= MIN_ELIGIBLE_REVENUE_SHARE_BPS, "ELIGIBLE_SHARE_TOO_LOW");
        require(newBps <= BPS_DENOMINATOR, "ELIGIBLE_SHARE_TOO_HIGH");
        require(
            _absDiff(eligibleRevenueShareBps, newBps) <= MAX_ELIGIBLE_REVENUE_SHARE_STEP_BPS,
            "ELIGIBLE_SHARE_STEP_TOO_LARGE"
        );

        uint64 eta = uint64(block.timestamp) + ELIGIBLE_REVENUE_SHARE_DELAY;
        pendingEligibleRevenueShareBps = newBps;
        pendingEligibleRevenueShareEta = eta;
        emit EligibleRevenueShareProposed(eligibleRevenueShareBps, newBps, eta);
    }

    function cancelEligibleRevenueShare() external onlyOwner {
        uint16 cancelledBps = pendingEligibleRevenueShareBps;
        require(cancelledBps != 0, "PENDING_SHARE_ZERO");
        pendingEligibleRevenueShareBps = 0;
        pendingEligibleRevenueShareEta = 0;
        eligibleRevenueShareCooldownEnd = uint64(block.timestamp) + ELIGIBLE_REVENUE_SHARE_DELAY;
        emit EligibleRevenueShareCancelled(cancelledBps, eligibleRevenueShareCooldownEnd);
    }

    // Reviewed in slither.db.json: the timestamp enforces the pending-share delay.
    // slither-disable-next-line timestamp
    function activateEligibleRevenueShare() external whenNotPaused onlyActiveSubject nonReentrant {
        uint16 newBps = pendingEligibleRevenueShareBps;
        uint64 eta = pendingEligibleRevenueShareEta;
        require(newBps != 0, "PENDING_SHARE_ZERO");
        require(block.timestamp >= eta, "SHARE_NOT_READY");
        uint16 previousBps = eligibleRevenueShareBps;
        eligibleRevenueShareBps = newBps;
        pendingEligibleRevenueShareBps = 0;
        pendingEligibleRevenueShareEta = 0;
        eligibleRevenueShareCooldownEnd = uint64(block.timestamp) + ELIGIBLE_REVENUE_SHARE_DELAY;
        emit EligibleRevenueShareActivated(
            previousBps, newBps, uint64(block.timestamp), eligibleRevenueShareCooldownEnd
        );
    }

    function setLabel(string calldata label_) external onlyOwner {
        InputBounds.requireStringMax(label_, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");
        label = label_;
        emit LabelSet(label_);
    }

    // Reviewed in slither.db.json: nonReentrant guards the exact-transfer token callback.
    // slither-disable-next-line reentrancy-no-eth
    function stake(uint256 amount, address receiver)
        external
        whenNotPaused
        onlyActiveSubject
        nonReentrant
    {
        require(amount != 0, "AMOUNT_ZERO");
        require(receiver != address(0), "RECEIVER_ZERO");
        require(receiver != address(this), "RECEIVER_IS_SELF");
        _sync(receiver);
        require(totalStaked + amount <= revenueShareSupplyDenominator, "STAKE_CAP_EXCEEDED");
        _pullExactStakeToken(msg.sender, amount);
        stakedBalance[receiver] += amount;
        totalStaked += amount;
        emit StakeUpdated(receiver, stakedBalance[receiver], totalStaked);
    }

    function unstake(uint256 amount, address recipient) external nonReentrant {
        require(amount != 0, "AMOUNT_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");
        require(recipient == msg.sender, "RECIPIENT_NOT_ACCOUNT");
        _sync(msg.sender);
        uint256 currentStake = stakedBalance[msg.sender];
        require(currentStake >= amount, "STAKE_BALANCE_LOW");
        unchecked {
            stakedBalance[msg.sender] = currentStake - amount;
            totalStaked -= amount;
        }
        emit StakeUpdated(msg.sender, stakedBalance[msg.sender], totalStaked);
        _pushExactStakeToken(recipient, amount);
    }

    function depositUSDC(uint256 amount, bytes32 sourceTag, bytes32 sourceRef)
        external
        override
        whenNotPaused
        onlyActiveSubject
        nonReentrant
        returns (uint256 received)
    {
        require(amount != 0, "AMOUNT_ZERO");
        uint256 beforeBalance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        received = afterBalance - beforeBalance;
        _recordRevenue(
            received,
            eligibleRevenueShareBps,
            RevenueSourceKind.DirectDeposit,
            msg.sender,
            sourceTag,
            sourceRef
        );
    }

    function recordIngressSweep(uint256 amount, bytes32 sourceRef)
        external
        override
        whenNotPaused
        onlyActiveSubject
        nonReentrant
        returns (uint256 recognized)
    {
        require(amount != 0, "AMOUNT_ZERO");
        require(_isKnownIngress(msg.sender), "ONLY_INGRESS_ACCOUNT");

        uint256 beforeBalance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        recognized = afterBalance - beforeBalance;

        _recordRevenue(
            recognized,
            eligibleRevenueShareBps,
            RevenueSourceKind.AuthorizedIngress,
            msg.sender,
            bytes32("ingress_sweep"),
            sourceRef
        );
    }

    function sync(address account) external whenNotPaused nonReentrant {
        require(account != address(0), "ACCOUNT_ZERO");
        _sync(account);
        emit AccountSynced(account);
    }

    function previewClaimableUSDC(address account) public view override returns (uint256) {
        uint256 claimable = storedClaimableUsdc[account];
        uint256 currentAcc = accRewardPerTokenUsdc;
        uint256 priorAcc = rewardDebtUsdc[account];
        if (currentAcc <= priorAcc) return claimable;
        uint256 stakeBal = stakedBalance[account];
        if (stakeBal == 0) return claimable;
        return claimable + FullMath.mulDiv(stakeBal, currentAcc - priorAcc, ACC_PRECISION);
    }

    function previewRevenueSplit(uint256 amount)
        external
        view
        override
        returns (IRevenueShareSplitter.RevenueSplitPreview memory preview)
    {
        preview = _previewRevenueSplit(amount, eligibleRevenueShareBps);
    }

    function previewTreasuryBalances()
        external
        view
        override
        returns (IRevenueShareSplitter.TreasuryBalancePreview memory preview)
    {
        preview = IRevenueShareSplitter.TreasuryBalancePreview({
            treasuryResidualUsdc: treasuryResidualUsdc,
            treasuryReservedUsdc: treasuryReservedUsdc,
            undistributedDustUsdc: undistributedDustUsdc,
            surplusUsdc: surplusUsdc()
        });
    }

    function previewStakeCapacity()
        external
        view
        override
        returns (IRevenueShareSplitter.StakeCapacityPreview memory preview)
    {
        preview = IRevenueShareSplitter.StakeCapacityPreview({
            totalStaked: totalStaked,
            stakeCapacity: revenueShareSupplyDenominator,
            remainingStakeCapacity: revenueShareSupplyDenominator - totalStaked
        });
    }

    function claimUSDC(address recipient) external nonReentrant returns (uint256 amount) {
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");
        require(recipient == msg.sender, "RECIPIENT_NOT_ACCOUNT");
        _sync(msg.sender);
        amount = storedClaimableUsdc[msg.sender];
        if (amount < 1) return 0;
        storedClaimableUsdc[msg.sender] = 0;
        _recordUsdcClaim(amount);
        emit USDCRewardClaimed(msg.sender, amount, recipient);
        usdc.safeTransfer(recipient, amount);
    }

    // The shared one-slot guard protects the exact-transfer callback and all following accounting.
    // slither-disable-next-line reentrancy-balance,reentrancy-benign
    function fundRegentRewards(uint256 amount) external nonReentrant returns (uint256 received) {
        _requireRegisteredFeeVault();
        require(amount != 0, "AMOUNT_ZERO");
        uint256 beforeBalance = IERC20SupplyMinimal(REGENT).balanceOf(address(this));
        REGENT.safeTransferFrom(msg.sender, address(this), amount);
        received = IERC20SupplyMinimal(REGENT).balanceOf(address(this)) - beforeBalance;
        require(received != 0, "NOTHING_RECEIVED");

        uint256 credited = 0;
        if (totalStaked == 0) {
            _undistributedRegent += received;
        } else {
            uint256 deltaAcc = FullMath.mulDiv(received, ACC_PRECISION, totalStaked);
            accRewardPerTokenRegent += deltaAcc;
            credited = FullMath.mulDiv(deltaAcc, totalStaked, ACC_PRECISION);
            _undistributedRegent += received - credited;
        }
        _totalRegentReceived += received;
        emit RegentRewardsFunded(received, credited, received - credited);
    }

    function previewClaimableRegent(address account) public view returns (uint256) {
        uint256 claimable = _storedClaimableRegent[account];
        uint256 currentAcc = accRewardPerTokenRegent;
        uint256 priorAcc = _rewardDebtRegent[account];
        if (currentAcc <= priorAcc) return claimable;
        return
            claimable
                + FullMath.mulDiv(stakedBalance[account], currentAcc - priorAcc, ACC_PRECISION);
    }

    // The shared one-slot guard protects the exact recipient-balance check across transfer.
    // slither-disable-next-line reentrancy-balance
    function claimRegent(address recipient) external nonReentrant returns (uint256 amount) {
        require(recipient == msg.sender, "RECIPIENT_NOT_ACCOUNT");
        _sync(msg.sender);
        amount = _storedClaimableRegent[msg.sender];
        if (amount == 0) return 0;
        _storedClaimableRegent[msg.sender] = 0;
        _totalClaimedRegent += amount;
        uint256 beforeBalance = IERC20SupplyMinimal(REGENT).balanceOf(recipient);
        REGENT.safeTransfer(recipient, amount);
        if (IERC20SupplyMinimal(REGENT).balanceOf(recipient) != beforeBalance + amount) {
            revert RegentTransferInexact();
        }
        emit RegentRewardClaimed(msg.sender, amount, recipient);
    }

    function reservedRegent() public view returns (uint256) {
        return _totalRegentReceived - _totalClaimedRegent;
    }

    function sweepTreasuryResidualUSDC(uint256 amount)
        external
        whenNotPaused
        onlyTreasurySweepCaller
        nonReentrant
    {
        require(amount != 0, "AMOUNT_ZERO");
        require(treasuryResidualUsdc >= amount, "TREASURY_BALANCE_LOW");
        treasuryResidualUsdc -= amount;
        emit USDCTreasuryResidualWithdrawn(amount, treasuryRecipient);
        usdc.safeTransfer(treasuryRecipient, amount);
    }

    function sweepTreasuryReservedUSDC(uint256 amount)
        external
        whenNotPaused
        onlyTreasurySweepCaller
        nonReentrant
    {
        require(amount != 0, "AMOUNT_ZERO");
        require(treasuryReservedUsdc >= amount, "TREASURY_RESERVED_BALANCE_LOW");
        treasuryReservedUsdc -= amount;
        emit USDCTreasuryReservedWithdrawn(amount, treasuryRecipient);
        usdc.safeTransfer(treasuryRecipient, amount);
    }

    function reassignUndistributedDustToTreasury(uint256 amount)
        external
        onlyOwner
        onlyActiveSubject
        nonReentrant
    {
        require(amount != 0, "AMOUNT_ZERO");
        require(undistributedDustUsdc >= amount, "DUST_BALANCE_LOW");
        require(
            undistributedDustUsdc - claimRoundingReserveUsdc >= amount, "DUST_RESERVED_FOR_STAKERS"
        );
        undistributedDustUsdc -= amount;
        treasuryResidualUsdc += amount;
        emit USDCDustReassigned(amount, treasuryRecipient);
    }

    function redepositSurplusUSDC(uint256 amount, bytes32 sourceTag, bytes32 sourceRef)
        external
        whenNotPaused
        onlyActiveSubject
        onlyOwner
        nonReentrant
    {
        require(amount != 0, "AMOUNT_ZERO");
        require(surplusUsdc() >= amount, "SURPLUS_BALANCE_LOW");
        uint256 beforeCredited = totalUsdcCreditedToStakers;
        uint256 beforeTreasury = treasuryResidualUsdc;
        totalSurplusUsdcRedeposited += amount;
        _recordRevenue(
            amount,
            eligibleRevenueShareBps,
            RevenueSourceKind.SurplusRedeposit,
            msg.sender,
            sourceTag,
            sourceRef
        );
        emit USDCSurplusRedeposited(
            amount,
            totalUsdcCreditedToStakers - beforeCredited,
            treasuryResidualUsdc - beforeTreasury,
            msg.sender,
            sourceTag,
            sourceRef
        );
    }

    function sweepSurplusUSDC(uint256 amount, address recipient)
        external
        whenNotPaused
        onlyActiveSubject
        onlyTreasurySweepCaller
        nonReentrant
    {
        require(amount != 0, "AMOUNT_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");
        require(recipient == treasuryRecipient, "RECIPIENT_NOT_TREASURY");
        require(surplusUsdc() >= amount, "SURPLUS_BALANCE_LOW");
        totalSurplusUsdcSwept += amount;
        emit USDCSurplusSwept(amount, recipient);
        usdc.safeTransfer(recipient, amount);
    }

    function reservedUsdc() public view returns (uint256) {
        uint256 stakerLiability = totalUsdcCreditedToStakers - totalClaimedUsdc;
        return treasuryReservedUsdc + treasuryResidualUsdc + undistributedDustUsdc + stakerLiability;
    }

    function surplusUsdc() public view returns (uint256) {
        uint256 balance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        uint256 reserved = reservedUsdc();
        if (balance <= reserved) return 0;
        unchecked {
            return balance - reserved;
        }
    }

    function _recordRevenue(
        uint256 received,
        uint16 shareBps,
        RevenueSourceKind sourceKind,
        address depositor,
        bytes32 sourceTag,
        bytes32 sourceRef
    ) internal {
        require(received > 0, "NOTHING_RECEIVED");

        RevenueAccounting memory accounting = _revenueAccounting(received, shareBps);
        _applyRevenueAccounting(accounting, sourceKind);
        _routeRevenue(accounting, sourceRef);
        _emitRevenueDeposited(accounting, shareBps, sourceKind, depositor, sourceTag, sourceRef);
    }

    function _revenueAccounting(uint256 received, uint16 shareBps)
        internal
        returns (RevenueAccounting memory accounting)
    {
        accounting.received = received;
        accounting.protocolAmount =
            FullMath.mulDiv(received, stakingRevenueRouter.protocolSkimBps(), BPS_DENOMINATOR);
        uint256 subjectLaneAmount = received - accounting.protocolAmount;
        accounting.treasuryReservedAmount =
            FullMath.mulDiv(subjectLaneAmount, BPS_DENOMINATOR - shareBps, BPS_DENOMINATOR);
        accounting.stakerEligibleAmount = subjectLaneAmount - accounting.treasuryReservedAmount;

        uint256 previousAcc = accRewardPerTokenUsdc;
        uint256 deltaAcc = 0;
        if (accounting.stakerEligibleAmount > 0) {
            deltaAcc = FullMath.mulDiv(
                accounting.stakerEligibleAmount, ACC_PRECISION, revenueShareSupplyDenominator
            );
        }
        uint256 nextAcc = previousAcc + deltaAcc;
        if (deltaAcc > 0) {
            accRewardPerTokenUsdc = nextAcc;
        }

        if (accounting.stakerEligibleAmount > 0 && totalStaked > 0) {
            accounting.stakerEntitlement = FullMath.mulDiv(
                accounting.stakerEligibleAmount, totalStaked, revenueShareSupplyDenominator
            );
        }
        uint256 stakerBacking = accounting.stakerEntitlement;
        if (deltaAcc > 0 && totalStaked > 0) {
            accounting.creditedByAccumulator = FullMath.mulDiv(deltaAcc, totalStaked, ACC_PRECISION);
            uint256 aggregateBefore = FullMath.mulDiv(previousAcc, totalStaked, ACC_PRECISION);
            uint256 aggregateAfter = FullMath.mulDiv(nextAcc, totalStaked, ACC_PRECISION);
            uint256 aggregateCreditedByAccumulator = aggregateAfter - aggregateBefore;
            if (aggregateCreditedByAccumulator > accounting.creditedByAccumulator) {
                claimRoundingReserveUsdc += aggregateCreditedByAccumulator
                    - accounting.creditedByAccumulator;
            }
            if (aggregateCreditedByAccumulator > stakerBacking) {
                stakerBacking = aggregateCreditedByAccumulator;
            }
        }
        accounting.treasuryResidualAmount = accounting.stakerEligibleAmount - stakerBacking;
        if (stakerBacking > accounting.creditedByAccumulator) {
            undistributedDustUsdc += stakerBacking - accounting.creditedByAccumulator;
        }
    }

    function _applyRevenueAccounting(
        RevenueAccounting memory accounting,
        RevenueSourceKind sourceKind
    ) internal {
        totalUsdcReceived += accounting.received;
        if (sourceKind == RevenueSourceKind.DirectDeposit) {
            directDepositUsdc += accounting.received;
        } else if (sourceKind == RevenueSourceKind.AuthorizedIngress) {
            verifiedIngressUsdc += accounting.received;
        } else if (sourceKind == RevenueSourceKind.SurplusRedeposit) {
            surplusRedepositUsdc += accounting.received;
        }
        protocolFeeUsdc += accounting.protocolAmount;
        stakerEligibleInflowUsdc += accounting.stakerEligibleAmount;
        treasuryReservedInflowUsdc += accounting.treasuryReservedAmount;
        treasuryResidualUsdc += accounting.treasuryResidualAmount;
        treasuryReservedUsdc += accounting.treasuryReservedAmount;
        totalUsdcCreditedToStakers += accounting.creditedByAccumulator;
    }

    // Reviewed in slither.db.json: exact settlement and callback ordering are guarded invariants.
    // slither-disable-next-line incorrect-equality,reentrancy-benign
    function _routeRevenue(RevenueAccounting memory accounting, bytes32 sourceRef) internal {
        if (accounting.protocolAmount > 0) {
            usdc.safeTransfer(address(stakingRevenueRouter), accounting.protocolAmount);
            uint256 depositedUsdc = stakingRevenueRouter.processProtocolFee(
                subjectId, accounting.protocolAmount, sourceRef
            );
            require(depositedUsdc == accounting.protocolAmount, "PROTOCOL_DEPOSIT_INEXACT");
            totalProtocolUsdcDepositedToRegentStaking += depositedUsdc;
        }
    }

    function _emitRevenueDeposited(
        RevenueAccounting memory accounting,
        uint16 shareBps,
        RevenueSourceKind sourceKind,
        address depositor,
        bytes32 sourceTag,
        bytes32 sourceRef
    ) internal {
        emit USDCRevenueDeposited(
            accounting.received,
            accounting.protocolAmount,
            shareBps,
            accounting.stakerEligibleAmount,
            accounting.treasuryReservedAmount,
            accounting.stakerEntitlement,
            accounting.treasuryResidualAmount,
            sourceKind,
            depositor,
            sourceTag,
            sourceRef
        );
    }

    /// @dev A claim can exceed outstanding credit by a few wei because per-account syncs floor
    ///      once over the accumulated delta while `creditedByAccumulator` floors per deposit.
    ///      That rounding is reserved in `undistributedDustUsdc`, never in sweepable residual.
    function _recordUsdcClaim(uint256 amount) internal {
        uint256 outstandingCredit = totalUsdcCreditedToStakers - totalClaimedUsdc;
        if (amount > outstandingCredit) {
            uint256 roundingOverage = amount - outstandingCredit;
            require(claimRoundingReserveUsdc >= roundingOverage, "STAKER_ROUNDING_UNDERFUNDED");
            claimRoundingReserveUsdc -= roundingOverage;
            undistributedDustUsdc -= roundingOverage;
            totalUsdcCreditedToStakers += roundingOverage;
        }
        totalClaimedUsdc += amount;
    }

    function _sync(address account) internal {
        uint256 currentAcc = accRewardPerTokenUsdc;
        uint256 priorAcc = rewardDebtUsdc[account];
        uint256 stakeBal = stakedBalance[account];
        if (currentAcc > priorAcc && stakeBal > 0) {
            storedClaimableUsdc[
                account
            ] += FullMath.mulDiv(stakeBal, currentAcc - priorAcc, ACC_PRECISION);
        }
        if (currentAcc > priorAcc) rewardDebtUsdc[account] = currentAcc;

        uint256 currentRegentAcc = accRewardPerTokenRegent;
        uint256 priorRegentAcc = _rewardDebtRegent[account];
        if (currentRegentAcc > priorRegentAcc && stakeBal > 0) {
            _storedClaimableRegent[
                account
            ] += FullMath.mulDiv(stakeBal, currentRegentAcc - priorRegentAcc, ACC_PRECISION);
        }
        if (currentRegentAcc > priorRegentAcc) _rewardDebtRegent[account] = currentRegentAcc;
    }

    function _requireRegisteredFeeVault() internal view {
        (
            address registeredStakeToken,
            address registeredSplitter,
            address registeredFeeRegistry,
            address registeredFeeVault,
            uint256 lifecycle
        ) = _subjectFeeBindings();
        if (
            lifecycle == uint256(ISubjectRegistry.Lifecycle.Retired)
                || registeredStakeToken != stakeToken || registeredSplitter != address(this)
        ) revert SubjectBindingMismatch();
        if (registeredFeeVault != msg.sender) revert SubjectFeeVaultUnauthorized();
        ILaunchFeeVaultBinding vault = ILaunchFeeVaultBinding(msg.sender);
        if (
            vault.registryContract() == registeredFeeRegistry
                && vault.canonicalLaunchToken() == stakeToken
                && vault.canonicalQuoteToken() == REGENT
        ) return;
        revert SubjectFeeVaultBindingMismatch();
    }

    /// @dev `SubjectConfig` contains a trailing dynamic string. Read only the five fixed ABI
    ///      words needed by this lane so the splitter deployer retains EIP-170 headroom.
    // This bounded read avoids material deployer bytecode growth while decoding only fixed words.
    // slither-disable-next-line assembly,low-level-calls
    function _subjectFeeBindings()
        private
        view
        returns (
            address registeredStakeToken,
            address registeredSplitter,
            address registeredFeeRegistry,
            address registeredFeeVault,
            uint256 lifecycle
        )
    {
        (bool success, bytes memory data) = subjectRegistry.staticcall(
            abi.encodeCall(ISubjectRegistry.getSubject, (subjectId))
        );
        if (!success || data.length < 480) revert SubjectLookupFailed();
        assembly ("memory-safe") {
            let tuple := add(add(data, 0x20), mload(add(data, 0x20)))
            registeredStakeToken := mload(tuple)
            registeredSplitter := mload(add(tuple, 0x20))
            registeredFeeRegistry := mload(add(tuple, 0xc0))
            registeredFeeVault := mload(add(tuple, 0xe0))
            lifecycle := mload(add(tuple, 0x180))
        }
    }

    function _subjectIsActive() internal view returns (bool) {
        return ISubjectRegistry(subjectRegistry).lifecycleOf(subjectId)
            == ISubjectRegistry.Lifecycle.Active;
    }

    function _isKnownIngress(address ingress) internal view returns (bool) {
        if (ingress.code.length == 0) return false;
        if (!IRevenueIngressFactoryMinimal(ingressFactory).isIngressAccount(ingress)) return false;
        try ISubjectPaymentReceiver(ingress).destination() returns (address destinationAddress) {
            if (destinationAddress != address(this)) return false;
        } catch {
            return false;
        }
        try ISubjectPaymentReceiver(ingress).subjectId() returns (bytes32 ingressSubjectId) {
            if (ingressSubjectId != subjectId) return false;
        } catch {
            return false;
        }
        try ISubjectPaymentReceiver(ingress).usdc() returns (address ingressUsdc) {
            if (ingressUsdc != usdc) return false;
        } catch {
            return false;
        }
        return true;
    }

    function _previewRevenueSplit(uint256 amount, uint16 shareBps)
        internal
        view
        returns (IRevenueShareSplitter.RevenueSplitPreview memory preview)
    {
        require(amount != 0, "AMOUNT_ZERO");
        uint256 protocolAmount =
            FullMath.mulDiv(amount, stakingRevenueRouter.protocolSkimBps(), BPS_DENOMINATOR);
        uint256 subjectLaneAmount = amount - protocolAmount;
        uint256 treasuryReservedAmount =
            FullMath.mulDiv(subjectLaneAmount, BPS_DENOMINATOR - shareBps, BPS_DENOMINATOR);
        uint256 stakerEligibleAmount = subjectLaneAmount - treasuryReservedAmount;
        uint256 stakerEntitlement = 0;
        uint256 creditedByAccumulator = 0;
        uint256 stakerBacking = 0;
        if (stakerEligibleAmount > 0 && totalStaked > 0) {
            stakerEntitlement =
                FullMath.mulDiv(stakerEligibleAmount, totalStaked, revenueShareSupplyDenominator);
            stakerBacking = stakerEntitlement;
            uint256 deltaAcc =
                FullMath.mulDiv(stakerEligibleAmount, ACC_PRECISION, revenueShareSupplyDenominator);
            creditedByAccumulator = FullMath.mulDiv(deltaAcc, totalStaked, ACC_PRECISION);
            uint256 aggregateBefore =
                FullMath.mulDiv(accRewardPerTokenUsdc, totalStaked, ACC_PRECISION);
            uint256 aggregateAfter =
                FullMath.mulDiv(accRewardPerTokenUsdc + deltaAcc, totalStaked, ACC_PRECISION);
            uint256 aggregateCreditedByAccumulator = aggregateAfter - aggregateBefore;
            if (aggregateCreditedByAccumulator > stakerBacking) {
                stakerBacking = aggregateCreditedByAccumulator;
            }
        }
        uint256 treasuryResidualAmount = stakerEligibleAmount - stakerBacking;
        uint256 dustAmount =
            stakerBacking > creditedByAccumulator ? stakerBacking - creditedByAccumulator : 0;

        preview = IRevenueShareSplitter.RevenueSplitPreview({
            amountReceived: amount,
            protocolAmount: protocolAmount,
            subjectLaneAmount: subjectLaneAmount,
            stakerEligibleAmount: stakerEligibleAmount,
            treasuryReservedAmount: treasuryReservedAmount,
            stakerEntitlement: stakerEntitlement,
            treasuryResidualAmount: treasuryResidualAmount,
            dustAmount: dustAmount
        });
    }

    function _absDiff(uint16 left, uint16 right) internal pure returns (uint16) {
        return left >= right ? left - right : right - left;
    }

    /// @dev Stake-token deposits require an exact balance delta. This deliberately makes
    ///      the splitter incompatible with fee-on-transfer / rebasing stake-token deposits.
    // Reviewed in slither.db.json: balance deltas intentionally reject fee-on-transfer tokens.
    // slither-disable-next-line incorrect-equality,reentrancy-balance
    function _pullExactStakeToken(address from, uint256 amount)
        internal
        returns (uint256 received)
    {
        uint256 beforeBalance = IERC20SupplyMinimal(stakeToken).balanceOf(address(this));
        stakeToken.safeTransferFrom(from, address(this), amount);
        uint256 afterBalance = IERC20SupplyMinimal(stakeToken).balanceOf(address(this));
        received = afterBalance - beforeBalance;
        require(received == amount, "STAKE_TOKEN_IN_EXACT");
    }

    // Reviewed in slither.db.json: balance deltas intentionally reject fee-on-transfer tokens.
    // slither-disable-next-line incorrect-equality,reentrancy-balance
    function _pushExactStakeToken(address recipient, uint256 amount) internal {
        uint256 beforeBalance = IERC20SupplyMinimal(stakeToken).balanceOf(recipient);
        stakeToken.safeTransfer(recipient, amount);
        uint256 afterBalance = IERC20SupplyMinimal(stakeToken).balanceOf(recipient);
        require(afterBalance - beforeBalance == amount, "STAKE_TOKEN_OUT_EXACT");
    }

    function _isProtectedToken(address token) internal view override returns (bool) {
        return token == usdc || token == stakeToken || token == REGENT;
    }
}

    interface ILaunchFeeVaultBinding {
        function registryContract() external view returns (address);
        function canonicalLaunchToken() external view returns (address);
        function canonicalQuoteToken() external view returns (address);
    }
