// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/shared/auth/Owned.sol";
import {IRevenueShareSplitter} from "src/autolaunch/revenue/interfaces/IRevenueShareSplitter.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {PaymentLinkReceiver} from "src/autolaunch/revenue/PaymentLinkReceiver.sol";
import {InputBounds} from "src/autolaunch/revenue/libraries/InputBounds.sol";

contract PaymentLinkFactory is Owned {
    uint256 public constant MAX_PUBLIC_LINKS_PER_CREATOR_PER_SUBJECT = 16;
    uint256 public constant MAX_CANONICAL_LINKS_PER_SUBJECT = 1;
    uint16 public constant MAX_REFERRAL_BPS = 250;
    uint256 public constant MAX_PAGE_SIZE = 100;

    address public immutable usdc;
    address public immutable subjectRegistry;
    address public immutable controller;

    struct PaymentLinkMeta {
        bytes32 subjectId;
        address creator;
        address controller;
        bool canonical;
    }

    mapping(address => bool) public isPaymentLink;
    mapping(address => PaymentLinkMeta) public paymentLinkMeta;
    mapping(bytes32 => address[]) private canonicalPaymentLinksBySubject;
    mapping(address => address[]) private paymentLinksByCreator;
    mapping(bytes32 => mapping(address => uint256)) public publicLinkCountByCreatorForSubject;

    event PaymentLinkCreated(
        bytes32 indexed subjectId,
        address indexed receiver,
        address indexed creator,
        address controller,
        address beneficiary,
        uint16 referralBps,
        address splitter,
        string label,
        bool canonical
    );
    event PaymentLinkCanonicalSet(
        bytes32 indexed subjectId, address indexed receiver, bool canonical
    );
    event PaymentLinkReceiverStateSet(
        bytes32 indexed subjectId,
        address indexed receiver,
        bool active,
        address indexed replacement
    );

    constructor(address owner_, address usdc_, address subjectRegistry_) Owned(owner_) {
        require(usdc_ != address(0), "USDC_ZERO");
        require(subjectRegistry_ != address(0), "SUBJECT_REGISTRY_ZERO");

        usdc = usdc_;
        subjectRegistry = subjectRegistry_;
        controller = SubjectRegistryControllerForPaymentLinks(subjectRegistry_).controller();
    }

    modifier onlyController() {
        require(msg.sender == controller, "ONLY_CONTROLLER");
        _;
    }

    function createPaymentLink(bytes32 subjectId, string calldata label, bytes32 salt)
        external
        returns (address receiver)
    {
        return _createPublicPaymentLink(subjectId, msg.sender, 0, label, salt);
    }

    function createPaymentLink(
        bytes32 subjectId,
        address beneficiary,
        uint16 referralBps,
        string calldata label,
        bytes32 salt
    ) external returns (address receiver) {
        return _createPublicPaymentLink(subjectId, beneficiary, referralBps, label, salt);
    }

    function _createPublicPaymentLink(
        bytes32 subjectId,
        address beneficiary,
        uint16 referralBps,
        string calldata label,
        bytes32 salt
    ) internal returns (address receiver) {
        require(
            publicLinkCountByCreatorForSubject[subjectId][msg.sender]
                < MAX_PUBLIC_LINKS_PER_CREATOR_PER_SUBJECT,
            "PUBLIC_LINK_LIMIT"
        );
        receiver = _createPaymentLink(
            subjectId, msg.sender, msg.sender, beneficiary, referralBps, label, salt, false
        );
        publicLinkCountByCreatorForSubject[subjectId][msg.sender] += 1;
    }

    function createCanonicalPaymentLink(bytes32 subjectId, string calldata label, bytes32 salt)
        external
        onlyController
        returns (address receiver)
    {
        require(canonicalPaymentLinksBySubject[subjectId].length == 0, "CANONICAL_LINK_EXISTS");
        ISubjectRegistry.SubjectConfig memory subject = _validatedSubject(subjectId);
        receiver = _createPaymentLink(
            subjectId, controller, subject.treasurySafe, subject.treasurySafe, 0, label, salt, true
        );
    }

    function setPaymentLinkCanonical(address, bool) external pure {
        revert("CANONICAL_IMMUTABLE");
    }

    function setPaymentLinkReceiverState(address, bool, address) external pure {
        revert("PAYMENT_LINK_IMMUTABLE");
    }

    function canonicalPaymentLinkCountForSubject(bytes32 subjectId)
        external
        view
        returns (uint256)
    {
        return canonicalPaymentLinksBySubject[subjectId].length;
    }

    function canonicalPaymentLinkForSubjectAt(bytes32 subjectId, uint256 index)
        external
        view
        returns (address)
    {
        return canonicalPaymentLinksBySubject[subjectId][index];
    }

    function canonicalPaymentLinksForSubject(bytes32 subjectId, uint256 cursor, uint256 limit)
        external
        view
        returns (address[] memory links, uint256 nextCursor, bool hasMore)
    {
        return _page(canonicalPaymentLinksBySubject[subjectId], cursor, limit);
    }

    function paymentLinkCountForCreator(address creator) external view returns (uint256) {
        return paymentLinksByCreator[creator].length;
    }

    function paymentLinkForCreatorAt(address creator, uint256 index)
        external
        view
        returns (address)
    {
        return paymentLinksByCreator[creator][index];
    }

    function paymentLinksForCreator(address creator, uint256 cursor, uint256 limit)
        external
        view
        returns (address[] memory links, uint256 nextCursor, bool hasMore)
    {
        return _page(paymentLinksByCreator[creator], cursor, limit);
    }

    function _createPaymentLink(
        bytes32 subjectId,
        address creator,
        address linkController,
        address beneficiary,
        uint16 referralBps,
        string calldata label,
        bytes32 salt,
        bool canonical
    ) internal returns (address receiver) {
        require(subjectId != bytes32(0), "SUBJECT_ZERO");
        require(creator != address(0), "CREATOR_ZERO");
        require(linkController != address(0), "CONTROLLER_ZERO");
        require(beneficiary != address(0), "BENEFICIARY_ZERO");
        require(referralBps <= MAX_REFERRAL_BPS, "REFERRAL_BPS_TOO_HIGH");
        InputBounds.requireStringMax(label, InputBounds.MAX_LABEL_BYTES, "LABEL_TOO_LONG");

        ISubjectRegistry.SubjectConfig memory subject = _validatedSubject(subjectId);

        bytes32 deploymentSalt = keccak256(
            abi.encode(
                creator, linkController, beneficiary, referralBps, subjectId, salt, canonical
            )
        );
        PaymentLinkReceiver deployed = new PaymentLinkReceiver{salt: deploymentSalt}(
            usdc,
            subjectRegistry,
            subjectId,
            subject.splitter,
            subject.treasurySafe,
            creator,
            linkController,
            beneficiary,
            referralBps,
            canonical,
            label
        );
        receiver = address(deployed);

        isPaymentLink[receiver] = true;
        paymentLinkMeta[receiver] = PaymentLinkMeta({
            subjectId: subjectId, creator: creator, controller: linkController, canonical: canonical
        });
        paymentLinksByCreator[creator].push(receiver);
        if (canonical) {
            _pushCanonicalPaymentLink(subjectId, receiver);
        }

        emit PaymentLinkCreated(
            subjectId,
            receiver,
            creator,
            linkController,
            beneficiary,
            referralBps,
            subject.splitter,
            label,
            canonical
        );
    }

    function _validatedSubject(bytes32 subjectId)
        internal
        view
        returns (ISubjectRegistry.SubjectConfig memory subject)
    {
        subject = ISubjectRegistry(subjectRegistry).getSubject(subjectId);
        require(subject.lifecycle == ISubjectRegistry.Lifecycle.Active, "SUBJECT_NOT_ACTIVE");
        require(subject.treasurySafe != address(0), "AGENT_SAFE_ZERO");
        require(subject.splitter != address(0), "SPLITTER_ZERO");
        require(IRevenueShareSplitter(subject.splitter).usdc() == usdc, "SPLITTER_USDC_MISMATCH");
        require(
            IRevenueShareSplitter(subject.splitter).subjectId() == subjectId,
            "SPLITTER_SUBJECT_MISMATCH"
        );
    }

    function _pushCanonicalPaymentLink(bytes32 subjectId, address receiver) internal {
        address[] storage links = canonicalPaymentLinksBySubject[subjectId];
        require(links.length == 0, "CANONICAL_LINK_EXISTS");
        links.push(receiver);
    }

    function _page(address[] storage source, uint256 cursor, uint256 limit)
        internal
        view
        returns (address[] memory links, uint256 nextCursor, bool hasMore)
    {
        require(limit != 0, "LIMIT_ZERO");
        require(limit <= MAX_PAGE_SIZE, "LIMIT_TOO_HIGH");
        uint256 length = source.length;
        require(cursor <= length, "CURSOR_OOB");

        nextCursor = cursor + limit;
        if (nextCursor > length) {
            nextCursor = length;
        }
        hasMore = nextCursor < length;
        links = new address[](nextCursor - cursor);
        for (uint256 i = cursor; i < nextCursor; ++i) {
            links[i - cursor] = source[i];
        }
    }
}

interface SubjectRegistryControllerForPaymentLinks {
    function controller() external view returns (address);
}
