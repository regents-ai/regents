// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockHookDeployer} from "test/mocks/MockHookDeployer.sol";
import {MockHookPoolManager, MockFeeSubjectRegistry} from "test/mocks/MockHookPoolManager.sol";

contract LaunchFeeInvariantHandler is Test {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    bytes32 internal constant SUBJECT_ID = keccak256("invariant-subject");

    MintableERC20Mock internal immutable regent;
    MockHookPoolManager internal immutable poolManager;
    MockFeeSubjectRegistry internal immutable subjectRegistry;
    LaunchPoolFeeVaultView internal immutable vault;
    LaunchPoolFeeHook internal immutable hook;
    bytes32 internal immutable poolId;
    PoolKey internal poolKey;

    constructor(
        MockHookPoolManager poolManager_,
        MockFeeSubjectRegistry subjectRegistry_,
        LaunchFeeVault vault_,
        LaunchPoolFeeHook hook_,
        PoolKey memory poolKey_,
        bytes32 poolId_
    ) {
        regent = MintableERC20Mock(REGENT);
        poolManager = poolManager_;
        subjectRegistry = subjectRegistry_;
        vault = LaunchPoolFeeVaultView(address(vault_));
        hook = hook_;
        poolKey = poolKey_;
        poolId = poolId_;
    }

    function swap(uint96 seed) external {
        uint256 amount = uint256(seed) % (1_000_000e18 - 100) + 100;
        regent.mint(address(poolManager), amount);
        bool regentIsCurrency0 = Currency.unwrap(poolKey.currency0) == REGENT;
        try poolManager.simulateSwap(
            address(hook),
            address(this),
            poolKey,
            SwapParams({
                zeroForOne: regentIsCurrency0,
                amountSpecified: -int256(amount),
                sqrtPriceLimitX96: 0
            }),
            -int128(int256(amount % uint256(uint128(type(int128).max)))),
            int128(int256(amount % uint256(uint128(type(int128).max))))
        ) {}
            catch {}
    }

    function setQuarantined(bool quarantined) external {
        subjectRegistry.setLifecycle(
            SUBJECT_ID,
            quarantined ? ISubjectRegistry.Lifecycle.Quarantined : ISubjectRegistry.Lifecycle.Active
        );
    }

    function directTransfer(uint96 amount) external {
        regent.mint(address(vault), amount);
    }

    function claimSubject() external {
        try vault.fundSubjectShare(poolId) {} catch {}
    }
}

interface LaunchPoolFeeVaultView {
    function fundSubjectShare(bytes32 poolId) external;
}

contract InvariantSubjectRegentSplitter {
    uint256 public constant ACC_PRECISION = 1e27;
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;

    address public immutable stakeToken;
    bytes32 public immutable subjectId;
    address public immutable subjectRegistry;
    uint256 public totalRegentReceived;
    uint256 public reservedRegent;

    constructor(address stakeToken_, bytes32 subjectId_, address subjectRegistry_) {
        stakeToken = stakeToken_;
        subjectId = subjectId_;
        subjectRegistry = subjectRegistry_;
    }

    function totalStaked() external pure returns (uint256) {
        return 0;
    }

    function accRewardPerTokenRegent() external pure returns (uint256) {
        return 0;
    }

    function fundRegentRewards(uint256 amount) external returns (uint256 received) {
        uint256 beforeBalance = MintableERC20Mock(REGENT).balanceOf(address(this));
        MintableERC20Mock(REGENT).transferFrom(msg.sender, address(this), amount);
        received = MintableERC20Mock(REGENT).balanceOf(address(this)) - beforeBalance;
        totalRegentReceived += received;
        reservedRegent += received;
    }
}

contract LaunchFeeInvariant is Test {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant AGENT_SAFE = address(0xA11CE);
    bytes32 internal constant SUBJECT_ID = keccak256("invariant-subject");

    MintableERC20Mock internal regent;
    MockHookPoolManager internal poolManager;
    MockFeeSubjectRegistry internal subjectRegistry;
    LaunchFeeRegistry internal registry;
    LaunchFeeVault internal vault;
    LaunchPoolFeeHook internal hook;
    InvariantSubjectRegentSplitter internal subjectSplitter;
    bytes32 internal poolId;

    function setUp() external {
        MintableERC20Mock implementation = new MintableERC20Mock("REGENT", "REGENT");
        vm.etch(REGENT, address(implementation).code);
        regent = MintableERC20Mock(REGENT);
        MintableERC20Mock launchToken = new MintableERC20Mock("Launch", "L");
        poolManager = new MockHookPoolManager();
        subjectRegistry = new MockFeeSubjectRegistry();
        registry = new LaunchFeeRegistry(
            AGENT_SAFE, address(this), address(subjectRegistry), SUBJECT_ID, REGENT
        );
        vault = new LaunchFeeVault(address(registry));
        subjectSplitter = new InvariantSubjectRegentSplitter(
            address(launchToken), SUBJECT_ID, address(subjectRegistry)
        );
        MockHookDeployer deployer = new MockHookDeployer();
        hook = deployer.deploy(address(poolManager), address(registry), address(vault));
        vault.setHook(address(hook));
        subjectRegistry.setSubject(
            SUBJECT_ID,
            ISubjectRegistry.SubjectConfig({
                stakeToken: address(launchToken),
                splitter: address(subjectSplitter),
                treasurySafe: AGENT_SAFE,
                ingress: address(2),
                paymentLinkFactory: address(3),
                strategy: address(this),
                launchFeeRegistry: address(registry),
                feeVault: address(vault),
                feeHook: address(hook),
                identityChainId: 0,
                identityRegistry: address(0),
                identityAgentId: 0,
                lifecycle: ISubjectRegistry.Lifecycle.Active,
                label: "subject",
                safeRuntime: address(4)
            })
        );
        poolId = registry.registerPool(
            LaunchFeeRegistry.PoolRegistration({
                launchToken: address(launchToken),
                quoteToken: REGENT,
                poolFee: 3000,
                tickSpacing: 60,
                poolManager: address(poolManager),
                hook: address(hook),
                authorizedInitializer: address(this)
            })
        );
        vault.setCanonicalTokens(poolId);
        PoolKey memory key = _poolKey(address(launchToken));
        LaunchFeeInvariantHandler handler =
            new LaunchFeeInvariantHandler(poolManager, subjectRegistry, vault, hook, key, poolId);
        targetContract(address(handler));
    }

    function invariantStoredAccrualIsAlwaysBacked() external view {
        uint256 subjectAccrued = vault.subjectAccrued(poolId, REGENT);
        uint256 protocolAccrued = vault.regentAccrued(poolId, REGENT);
        uint256 balance = regent.balanceOf(address(vault));
        assertLe(subjectAccrued, balance);
        assertLe(protocolAccrued, balance);
        assertLe(subjectAccrued + protocolAccrued, balance);
    }

    function invariantDestinationsAndAuthorityNeverDrift() external view {
        assertEq(registry.subjectStakingRecipient(poolId), address(subjectSplitter));
        assertEq(registry.regentRecipient(poolId), registry.REGENT_REVENUE_STAKING());
        assertEq(registry.agentSafe(), AGENT_SAFE);
        assertEq(registry.setupAuthority(), address(0));
        assertEq(vault.hookSetupAuthority(), address(0));
        assertEq(vault.tokenSetupAuthority(), address(0));
    }

    function _poolKey(address launchToken) internal view returns (PoolKey memory) {
        (address currency0, address currency1) =
            launchToken < REGENT ? (launchToken, REGENT) : (REGENT, launchToken);
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }
}
