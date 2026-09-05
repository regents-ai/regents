// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

contract SafeReleaseEvidenceTest is Test {
    string internal constant FIXTURE =
        "test/fixtures/safe-1.4.1-base-8453-deployment-evidence.json";

    function testSafeReleaseEvidenceMatchesFrozenTuple() public view {
        string memory json = vm.readFile(FIXTURE);

        assertEq(vm.parseJsonUint(json, ".schemaVersion"), 1);
        assertEq(vm.parseJsonUint(json, ".chainId"), 8453);
        _assertString(json, ".variant", "canonical");

        _assertString(json, ".source.repository", "https://github.com/safe-fndn/safe-smart-account");
        _assertString(json, ".source.tag", "v1.4.1");
        _assertString(json, ".source.commit", "bf943f80fec5ac647159d26161446ac5d716a294");
        _assertString(json, ".source.tree", "dbbe8faa94445342975303ff4da1471cac2052d6");

        _assertString(
            json,
            ".deploymentRegistry.repository",
            "https://github.com/safe-global/safe-deployments.git"
        );
        _assertString(json, ".deploymentRegistry.release", "v1.37.62");
        _assertString(
            json, ".deploymentRegistry.commit", "3274616f3e5e2ab1f2cba6aec8e1abb9971e61cb"
        );
        _assertString(json, ".deploymentRegistry.tree", "573a96fa5b7b6e5629d6a51d7bcd1705cd9d5faf");
        _assertString(
            json,
            ".deploymentRegistry.releasePackageSha256",
            "74c1899fc2d1475c0b5c5a9637b737339f9ba79e4775bec219fc047b6017a086"
        );

        _assertAsset(
            json,
            ".assets.safe",
            "safe.json",
            "35bccf8ecb41832f195cf2417f65637cde02359cf45b671309895cffd0310eeb",
            0x41675C099F32341bf84BFc5382aF534df5C7461a,
            0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4
        );
        _assertAsset(
            json,
            ".assets.safeProxyFactory",
            "safe_proxy_factory.json",
            "a1f853f65ab3f9878915c4a12ef40c3e15fae3c38babfcf7d37d563f07aedf8f",
            0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67,
            0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317
        );
        _assertAsset(
            json,
            ".assets.compatibilityFallbackHandler",
            "compatibility_fallback_handler.json",
            "36efb2ccaffc202fdd60f07e7f15813246e173e4b5c2cda306bc87c5d3547b54",
            0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99,
            0x7c6007a5d711cea8dfd5d91f5940ec29c7f200fe511eb1fc1397b367af3c42f9
        );

        _assertString(json, ".proxyConstruction.factoryMethod", "createProxyWithNonce");
        _assertString(json, ".proxyConstruction.initializer", "Safe.setup");
        assertEq(
            vm.parseJsonAddress(json, ".proxyConstruction.fallbackHandler"),
            0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99
        );
        _assertString(json, ".proxyConstruction.chainSpecificSaltPath", "excluded");
        _assertString(json, ".proxyConstruction.callbackPath", "excluded");

        _assertString(json, ".compiler.version", "0.7.6");
        assertFalse(vm.parseJsonBool(json, ".compiler.optimizerEnabled"));
        _assertNotSourcePinned(json, ".compiler.optimizerRuns");
        _assertNotSourcePinned(json, ".compiler.evmVersion");
        _assertNotSourcePinned(json, ".compiler.metadataBytecodeHash");
        _assertNotSourcePinned(json, ".compiler.metadataUseLiteralContent");
        _assertNotSourcePinned(json, ".compiler.viaIR");

        _assertString(json, ".eip1271.bytesMagicValue", "0x20c13b0b");
        _assertString(json, ".eip1271.bytes32MagicValue", "0x1626ba7e");
    }

    function _assertAsset(
        string memory json,
        string memory path,
        string memory filename,
        string memory artifactSha256,
        address canonicalAddress,
        bytes32 runtimeCodeHash
    ) internal pure {
        string memory url = string.concat(
            "https://raw.githubusercontent.com/safe-global/safe-deployments/",
            "3274616f3e5e2ab1f2cba6aec8e1abb9971e61cb/src/assets/v1.4.1/",
            filename
        );
        _assertString(json, string.concat(path, ".url"), url);
        _assertString(json, string.concat(path, ".sha256"), artifactSha256);
        assertEq(vm.parseJsonAddress(json, string.concat(path, ".address")), canonicalAddress);
        assertEq(
            vm.parseJsonBytes32(json, string.concat(path, ".runtimeCodeHash")), runtimeCodeHash
        );
    }

    function _assertNotSourcePinned(string memory json, string memory path) internal pure {
        _assertString(json, path, "not explicitly source-pinned");
    }

    function _assertString(string memory json, string memory path, string memory expected)
        internal
        pure
    {
        assertEq(vm.parseJsonString(json, path), expected);
    }
}
