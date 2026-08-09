// SPDX-License-Identifier: MIT
// slither-disable-next-line pragma
pragma solidity ^0.8.26;

import {IAgentSafe} from "src/autolaunch/interfaces/IAgentSafe.sol";
import {IERC1271} from "src/autolaunch/interfaces/IERC1271.sol";

library AgentSafePolicy {
    bytes20 internal constant SAFE_SOURCE_COMMIT = hex"bf943f80fec5ac647159d26161446ac5d716a294";
    bytes20 internal constant SAFE_SOURCE_TREE = hex"dbbe8faa94445342975303ff4da1471cac2052d6";
    bytes20 internal constant SAFE_DEPLOYMENTS_COMMIT =
        hex"3274616f3e5e2ab1f2cba6aec8e1abb9971e61cb";
    bytes20 internal constant SAFE_DEPLOYMENTS_TREE = hex"573a96fa5b7b6e5629d6a51d7bcd1705cd9d5faf";

    address internal constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    bytes32 internal constant SAFE_SINGLETON_RUNTIME_CODE_HASH =
        0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4;
    address internal constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    bytes32 internal constant SAFE_PROXY_FACTORY_RUNTIME_CODE_HASH =
        0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317;
    address internal constant COMPATIBILITY_FALLBACK_HANDLER =
        0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;
    bytes32 internal constant COMPATIBILITY_FALLBACK_HANDLER_RUNTIME_CODE_HASH =
        0x7c6007a5d711cea8dfd5d91f5940ec29c7f200fe511eb1fc1397b367af3c42f9;
    bytes32 internal constant SAFE_PROXY_RUNTIME_CODE_HASH =
        0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c;

    bytes4 internal constant CREATE_PROXY_WITH_NONCE_SELECTOR = 0x1688f0b9;
    bytes4 internal constant SAFE_SETUP_SELECTOR = 0xb63e800d;
    bytes4 internal constant EXCLUDED_CHAIN_SPECIFIC_PROXY_SELECTOR = 0xec9e80bb;
    bytes4 internal constant EXCLUDED_CALLBACK_PROXY_SELECTOR = 0xd18af54d;
    bytes4 internal constant EIP1271_BYTES_MAGIC_VALUE = 0x20c13b0b;
    bytes4 internal constant EIP1271_BYTES32_MAGIC_VALUE = 0x1626ba7e;

    address internal constant SENTINEL = address(0x1);
    uint256 internal constant FALLBACK_HANDLER_STORAGE_SLOT =
        uint256(0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5);
    uint256 internal constant GUARD_STORAGE_SLOT =
        uint256(0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8);

    struct ExpectedState {
        bytes32 ownersHash;
        uint256 ownerCount;
        uint256 threshold;
        uint256 nonce;
        bytes32 modulesHash;
        address guard;
    }

    error RuntimeMismatch(address target, bytes32 actual);
    error SingletonMismatch(address actual);
    error FallbackHandlerMismatch(address actual);
    error OwnersMismatch(bytes32 actualHash, uint256 actualCount);
    error InvalidThreshold(uint256 actual);
    error NonceMismatch(uint256 actual);
    error ForbiddenOwner(address owner);
    error ModulesNotEmpty();
    error GuardNotZero(address guard);
    error StorageReadMalformed(uint256 slot);
    error SignatureCallFailed();
    error InvalidSignatureMagic(bytes4 actual);

    function emptyModulesHash() internal pure returns (bytes32) {
        address[] memory modules = new address[](0);
        return keccak256(abi.encode(modules));
    }

    function validate(
        address safe,
        address controller,
        address runtime,
        ExpectedState memory expected,
        bytes32 digest,
        bytes memory signature
    ) internal view {
        _requireRuntime(SAFE_PROXY_FACTORY, SAFE_PROXY_FACTORY_RUNTIME_CODE_HASH);
        _requireRuntime(safe, SAFE_PROXY_RUNTIME_CODE_HASH);
        _requireRuntime(SAFE_SINGLETON, SAFE_SINGLETON_RUNTIME_CODE_HASH);
        _requireRuntime(
            COMPATIBILITY_FALLBACK_HANDLER, COMPATIBILITY_FALLBACK_HANDLER_RUNTIME_CODE_HASH
        );

        IAgentSafe agentSafe = IAgentSafe(safe);
        address singleton = agentSafe.masterCopy();
        if (singleton != SAFE_SINGLETON) revert SingletonMismatch(singleton);

        address fallbackHandler = _storageAddress(agentSafe, FALLBACK_HANDLER_STORAGE_SLOT);
        if (fallbackHandler != COMPATIBILITY_FALLBACK_HANDLER) {
            revert FallbackHandlerMismatch(fallbackHandler);
        }

        address[] memory owners = agentSafe.getOwners();
        bytes32 ownersHash = keccak256(abi.encode(owners));
        if (ownersHash != expected.ownersHash || owners.length != expected.ownerCount) {
            revert OwnersMismatch(ownersHash, owners.length);
        }
        for (uint256 i; i < owners.length; ++i) {
            if (owners[i] == controller || owners[i] == runtime) revert ForbiddenOwner(owners[i]);
        }

        uint256 threshold = agentSafe.getThreshold();
        if (threshold == 0 || threshold > owners.length || threshold != expected.threshold) {
            revert InvalidThreshold(threshold);
        }

        uint256 safeNonce = agentSafe.nonce();
        if (safeNonce != expected.nonce) revert NonceMismatch(safeNonce);

        (address[] memory modules, address next) = agentSafe.getModulesPaginated(SENTINEL, 1);
        bytes32 modulesHash = keccak256(abi.encode(modules));
        if (
            modules.length != 0 || next != SENTINEL || modulesHash != expected.modulesHash
                || expected.modulesHash != emptyModulesHash()
        ) revert ModulesNotEmpty();

        address guard = _storageAddress(agentSafe, GUARD_STORAGE_SLOT);
        if (guard != address(0) || guard != expected.guard) revert GuardNotZero(guard);

        _validateSignature(safe, digest, signature);
    }

    function _storageAddress(IAgentSafe safe, uint256 slot) private view returns (address value) {
        bytes memory stored = safe.getStorageAt(slot, 1);
        if (stored.length != 32) revert StorageReadMalformed(slot);
        bytes32 word = abi.decode(stored, (bytes32));
        value = address(uint160(uint256(word)));
    }

    function _validateSignature(address safe, bytes32 digest, bytes memory signature) private view {
        try IERC1271(safe).isValidSignature(digest, signature) returns (bytes4 magic) {
            if (magic != EIP1271_BYTES32_MAGIC_VALUE) revert InvalidSignatureMagic(magic);
        } catch {
            revert SignatureCallFailed();
        }
    }

    function _requireRuntime(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (actual != expected) revert RuntimeMismatch(target, actual);
    }
}
