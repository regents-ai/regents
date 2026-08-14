// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Disposable two-phase CREATE sequencer for the Autolaunch deployment ceremony.
/// @dev The reviewed complete initcodes are never embedded in this runtime; they arrive as
/// calldata and are bound by nine immutable position-specific hashes. An ordinarily created
/// sequencer spends CREATE nonces 1..8 on the dependencies and nonce 9 on the factory, so every
/// created address is derived here and never supplied by the caller.
contract AutolaunchCreateSequencerV1 {
    enum Phase {
        Pending,
        DependenciesOneRunning,
        DependenciesOneDone,
        DependenciesTwoRunning,
        DependenciesTwoDone,
        FactoryRunning,
        Complete
    }

    address public immutable governance;
    bytes32 public immutable dependencyInitcodeHash1;
    bytes32 public immutable dependencyInitcodeHash2;
    bytes32 public immutable dependencyInitcodeHash3;
    bytes32 public immutable dependencyInitcodeHash4;
    bytes32 public immutable dependencyInitcodeHash5;
    bytes32 public immutable dependencyInitcodeHash6;
    bytes32 public immutable dependencyInitcodeHash7;
    bytes32 public immutable dependencyInitcodeHash8;
    bytes32 public immutable factoryInitcodeHash;

    Phase public phase;

    constructor(address governance_, bytes32[9] memory initcodeHashes) {
        require(governance_ != address(0), "GOVERNANCE_ZERO");
        governance = governance_;
        dependencyInitcodeHash1 = initcodeHashes[0];
        dependencyInitcodeHash2 = initcodeHashes[1];
        dependencyInitcodeHash3 = initcodeHashes[2];
        dependencyInitcodeHash4 = initcodeHashes[3];
        dependencyInitcodeHash5 = initcodeHashes[4];
        dependencyInitcodeHash6 = initcodeHashes[5];
        dependencyInitcodeHash7 = initcodeHashes[6];
        dependencyInitcodeHash8 = initcodeHashes[7];
        factoryInitcodeHash = initcodeHashes[8];
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "ONLY_GOVERNANCE");
        _;
    }

    /// @notice Creates reviewed dependencies one through four at CREATE nonces one through four.
    function deployDependenciesPhaseOne(bytes[4] calldata initcodes) external onlyGovernance {
        require(phase == Phase.Pending, "WRONG_PHASE");
        phase = Phase.DependenciesOneRunning;
        bytes32[4] memory hashes = [
            dependencyInitcodeHash1,
            dependencyInitcodeHash2,
            dependencyInitcodeHash3,
            dependencyInitcodeHash4
        ];
        for (uint256 i; i < 4; ++i) {
            _create(initcodes[i], hashes[i], i + 1);
        }
        phase = Phase.DependenciesOneDone;
    }

    /// @notice Creates reviewed dependencies five through eight at CREATE nonces five through eight.
    function deployDependenciesPhaseTwo(bytes[4] calldata initcodes) external onlyGovernance {
        require(phase == Phase.DependenciesOneDone, "WRONG_PHASE");
        phase = Phase.DependenciesTwoRunning;
        bytes32[4] memory hashes = [
            dependencyInitcodeHash5,
            dependencyInitcodeHash6,
            dependencyInitcodeHash7,
            dependencyInitcodeHash8
        ];
        for (uint256 i; i < 4; ++i) {
            _create(initcodes[i], hashes[i], i + 5);
        }
        phase = Phase.DependenciesTwoDone;
    }

    /// @notice Creates AutolaunchFactoryV1 at CREATE nonce nine.
    /// @dev The frozen factory constructor is the authorization enforcement point; the separate
    /// governance authorization call must already have run.
    function deployFactory(bytes calldata initcode) external onlyGovernance {
        require(phase == Phase.DependenciesTwoDone, "WRONG_PHASE");
        phase = Phase.FactoryRunning;
        _create(initcode, factoryInitcodeHash, 9);
        phase = Phase.Complete;
    }

    function _create(bytes calldata initcode, bytes32 expectedInitcodeHash, uint256 nonce) private {
        bytes memory payload = initcode;
        require(keccak256(payload) == expectedInitcodeHash, "INITCODE_HASH_MISMATCH");
        address expected = _createAddress(nonce);
        address created;
        // Raw CREATE of a caller-supplied, hash-bound initcode has no Solidity expression form.
        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            created := create(0, add(payload, 0x20), mload(payload))
        }
        require(created != address(0), "CREATE_FAILED");
        require(created == expected, "CREATE_ADDRESS_MISMATCH");
        require(created.code.length != 0, "CREATE_EMPTY_CODE");
    }

    /// @dev RLP of a twenty-byte sender and a single-byte nonce below 0x80 is a fixed 22-byte
    /// payload, which covers every nonce this sequencer can reach.
    function _createAddress(uint256 nonce) private view returns (address) {
        // casting to 'uint8' is safe because every ceremony nonce is a literal one through nine
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes1 nonceByte = bytes1(uint8(nonce));
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(this), nonceByte))))
            );
    }
}
