// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/shared/auth/Owned.sol";
import {RevenueIngressAccount} from "src/autolaunch/revenue/RevenueIngressAccount.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";

contract RevenueIngressFactory is Owned {
    string internal constant DEFAULT_LABEL = "default-usdc-ingress";

    address public immutable usdc;
    address public immutable subjectRegistry;
    address public immutable controller;

    mapping(address => bool) public isIngressAccount;
    mapping(bytes32 => address) public defaultIngressOfSubject;

    event IngressAccountCreated(
        bytes32 indexed subjectId,
        address indexed ingress,
        address indexed splitter,
        address owner,
        string label,
        bool makeDefault
    );
    event DefaultIngressSet(bytes32 indexed subjectId, address indexed ingress);

    constructor(address usdc_, address subjectRegistry_, address owner_) Owned(owner_) {
        require(usdc_ != address(0), "USDC_ZERO");
        require(subjectRegistry_ != address(0), "SUBJECT_REGISTRY_ZERO");
        usdc = usdc_;
        subjectRegistry = subjectRegistry_;
        controller = SubjectRegistryController(subjectRegistry_).controller();
    }

    modifier onlyController() {
        require(msg.sender == controller, "ONLY_CONTROLLER");
        _;
    }

    function authorizedCreators(address account) external view returns (bool) {
        return account == controller;
    }

    function setAuthorizedCreator(address, bool) external pure {
        revert("LEGACY_AUTHORITY_DISABLED");
    }

    function predictDefaultIngress(bytes32 subjectId, address agentSafe)
        public
        view
        returns (address predicted)
    {
        require(subjectId != bytes32(0), "SUBJECT_ZERO");
        require(agentSafe != address(0), "AGENT_SAFE_ZERO");
        // creationCode is compiler output, not a hand-written numeric literal.
        // slither-disable-next-line too-many-digits
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(RevenueIngressAccount).creationCode,
                abi.encode(usdc, subjectRegistry, subjectId, DEFAULT_LABEL, agentSafe)
            )
        );
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), subjectId, initCodeHash)
                    )
                )
            )
        );
    }

    function createDefaultIngressAccount(bytes32 subjectId, string calldata label)
        external
        onlyController
        returns (address ingress)
    {
        require(keccak256(bytes(label)) == keccak256(bytes(DEFAULT_LABEL)), "DEFAULT_LABEL_ONLY");
        ingress = _createDefaultIngress(subjectId);
    }

    function createIngressAccount(bytes32, string calldata, bool) external pure returns (address) {
        revert("LEGACY_INGRESS_DISABLED");
    }

    function _createDefaultIngress(bytes32 subjectId) internal returns (address ingress) {
        ISubjectRegistry.SubjectConfig memory cfg =
            ISubjectRegistry(subjectRegistry).getSubject(subjectId);
        require(cfg.lifecycle == ISubjectRegistry.Lifecycle.Active, "SUBJECT_NOT_ACTIVE");
        require(defaultIngressOfSubject[subjectId] == address(0), "INGRESS_EXISTS");
        address predicted = predictDefaultIngress(subjectId, cfg.treasurySafe);
        require(cfg.ingress == predicted, "INGRESS_PREDICTION_MISMATCH");

        RevenueIngressAccount account = new RevenueIngressAccount{salt: subjectId}(
            usdc, subjectRegistry, subjectId, DEFAULT_LABEL, cfg.treasurySafe
        );
        ingress = address(account);
        require(ingress == predicted, "INGRESS_ADDRESS_MISMATCH");
        defaultIngressOfSubject[subjectId] = ingress;
        isIngressAccount[ingress] = true;

        emit DefaultIngressSet(subjectId, ingress);
        emit IngressAccountCreated(
            subjectId, ingress, cfg.splitter, cfg.treasurySafe, DEFAULT_LABEL, true
        );
    }

    function setDefaultIngress(bytes32, address) external pure {
        revert("INGRESS_IMMUTABLE");
    }

    function setIngressReceiverState(bytes32, address, bool, address) external pure {
        revert("INGRESS_IMMUTABLE");
    }

    function ingressAccountCount(bytes32 subjectId) external view returns (uint256) {
        return defaultIngressOfSubject[subjectId] == address(0) ? 0 : 1;
    }

    function ingressAccountAt(bytes32 subjectId, uint256 index) external view returns (address) {
        require(index == 0 && defaultIngressOfSubject[subjectId] != address(0), "INGRESS_INDEX_OOB");
        return defaultIngressOfSubject[subjectId];
    }

    function ingressAccountsOfSubject(bytes32 subjectId)
        external
        view
        returns (address[] memory accounts)
    {
        address ingress = defaultIngressOfSubject[subjectId];
        accounts = new address[](ingress == address(0) ? 0 : 1);
        if (ingress != address(0)) accounts[0] = ingress;
    }
}

interface SubjectRegistryController {
    function controller() external view returns (address);
}
