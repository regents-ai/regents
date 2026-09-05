// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol";

interface ILaunchStrategyGraduation {
    function migrated() external view returns (bool);
}

contract AgentTokenVestingWallet {
    using SafeTransferLib for address;

    uint64 public constant VESTING_DURATION = 365 days;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public immutable beneficiary;
    uint64 public immutable startTimestamp;
    uint64 public immutable durationSeconds;
    address public immutable launchToken;
    address public immutable deployer;

    address public strategy;
    bool public burnedOnFailedLaunch;
    uint256 public releasedLaunchToken;
    uint256 private _reentrancyGuard = 1;

    event LaunchTokenReleased(address indexed beneficiary, uint256 amount);
    event StrategyBound(address indexed strategy);
    event LaunchTokenBurnedOnFailedLaunch(address indexed strategy, uint256 amount);
    event NativeRescued(address indexed recipient, uint256 amount);
    event UnsupportedTokenRescued(address indexed token, uint256 amount, address indexed recipient);

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "ONLY_BENEFICIARY");
        _;
    }

    constructor(
        address beneficiary_,
        uint64 startTimestamp_,
        uint64 durationSeconds_,
        address launchToken_
    ) {
        require(beneficiary_ != address(0), "BENEFICIARY_ZERO");
        require(startTimestamp_ != 0, "START_ZERO");
        require(durationSeconds_ != 0, "DURATION_ZERO");
        require(durationSeconds_ == VESTING_DURATION, "DURATION_NOT_365_DAYS");
        require(launchToken_ != address(0), "LAUNCH_TOKEN_ZERO");

        beneficiary = beneficiary_;
        startTimestamp = startTimestamp_;
        durationSeconds = durationSeconds_;
        launchToken = launchToken_;
        deployer = msg.sender;
    }

    /// @notice One-time binding of the launch strategy allowed to burn this wallet on a failed
    ///         launch. Only the wallet deployer (the launch deployment controller) can bind, and
    ///         only once — the strategy address is not known yet when the wallet is created at
    ///         launch prep.
    function bindStrategy(address strategy_) external {
        require(msg.sender == deployer, "ONLY_DEPLOYER");
        require(strategy_ != address(0), "STRATEGY_ZERO");
        require(strategy == address(0), "STRATEGY_BOUND");

        strategy = strategy_;
        emit StrategyBound(strategy_);
    }

    /// @notice Burns the entire held launch-token allocation to the canonical dead address when
    ///         the launch's auction fails to graduate. Callable only by the bound strategy, from
    ///         `recoverFailedAuction`. The agent receives nothing from a failed launch.
    function burnOnFailedLaunch() external nonReentrant returns (uint256 amount) {
        require(msg.sender == strategy, "ONLY_STRATEGY");
        require(!burnedOnFailedLaunch, "ALREADY_BURNED");

        burnedOnFailedLaunch = true;
        amount = IERC20SupplyMinimal(launchToken).balanceOf(address(this));
        if (amount != 0) {
            launchToken.safeTransfer(BURN_ADDRESS, amount);
        }

        emit LaunchTokenBurnedOnFailedLaunch(msg.sender, amount);
    }

    /// @notice True once the launch has settled (the bound strategy migrated the graduated
    ///         pool). Nothing is releasable before this: the auction resolves ~2 days after
    ///         vesting's start timestamp, and a failed launch must leave the agent with nothing
    ///         to withdraw before `recoverFailedAuction` burns the whole allocation.
    function launchGraduated() public view returns (bool) {
        return strategy != address(0) && ILaunchStrategyGraduation(strategy).migrated();
    }

    function releasableLaunchToken() external view returns (uint256) {
        if (!launchGraduated()) {
            return 0;
        }
        return _vestedAmount(_currentTime()) - releasedLaunchToken;
    }

    // Timestamp comparisons implement the fixed linear vesting schedule.
    // slither-disable-next-line timestamp
    function releaseLaunchToken() external nonReentrant returns (uint256 amount) {
        require(launchGraduated(), "LAUNCH_NOT_GRADUATED");

        uint256 vestedAmount = _vestedAmount(_currentTime());
        amount = vestedAmount - releasedLaunchToken;
        require(amount != 0, "NOTHING_TO_RELEASE");

        releasedLaunchToken = vestedAmount;
        launchToken.safeTransfer(beneficiary, amount);

        emit LaunchTokenReleased(beneficiary, amount);
    }

    function rescueNative(address recipient) external onlyBeneficiary nonReentrant {
        require(recipient != address(0), "RECIPIENT_ZERO");

        uint256 amount = address(this).balance;
        require(amount != 0, "NOTHING_TO_RESCUE");

        address(0).safeTransfer(recipient, amount);
        emit NativeRescued(recipient, amount);
    }

    function rescueUnsupportedToken(address token, uint256 amount, address recipient)
        external
        onlyBeneficiary
        nonReentrant
    {
        require(token != address(0), "TOKEN_ZERO");
        require(token != launchToken, "PROTECTED_TOKEN");
        require(amount != 0, "AMOUNT_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");

        token.safeTransfer(recipient, amount);
        emit UnsupportedTokenRescued(token, amount, recipient);
    }

    function _currentTime() internal view returns (uint256 timestamp) {
        // slither-disable-next-line timestamp
        timestamp = block.timestamp;
    }

    // Timestamp comparisons implement the fixed linear vesting schedule.
    // slither-disable-next-line timestamp
    function _vestedAmount(uint256 timestamp) internal view returns (uint256) {
        // After a failed-launch burn nothing is vestable; report exactly what was already
        // released so `releasableLaunchToken` returns 0 instead of underflowing.
        if (burnedOnFailedLaunch) {
            return releasedLaunchToken;
        }

        uint256 totalAllocation =
            IERC20SupplyMinimal(launchToken).balanceOf(address(this)) + releasedLaunchToken;

        if (timestamp <= startTimestamp) {
            return 0;
        }

        uint256 elapsed = timestamp - startTimestamp;
        if (elapsed >= durationSeconds) {
            return totalAllocation;
        }

        return (totalAllocation * elapsed) / durationSeconds;
    }
}
