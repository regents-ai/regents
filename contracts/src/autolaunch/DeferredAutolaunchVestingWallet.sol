// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol";

contract DeferredAutolaunchVestingWallet {
    using SafeTransferLib for address;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint16 public constant CLIFF_BPS = 1500;
    uint64 public constant CLIFF_SECONDS = 10 days;
    uint64 public constant DURATION_SECONDS = 365 days;
    uint64 internal constant DEFAULT_ROTATION_DELAY = 3 days;

    address public beneficiary;
    address public pendingBeneficiary;
    uint64 public pendingBeneficiaryEta;
    uint64 public immutable rotationDelay;
    uint64 public immutable startTimestamp;
    address public immutable launchToken;

    uint256 public releasedLaunchToken;
    uint256 private _reentrancyGuard = 1;

    event LaunchTokenReleased(address indexed beneficiary, uint256 amount);
    event BeneficiaryRotationProposed(
        address indexed currentBeneficiary, address indexed pendingBeneficiary, uint64 eta
    );
    event BeneficiaryRotationCancelled(
        address indexed currentBeneficiary, address indexed cancelledBeneficiary
    );
    event BeneficiaryRotationExecuted(
        address indexed oldBeneficiary, address indexed newBeneficiary
    );
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

    constructor(address beneficiary_, uint64 startTimestamp_, address launchToken_) {
        require(beneficiary_ != address(0), "BENEFICIARY_ZERO");
        require(startTimestamp_ != 0, "START_ZERO");
        require(launchToken_ != address(0), "LAUNCH_TOKEN_ZERO");

        beneficiary = beneficiary_;
        rotationDelay = DEFAULT_ROTATION_DELAY;
        startTimestamp = startTimestamp_;
        launchToken = launchToken_;
    }

    function releasableLaunchToken() external view returns (uint256) {
        return _vestedAmount(_currentTime()) - releasedLaunchToken;
    }

    function releaseLaunchToken() external nonReentrant returns (uint256 amount) {
        uint256 vestedAmount = _vestedAmount(_currentTime());
        amount = vestedAmount - releasedLaunchToken;
        require(amount != 0, "NOTHING_TO_RELEASE");

        releasedLaunchToken = vestedAmount;
        launchToken.safeTransfer(beneficiary, amount);
        emit LaunchTokenReleased(beneficiary, amount);
    }

    function proposeBeneficiaryRotation(address newBeneficiary) external onlyBeneficiary {
        require(newBeneficiary != address(0), "BENEFICIARY_ZERO");
        require(newBeneficiary != beneficiary, "BENEFICIARY_UNCHANGED");

        uint64 eta = uint64(_currentTime()) + rotationDelay;
        pendingBeneficiary = newBeneficiary;
        pendingBeneficiaryEta = eta;
        emit BeneficiaryRotationProposed(beneficiary, newBeneficiary, eta);
    }

    function cancelBeneficiaryRotation() external onlyBeneficiary {
        address cancelledBeneficiary = pendingBeneficiary;
        require(cancelledBeneficiary != address(0), "PENDING_BENEFICIARY_ZERO");
        pendingBeneficiary = address(0);
        pendingBeneficiaryEta = 0;
        emit BeneficiaryRotationCancelled(beneficiary, cancelledBeneficiary);
    }

    function executeBeneficiaryRotation() external {
        address nextBeneficiary = pendingBeneficiary;
        require(nextBeneficiary != address(0), "PENDING_BENEFICIARY_ZERO");
        require(_currentTime() >= pendingBeneficiaryEta, "ROTATION_NOT_READY");

        address oldBeneficiary = beneficiary;
        beneficiary = nextBeneficiary;
        pendingBeneficiary = address(0);
        pendingBeneficiaryEta = 0;
        emit BeneficiaryRotationExecuted(oldBeneficiary, nextBeneficiary);
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

    function vestedLaunchToken() external view returns (uint256) {
        return _vestedAmount(_currentTime());
    }

    function _currentTime() internal view returns (uint256 timestamp) {
        timestamp = block.timestamp;
    }

    function _vestedAmount(uint256 timestamp) internal view returns (uint256) {
        uint256 totalAllocation =
            IERC20SupplyMinimal(launchToken).balanceOf(address(this)) + releasedLaunchToken;

        if (timestamp < startTimestamp + CLIFF_SECONDS) {
            return 0;
        }

        if (timestamp >= startTimestamp + DURATION_SECONDS) {
            return totalAllocation;
        }

        uint256 cliffAmount = FullMath.mulDiv(totalAllocation, CLIFF_BPS, BPS_DENOMINATOR);
        uint256 remaining = totalAllocation - cliffAmount;
        uint256 elapsedAfterCliff = timestamp - (startTimestamp + CLIFF_SECONDS);
        uint256 linearDuration = DURATION_SECONDS - CLIFF_SECONDS;
        uint256 linearVested = FullMath.mulDiv(remaining, elapsedAfterCliff, linearDuration);

        return cliffAmount + linearVested;
    }
}
