// SPDX-License-Identifier: MIT

/**
 * NOTICE: This file is the source of the RegentRevenueStaking contract deployed
 * on Base mainnet at 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5, which holds
 * real funds. It is kept faithful to that deployment; the only departures from
 * the verified source are the import paths, which follow this repository's
 * layout.
 *
 * Deployed runtime size: 11,757 bytes; deployed runtime SHA-256:
 * 9e7d05378e4aeddb4db00bdaa88e6a466c3061d6514a760bbe93fa5d665129bb.
 * Verified source: Blockscout at the address above, compiled with
 * solc 0.8.30+commit.73712a01, optimizer enabled at 200 runs, EVM version
 * prague.
 *
 * KNOWN LIMITATION, present in the deployed contract: there is no reserve for
 * the accumulator's rounding carry. A per-account `_sync` floors once over the
 * sum of several deposits' accumulator deltas, so a staker's merged claimable
 * can exceed the per-deposit `creditedToStakers` floors by a wei-scale overage.
 * `_recordUsdcClaim` covers that overage out of `treasuryResidualUsdc`, and
 * `withdrawTreasuryResidual` may take the whole residual, the dust backing it
 * included. An affected claim then reverts on arithmetic underflow.
 *
 * Further deposits do not clear it. `treasuryResidualUsdc` is only ever
 * increased by `_recordRevenue`, and every path into it raises the aggregate
 * overage by the same wei, so the residual never catches up. Measured across
 * eleven deposits from 1 wei to 999e18 in the fully-staked regime, the
 * shortfall stayed at exactly 1 wei throughout.
 *
 * That is a bounded claim-availability risk: NOT reentrancy, NOT fund loss, and
 * staked principal and the rest of a claim are unaffected. It is proven by
 * test/RegentStakingClaimRoundingDrain.t.sol.
 *
 * A newer revision reserving that carry was previously kept in this file. It
 * was removed so this source states only what is deployed. Any fix ships as a
 * redeploy, which is a founder decision this file does not pre-empt.
 */
pragma solidity ^0.8.26;

import {Owned} from "src/shared/auth/Owned.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {IERC20SupplyMinimal} from "src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol";

