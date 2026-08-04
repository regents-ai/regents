// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/shared/auth/Owned.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/autolaunch/revenue/interfaces/IERC20SupplyMinimal.sol";
import {IRevenueShareSplitter} from "src/autolaunch/revenue/interfaces/IRevenueShareSplitter.sol";
import {
    ISubjectPaymentReceiver
} from "src/autolaunch/revenue/interfaces/ISubjectPaymentReceiver.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {InputBounds} from "src/autolaunch/revenue/libraries/InputBounds.sol";

contract RevenueIngressAccount is Owned, ISubjectPaymentReceiver {
    using SafeTransferLib for address;

    address public immutable override usdc;
    address public immutable subjectRegistry;
    address public immutable factory;
    bytes32 public immutable override subjectId;
    uint256 public constant MAX_ACCOUNTING_TAG_PAGE_SIZE = 100;
    uint256 private _reentrancyGuard = 1;

    string public label;
    bool public override isReceiverActive = true;
    address public override replacementReceiver;

    struct AccountingTag {
        uint256 blockNumber;
        address depositor;
        uint256 amount;
        bytes32 sourceTag;
    }

    AccountingTag[] private _accountingTags;

    event LabelSet(string label);
    event ReceiverStateSet(bool active, address indexed replacementReceiver);
    event AccountingTagRecorded(
        uint256 indexed index,
        address indexed depositor,
        uint256 blockNumber,
        uint256 amount,
        bytes32 sourceTag
    );
    event USDCSwept(
        address indexed caller,
        address indexed destination,
        uint256 balanceForwarded,
        uint256 amountRecognized,
        bytes32 indexed sourceRef
    );

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "ONLY_FACTORY");
        _;
    }

    constructor(
        address usdc_,
        address subjectRegistry_,
        bytes32 subjectId_,
        string memory label_,
        address owner_
    ) Owned(owner_) {
        require(usdc_ != address(0), "USDC_ZERO");
        require(subjectRegistry_ != address(0), "SUBJECT_REGISTRY_ZERO");
        require(subjectId_ != bytes32(0), "SUBJECT_ZERO");
        InputBounds.requireStringMax(label_, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");

        address splitter = ISubjectRegistry(subjectRegistry_).splitterOfSubject(subjectId_);
        require(splitter != address(0), "SPLITTER_ZERO");
        require(IRevenueShareSplitter(splitter).usdc() == usdc_, "SPLITTER_USDC_MISMATCH");
        require(
            IRevenueShareSplitter(splitter).subjectId() == subjectId_, "SPLITTER_SUBJECT_MISMATCH"
        );

        usdc = usdc_;
        subjectRegistry = subjectRegistry_;
        factory = msg.sender;
        subjectId = subjectId_;
        label = label_;
    }

    function setLabel(string calldata label_) external onlyOwner {
        InputBounds.requireStringMax(label_, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");
        label = label_;
        emit LabelSet(label_);
    }

    function setReceiverState(bool active, address replacement) external onlyFactory {
        if (replacement != address(0)) {
            require(replacement != address(this), "REPLACEMENT_IS_SELF");
        }
        isReceiverActive = active;
        replacementReceiver = replacement;
        emit ReceiverStateSet(active, replacement);
    }

    function destination() public view override returns (address splitter) {
        splitter = ISubjectRegistry(subjectRegistry).splitterOfSubject(subjectId);
        require(splitter != address(0), "SPLITTER_ZERO");
    }

    function depositUSDC(uint256 amount, bytes32 sourceTag)
        external
        nonReentrant
        returns (uint256 received)
    {
        require(isReceiverActive, "RECEIVER_INACTIVE");
        require(ISubjectRegistry(subjectRegistry).isSubjectActive(subjectId), "SUBJECT_INACTIVE");
        require(amount != 0, "AMOUNT_ZERO");

        // This ingress is configured for canonical USDC; safe transfer success is the
        // accounting source for the supported token.
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        received = amount;

        uint256 index = _accountingTags.length;
        _accountingTags.push(
            AccountingTag({
                blockNumber: block.number,
                depositor: msg.sender,
                amount: received,
                sourceTag: sourceTag
            })
        );

        emit AccountingTagRecorded(index, msg.sender, block.number, received, sourceTag);
    }

    function accountingTagCount() external view returns (uint256) {
        return _accountingTags.length;
    }

    function accountingTagAt(uint256 index)
        external
        view
        returns (uint256 blockNumber, address depositor, uint256 amount, bytes32 sourceTag)
    {
        require(index < _accountingTags.length, "TAG_INDEX_OOB");
        AccountingTag memory tag = _accountingTags[index];
        return (tag.blockNumber, tag.depositor, tag.amount, tag.sourceTag);
    }

    function accountingTagsSinceBlock(uint256 fromBlock, uint256 cursor, uint256 limit)
        external
        view
        returns (AccountingTag[] memory tags, uint256 nextCursor, bool hasMore)
    {
        require(limit != 0, "LIMIT_ZERO");
        require(limit <= MAX_ACCOUNTING_TAG_PAGE_SIZE, "LIMIT_TOO_HIGH");
        uint256 length = _accountingTags.length;
        require(cursor <= length, "CURSOR_OOB");

        uint256 count = 0;
        uint256 i = cursor;
        for (; i < length && count < limit; ++i) {
            if (_accountingTags[i].blockNumber >= fromBlock) {
                ++count;
            }
        }

        nextCursor = i;
        hasMore = nextCursor < length;
        tags = new AccountingTag[](count);

        uint256 outputIndex = 0;
        for (uint256 readIndex = cursor; readIndex < nextCursor; ++readIndex) {
            AccountingTag memory tag = _accountingTags[readIndex];
            if (tag.blockNumber >= fromBlock) {
                tags[outputIndex] = tag;
                ++outputIndex;
            }
        }
    }

    function sweepUSDC(bytes32 sourceRef)
        external
        override
        nonReentrant
        returns (uint256 balance, uint256 recognized)
    {
        // Sweeping is always safe: funds route only to the subject's canonical splitter.
        // Deactivation blocks new deposits (see depositUSDC) but must never strand held USDC.
        require(sourceRef != bytes32(0), "SOURCE_REF_ZERO");

        address splitter = destination();
        require(IRevenueShareSplitter(splitter).usdc() == usdc, "SPLITTER_USDC_MISMATCH");
        require(
            IRevenueShareSplitter(splitter).subjectId() == subjectId, "SPLITTER_SUBJECT_MISMATCH"
        );

        balance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        require(balance != 0, "NOTHING_TO_SWEEP");

        usdc.forceApprove(splitter, balance);
        recognized = IRevenueShareSplitter(splitter).recordIngressSweep(balance, sourceRef);

        emit USDCSwept(msg.sender, splitter, balance, recognized, sourceRef);
    }

    receive() external payable {
        revert("ETH_NOT_ACCEPTED");
    }

    function _isProtectedToken(address token) internal view override returns (bool) {
        return token == usdc;
    }
}
