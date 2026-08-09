// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol";
import {IRevenueShareSplitter} from "src/autolaunch/revenue/interfaces/IRevenueShareSplitter.sol";
import {
    ISubjectPaymentReceiver
} from "src/autolaunch/revenue/interfaces/ISubjectPaymentReceiver.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {InputBounds} from "src/autolaunch/revenue/libraries/InputBounds.sol";

contract PaymentLinkReceiver is ISubjectPaymentReceiver {
    using SafeTransferLib for address;

    address public immutable override usdc;
    address public immutable subjectRegistry;
    address public immutable factory;
    address public immutable splitter;
    address public immutable agentSafe;
    address public immutable creator;
    address public immutable controller;
    address public immutable beneficiary;
    uint16 public immutable referralBps;
    bool public immutable canonical;
    bytes32 public immutable override subjectId;
    uint256 private _reentrancyGuard = 1;

    string public label;
    bool public productPaused;
    bool public constant override isReceiverActive = true;
    address public constant override replacementReceiver = address(0);

    event LabelSet(string label);
    event ProductPauseSet(bool paused);
    event PaymentLinkDeposit(address indexed payer, uint256 amount, bytes32 indexed paymentRef);
    event PaymentLinkSwept(
        address indexed caller,
        address indexed destination,
        address indexed beneficiary,
        uint256 grossAmount,
        uint256 referralAmount,
        uint256 netAmount,
        uint256 amountRecognized,
        bytes32 paymentRef
    );

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    modifier onlyController() {
        require(msg.sender == controller, "ONLY_CONTROLLER");
        _;
    }

    constructor(
        address usdc_,
        address subjectRegistry_,
        bytes32 subjectId_,
        address splitter_,
        address agentSafe_,
        address creator_,
        address controller_,
        address beneficiary_,
        uint16 referralBps_,
        bool canonical_,
        string memory label_
    ) {
        require(usdc_ != address(0), "USDC_ZERO");
        require(subjectRegistry_ != address(0), "SUBJECT_REGISTRY_ZERO");
        require(subjectId_ != bytes32(0), "SUBJECT_ZERO");
        require(splitter_ != address(0), "SPLITTER_ZERO");
        require(agentSafe_ != address(0), "AGENT_SAFE_ZERO");
        require(creator_ != address(0), "CREATOR_ZERO");
        require(controller_ != address(0), "CONTROLLER_ZERO");
        require(beneficiary_ != address(0), "BENEFICIARY_ZERO");
        require(referralBps_ <= 250, "REFERRAL_BPS_TOO_HIGH");
        InputBounds.requireStringMax(label_, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");

        ISubjectRegistry.SubjectConfig memory subject =
            ISubjectRegistry(subjectRegistry_).getSubject(subjectId_);
        require(subject.lifecycle == ISubjectRegistry.Lifecycle.Active, "SUBJECT_NOT_ACTIVE");
        require(subject.splitter == splitter_, "SPLITTER_MISMATCH");
        require(subject.treasurySafe == agentSafe_, "AGENT_SAFE_MISMATCH");
        require(IRevenueShareSplitter(splitter_).usdc() == usdc_, "SPLITTER_USDC_MISMATCH");
        require(
            IRevenueShareSplitter(splitter_).subjectId() == subjectId_, "SPLITTER_SUBJECT_MISMATCH"
        );

        usdc = usdc_;
        subjectRegistry = subjectRegistry_;
        factory = msg.sender;
        splitter = splitter_;
        agentSafe = agentSafe_;
        creator = creator_;
        controller = controller_;
        beneficiary = beneficiary_;
        referralBps = referralBps_;
        canonical = canonical_;
        subjectId = subjectId_;
        label = label_;
    }

    function setLabel(string calldata label_) external onlyController {
        InputBounds.requireStringMax(label_, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");
        label = label_;
        emit LabelSet(label_);
    }

    function setProductPaused(bool paused_) external onlyController {
        productPaused = paused_;
        emit ProductPauseSet(paused_);
    }

    function setReceiverState(bool, address) external pure {
        revert("PAYMENT_LINK_IMMUTABLE");
    }

    function destination() public view override returns (address) {
        return splitter;
    }

    function depositUSDC(uint256 amount, bytes32 paymentRef)
        external
        nonReentrant
        returns (uint256 received, uint256 recognized)
    {
        _requireActiveSubject();
        require(!productPaused, "PRODUCT_PAUSED");
        require(amount != 0, "AMOUNT_ZERO");
        require(paymentRef != bytes32(0), "PAYMENT_REF_ZERO");

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        received = amount;

        emit PaymentLinkDeposit(msg.sender, received, paymentRef);

        (, recognized) = _forwardUSDC(paymentRef);
    }

    function sweepUSDC(bytes32 paymentRef)
        external
        override
        nonReentrant
        returns (uint256 balance, uint256 recognized)
    {
        require(paymentRef != bytes32(0), "PAYMENT_REF_ZERO");
        _requireActiveSubject();
        return _forwardUSDC(paymentRef);
    }

    function _forwardUSDC(bytes32 paymentRef)
        internal
        returns (uint256 balance, uint256 recognized)
    {
        require(IRevenueShareSplitter(splitter).usdc() == usdc, "SPLITTER_USDC_MISMATCH");
        require(
            IRevenueShareSplitter(splitter).subjectId() == subjectId, "SPLITTER_SUBJECT_MISMATCH"
        );

        balance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        require(balance != 0, "NOTHING_TO_SWEEP");

        uint256 referralAmount = (balance * referralBps) / 10_000;
        uint256 netAmount = balance - referralAmount;
        if (referralAmount != 0) {
            usdc.safeTransfer(beneficiary, referralAmount);
        }

        usdc.forceApprove(splitter, netAmount);
        recognized = IRevenueShareSplitter(splitter)
            .depositUSDC(netAmount, bytes32("payment_link"), paymentRef);

        emit PaymentLinkSwept(
            msg.sender,
            splitter,
            beneficiary,
            balance,
            referralAmount,
            netAmount,
            recognized,
            paymentRef
        );
    }

    receive() external payable {
        revert("ETH_NOT_ACCEPTED");
    }

    function _requireActiveSubject() internal view {
        require(
            ISubjectRegistry(subjectRegistry).lifecycleOf(subjectId)
                == ISubjectRegistry.Lifecycle.Active,
            "SUBJECT_NOT_ACTIVE"
        );
    }
}