contract RegentRevenueStaking is Owned {
    using SafeTransferLib for address;

    enum RevenueSourceKind {
        DirectDeposit,
        SurplusRedeposit
    }

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant ACC_PRECISION = 1e27;
    uint256 public constant MAX_EMISSION_APR_BPS = 2000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    address public immutable stakeToken;
    address public immutable usdc;
    uint256 public immutable revenueShareSupplyDenominator;

    address public treasuryRecipient;
    bool public paused;
    uint256 public totalStaked;
    uint256 public accRewardPerTokenUsdc;
    uint256 public accRewardPerTokenRegent;
    uint16 public emissionAprBps;
    uint256 public lastEmissionUpdate;
    uint256 public treasuryResidualUsdc;
    uint256 public totalUsdcReceived;
    uint256 public directDepositUsdc;
    uint256 public surplusRedepositUsdc;
    uint256 public totalUsdcCreditedToStakers;
    uint256 public totalClaimedUsdc;
    uint256 public totalSurplusUsdcRedeposited;
    uint256 public totalSurplusUsdcSwept;
    uint256 public unclaimedRegentLiability;
    uint256 public totalEmittedRegent;
    uint256 public totalFundedRegent;
    uint256 public totalClaimedRegent;
    uint256 public totalRewardTokenPoolSwept;
    uint256 public totalRewardTokenPoolRefunded;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public rewardDebtUsdc;
    mapping(address => uint256) public storedClaimableUsdc;
    mapping(address => uint256) public rewardDebtRegent;
    mapping(address => uint256) public storedClaimableRegent;

    uint256 private _reentrancyGuard = 1;

    event PausedSet(bool paused);
    event TreasuryRecipientSet(address indexed treasuryRecipient);
    event EmissionAprBpsSet(uint16 previousBps, uint16 newBps);
    event StakeUpdated(address indexed account, uint256 newStakeBalance, uint256 totalStaked);
    event USDCRevenueDeposited(
        uint256 amountReceived,
        uint256 stakerRewardsCredited,
        uint256 treasuryResidualIncrease,
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
    event RewardTokenFunded(address indexed caller, uint256 amountReceived);
    event RewardTokenClaimed(address indexed account, uint256 amount, address recipient);
    event RewardTokenCompounded(
        address indexed account, uint256 amount, uint256 newStakeBalance, uint256 totalStaked
    );
    event RewardTokenPoolSwept(uint256 amount, address indexed recipient);
    event RewardTokenPoolRefunded(uint256 amount, address indexed recipient);
    event TreasuryResidualWithdrawn(uint256 amount, address indexed recipient);
    event AccountSynced(address indexed account);

    constructor(
        address stakeToken_,
        address usdc_,
        address treasuryRecipient_,
        uint256 revenueShareSupplyDenominator_,
        address owner_
    ) Owned(owner_) {
        require(stakeToken_ != address(0), "STAKE_TOKEN_ZERO");
        require(usdc_ != address(0), "USDC_ZERO");
        require(stakeToken_ != usdc_, "STAKE_TOKEN_IS_USDC");
        require(treasuryRecipient_ != address(0), "TREASURY_ZERO");
        require(owner_ != address(0), "OWNER_ZERO");
        require(revenueShareSupplyDenominator_ != 0, "SUPPLY_DENOMINATOR_ZERO");

        stakeToken = stakeToken_;
        usdc = usdc_;
        treasuryRecipient = treasuryRecipient_;
        revenueShareSupplyDenominator = revenueShareSupplyDenominator_;
        lastEmissionUpdate = block.timestamp;
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

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedSet(paused_);
    }

    function setTreasuryRecipient(address treasuryRecipient_) external onlyOwner {
        require(treasuryRecipient_ != address(0), "TREASURY_ZERO");
        require(treasuryRecipient_ != address(this), "TREASURY_IS_SELF");
        treasuryRecipient = treasuryRecipient_;
        emit TreasuryRecipientSet(treasuryRecipient_);
    }

    function setEmissionAprBps(uint16 newBps) external onlyOwner {
        require(newBps <= MAX_EMISSION_APR_BPS, "EMISSION_APR_BPS_INVALID");
        _settleRegentEmissions();
        uint16 previousBps = emissionAprBps;
        emissionAprBps = newBps;
        emit EmissionAprBpsSet(previousBps, newBps);
    }

    // slither-disable-next-line reentrancy-no-eth
    function stake(uint256 amount, address receiver) external whenNotPaused nonReentrant {
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

    function sync(address account) external nonReentrant {
        require(account != address(0), "ACCOUNT_ZERO");
        _sync(account);
        emit AccountSynced(account);
    }

    function previewClaimableUSDC(address account) public view returns (uint256) {
        uint256 claimable = storedClaimableUsdc[account];
        uint256 currentAcc = accRewardPerTokenUsdc;
        uint256 priorAcc = rewardDebtUsdc[account];
        if (currentAcc <= priorAcc) {
            return claimable;
        }

        uint256 stakeBal = stakedBalance[account];
        if (stakeBal == 0) {
            return claimable;
        }

        return claimable + FullMath.mulDiv(stakeBal, currentAcc - priorAcc, ACC_PRECISION);
    }

    function previewClaimableRegent(address account) public view returns (uint256) {
        uint256 claimable = storedClaimableRegent[account];
        uint256 currentAcc = _previewAccRewardPerTokenRegent();
        uint256 priorAcc = rewardDebtRegent[account];
        if (currentAcc <= priorAcc) {
            return claimable;
        }

        uint256 stakeBal = stakedBalance[account];
        if (stakeBal == 0) {
            return claimable;
        }

        return claimable + FullMath.mulDiv(stakeBal, currentAcc - priorAcc, ACC_PRECISION);
    }

    function previewFundedClaimableRegent(address account) public view returns (uint256) {
        uint256 claimable = previewClaimableRegent(account);
        uint256 available = availableRegentRewardInventory();
        return claimable <= available ? claimable : available;
    }

    function claimUSDC(address recipient) external nonReentrant returns (uint256 amount) {
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");

        _sync(msg.sender);
        amount = storedClaimableUsdc[msg.sender];
        if (amount < 1) {
            return 0;
        }

        storedClaimableUsdc[msg.sender] = 0;
        _recordUsdcClaim(amount);
        emit USDCRewardClaimed(msg.sender, amount, recipient);
        usdc.safeTransfer(recipient, amount);
    }

    function claimRegent(address recipient) external nonReentrant returns (uint256 amount) {
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");

        _sync(msg.sender);
        amount = storedClaimableRegent[msg.sender];
        if (amount < 1) {
            return 0;
        }
        require(availableRegentRewardInventory() >= amount, "REWARD_INVENTORY_LOW");

        storedClaimableRegent[msg.sender] = 0;
        unclaimedRegentLiability -= amount;
        totalClaimedRegent += amount;

        emit RewardTokenClaimed(msg.sender, amount, recipient);
        _pushExactStakeToken(recipient, amount);
    }

    function claimAndRestakeRegent() external whenNotPaused nonReentrant returns (uint256 amount) {
        _sync(msg.sender);
        amount = storedClaimableRegent[msg.sender];
        if (amount < 1) {
            return 0;
        }
        require(availableRegentRewardInventory() >= amount, "REWARD_INVENTORY_LOW");
        require(totalStaked + amount <= revenueShareSupplyDenominator, "STAKE_CAP_EXCEEDED");

        storedClaimableRegent[msg.sender] = 0;
        unclaimedRegentLiability -= amount;
        totalClaimedRegent += amount;
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;

        emit RewardTokenCompounded(msg.sender, amount, stakedBalance[msg.sender], totalStaked);
        emit StakeUpdated(msg.sender, stakedBalance[msg.sender], totalStaked);
    }

    function depositUSDC(uint256 amount, bytes32 sourceTag, bytes32 sourceRef)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 received)
    {
        require(amount != 0, "AMOUNT_ZERO");
        _settleRegentEmissions();

        uint256 beforeBalance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        // slither-disable-next-line reentrancy-benign
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        received = afterBalance - beforeBalance;

        _recordRevenue(received, RevenueSourceKind.DirectDeposit, msg.sender, sourceTag, sourceRef);
    }

    function fundRegentRewards(uint256 amount)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 received)
    {
        require(amount != 0, "AMOUNT_ZERO");
        _settleRegentEmissions();

        // slither-disable-next-line reentrancy-benign
        received = _pullExactStakeToken(msg.sender, amount);

        totalFundedRegent += received;
        emit RewardTokenFunded(msg.sender, received);
    }

    function withdrawTreasuryResidual(uint256 amount, address recipient)
        external
        whenNotPaused
        nonReentrant
    {
        require(msg.sender == treasuryRecipient || msg.sender == owner, "ONLY_TREASURY");
        require(amount != 0, "AMOUNT_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");
        require(treasuryResidualUsdc >= amount, "TREASURY_BALANCE_LOW");

        treasuryResidualUsdc -= amount;
        emit TreasuryResidualWithdrawn(amount, recipient);
        usdc.safeTransfer(recipient, amount);
    }

    function sweepRegentRewardPool(uint256 amount) external whenNotPaused nonReentrant {
        require(msg.sender == treasuryRecipient || msg.sender == owner, "ONLY_TREASURY");

        _settleRegentEmissions();
        totalRewardTokenPoolSwept += amount;
        _withdrawRegentRewardPool(amount, treasuryRecipient);
        emit RewardTokenPoolSwept(amount, treasuryRecipient);
    }

    function refundRegentRewardPool(uint256 amount, address recipient)
        external
        whenNotPaused
        onlyOwner
        nonReentrant
    {
        _settleRegentEmissions();
        totalRewardTokenPoolRefunded += amount;
        _withdrawRegentRewardPool(amount, recipient);
        emit RewardTokenPoolRefunded(amount, recipient);
    }

    function redepositSurplusUSDC(uint256 amount, bytes32 sourceTag, bytes32 sourceRef)
        external
        whenNotPaused
        onlyOwner
        nonReentrant
    {
        require(amount != 0, "AMOUNT_ZERO");
        require(surplusUsdc() >= amount, "SURPLUS_BALANCE_LOW");
        _settleRegentEmissions();

        uint256 beforeCredited = totalUsdcCreditedToStakers;
        uint256 beforeTreasury = treasuryResidualUsdc;
        totalSurplusUsdcRedeposited += amount;
        _recordRevenue(amount, RevenueSourceKind.SurplusRedeposit, msg.sender, sourceTag, sourceRef);

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
        nonReentrant
    {
        require(msg.sender == treasuryRecipient || msg.sender == owner, "ONLY_TREASURY");
        require(amount != 0, "AMOUNT_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");
        require(surplusUsdc() >= amount, "SURPLUS_BALANCE_LOW");

        totalSurplusUsdcSwept += amount;
        emit USDCSurplusSwept(amount, recipient);
        usdc.safeTransfer(recipient, amount);
    }

    function reservedUsdc() public view returns (uint256) {
        uint256 stakerLiability = totalUsdcCreditedToStakers - totalClaimedUsdc;
        return treasuryResidualUsdc + stakerLiability;
    }

    function surplusUsdc() public view returns (uint256) {
        uint256 balance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        uint256 reserved = reservedUsdc();
        if (balance <= reserved) {
            return 0;
        }
        unchecked {
            return balance - reserved;
        }
    }

    function availableRegentRewardInventory() public view returns (uint256 available) {
        return regentRewardPool();
    }

    function regentRewardPool() public view returns (uint256 available) {
        uint256 balance = IERC20SupplyMinimal(stakeToken).balanceOf(address(this));
        if (balance <= totalStaked) {
            return 0;
        }
        unchecked {
            available = balance - totalStaked;
        }
    }

    function reservedRegentRewards() public view returns (uint256) {
        uint256 emitted = _previewTotalEmittedRegent();
        if (emitted <= totalClaimedRegent) {
            return 0;
        }
        unchecked {
            return emitted - totalClaimedRegent;
        }
    }

    function sweepableRegentRewardPool() public view returns (uint256) {
        uint256 pool = regentRewardPool();
        uint256 reserved = reservedRegentRewards();
        if (pool <= reserved) {
            return 0;
        }
        unchecked {
            return pool - reserved;
        }
    }

    function regentRewardShortfall() external view returns (uint256) {
        uint256 liability = reservedRegentRewards();
        uint256 available = regentRewardPool();
        if (liability <= available) {
            return 0;
        }
        unchecked {
            return liability - available;
        }
    }

    function _isProtectedToken(address token) internal view override returns (bool) {
        return token == usdc || token == stakeToken;
    }

    function _sync(address account) internal {
        _settleRegentEmissions();

        uint256 currentAccRegent = accRewardPerTokenRegent;
        uint256 priorAccRegent = rewardDebtRegent[account];
        if (currentAccRegent > priorAccRegent) {
            uint256 stakeBalRegent = stakedBalance[account];
            if (stakeBalRegent > 0) {
                uint256 accruedRegent = FullMath.mulDiv(
                    stakeBalRegent, currentAccRegent - priorAccRegent, ACC_PRECISION
                );
                storedClaimableRegent[account] += accruedRegent;
                unclaimedRegentLiability += accruedRegent;
            }
            rewardDebtRegent[account] = currentAccRegent;
        }

        uint256 currentAcc = accRewardPerTokenUsdc;
        uint256 priorAcc = rewardDebtUsdc[account];
        if (currentAcc <= priorAcc) {
            return;
        }

        uint256 stakeBal = stakedBalance[account];
        if (stakeBal > 0) {
            storedClaimableUsdc[
                account
            ] += FullMath.mulDiv(stakeBal, currentAcc - priorAcc, ACC_PRECISION);
        }
        rewardDebtUsdc[account] = currentAcc;
    }

    function _recordRevenue(
        uint256 received,
        RevenueSourceKind sourceKind,
        address depositor,
        bytes32 sourceTag,
        bytes32 sourceRef
    ) internal {
        require(received > 0, "NOTHING_RECEIVED");

        totalUsdcReceived += received;
        if (sourceKind == RevenueSourceKind.DirectDeposit) {
            directDepositUsdc += received;
        } else if (sourceKind == RevenueSourceKind.SurplusRedeposit) {
            surplusRedepositUsdc += received;
        }

        uint256 stakerPool = received;

        uint256 creditedToStakers = 0;
        if (stakerPool > 0) {
            uint256 deltaAcc =
                FullMath.mulDiv(stakerPool, ACC_PRECISION, revenueShareSupplyDenominator);
            if (deltaAcc > 0) {
                accRewardPerTokenUsdc += deltaAcc;

                if (totalStaked > 0) {
                    creditedToStakers = FullMath.mulDiv(deltaAcc, totalStaked, ACC_PRECISION);
                }
            }
        }

        uint256 treasuryIncrease = received - creditedToStakers;
        totalUsdcCreditedToStakers += creditedToStakers;
        treasuryResidualUsdc += treasuryIncrease;

        emit USDCRevenueDeposited(
            received,
            creditedToStakers,
            treasuryIncrease,
            sourceKind,
            depositor,
            sourceTag,
            sourceRef
        );
    }

    function _recordUsdcClaim(uint256 amount) internal {
        uint256 outstandingCredit = totalUsdcCreditedToStakers - totalClaimedUsdc;
        if (amount > outstandingCredit) {
            uint256 roundingOverage = amount - outstandingCredit;
            treasuryResidualUsdc -= roundingOverage;
            totalUsdcCreditedToStakers += roundingOverage;
        }
        totalClaimedUsdc += amount;
    }

    function _withdrawRegentRewardPool(uint256 amount, address recipient) internal {
        require(amount != 0, "AMOUNT_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");
        require(sweepableRegentRewardPool() >= amount, "REWARD_POOL_LOW");

        _pushExactStakeToken(recipient, amount);
    }

    function _previewTotalEmittedRegent() internal view returns (uint256) {
        uint256 currentAcc = _previewAccRewardPerTokenRegent();
        if (currentAcc <= accRewardPerTokenRegent || totalStaked == 0) {
            return totalEmittedRegent;
        }

        uint256 deltaAcc = currentAcc - accRewardPerTokenRegent;
        return totalEmittedRegent + FullMath.mulDiv(totalStaked, deltaAcc, ACC_PRECISION);
    }

    function _previewAccRewardPerTokenRegent() internal view returns (uint256 currentAcc) {
        currentAcc = accRewardPerTokenRegent;
        if (emissionAprBps == 0 || totalStaked == 0) {
            return currentAcc;
        }

        uint256 elapsed = block.timestamp - lastEmissionUpdate;
        if (elapsed == 0) {
            return currentAcc;
        }

        uint256 deltaAcc = FullMath.mulDiv(
            uint256(emissionAprBps) * elapsed, ACC_PRECISION, BPS_DENOMINATOR * SECONDS_PER_YEAR
        );
        return currentAcc + deltaAcc;
    }

    function _settleRegentEmissions() internal {
        uint256 timestamp = block.timestamp;
        if (timestamp <= lastEmissionUpdate) {
            return;
        }

        if (emissionAprBps == 0 || totalStaked == 0) {
            lastEmissionUpdate = timestamp;
            return;
        }

        uint256 elapsed = timestamp - lastEmissionUpdate;
        uint256 deltaAcc = FullMath.mulDiv(
            uint256(emissionAprBps) * elapsed, ACC_PRECISION, BPS_DENOMINATOR * SECONDS_PER_YEAR
        );
        if (deltaAcc == 0) {
            lastEmissionUpdate = timestamp;
            return;
        }

        accRewardPerTokenRegent += deltaAcc;
        totalEmittedRegent += FullMath.mulDiv(totalStaked, deltaAcc, ACC_PRECISION);
        lastEmissionUpdate = timestamp;
    }

    // slither-disable-next-line reentrancy-balance
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

    // slither-disable-next-line reentrancy-balance
    function _pushExactStakeToken(address recipient, uint256 amount) internal {
        uint256 beforeBalance = IERC20SupplyMinimal(stakeToken).balanceOf(recipient);
        stakeToken.safeTransfer(recipient, amount);
        uint256 afterBalance = IERC20SupplyMinimal(stakeToken).balanceOf(recipient);
        require(afterBalance - beforeBalance == amount, "STAKE_TOKEN_OUT_EXACT");
    }
}
