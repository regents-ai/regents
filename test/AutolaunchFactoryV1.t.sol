// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {UERC20Factory} from "@uniswap/uerc20-factory/src/factories/UERC20Factory.sol";
import {
    AuctionParameters,
    IContinuousClearingAuction
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuction.sol";
import {
    IContinuousClearingAuctionFactory
} from "src/autolaunch/cca/interfaces/IContinuousClearingAuctionFactory.sol";
import {
    IDistributionContract
} from "src/autolaunch/cca/interfaces/external/IDistributionContract.sol";
import {AutolaunchFactoryV1} from "src/autolaunch/AutolaunchFactoryV1.sol";
import {AgentTokenVestingWallet} from "src/autolaunch/AgentTokenVestingWallet.sol";
import {IAutolaunchFactoryV1} from "src/autolaunch/interfaces/IAutolaunchFactoryV1.sol";
import {LaunchFeeInfraDeployer} from "src/autolaunch/LaunchFeeInfraDeployer.sol";
import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {LaunchFeeVault} from "src/autolaunch/LaunchFeeVault.sol";
import {LaunchPoolFeeHook} from "src/autolaunch/LaunchPoolFeeHook.sol";
import {RegentLBPStrategy} from "src/autolaunch/RegentLBPStrategy.sol";
import {
    RegentLBPStrategyDeployer,
    RegentLBPStrategyFactory
} from "src/autolaunch/RegentLBPStrategyFactory.sol";
import {PaymentLinkFactory} from "src/autolaunch/revenue/PaymentLinkFactory.sol";
import {PaymentLinkReceiver} from "src/autolaunch/revenue/PaymentLinkReceiver.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";
import {
    RevenueShareSplitterV2Deployer
} from "src/autolaunch/revenue/RevenueShareSplitterV2Deployer.sol";
import {RevenueShareSplitterV2} from "src/autolaunch/revenue/RevenueShareSplitterV2.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {ISubjectRegistry} from "src/autolaunch/revenue/interfaces/ISubjectRegistry.sol";
import {IDistributionStrategy} from "src/shared/interfaces/IDistributionStrategy.sol";
import {ITokenFactory} from "src/shared/interfaces/ITokenFactory.sol";
import {HookMiner} from "src/shared/libraries/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionDescriptor} from "@uniswap/v4-periphery/src/PositionDescriptor.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {AutolaunchBindingsTest} from "test/AutolaunchBindings.t.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

interface IUERC20LaunchToken {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function creator() external view returns (address);
    function graffiti() external view returns (bytes32);
}

contract Permit2Mock {
    struct PermitAllowance {
        uint160 amount;
        uint48 expiration;
    }

    mapping(address => mapping(address => mapping(address => PermitAllowance))) internal allowances;

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        allowances[msg.sender][token][spender] =
            PermitAllowance({amount: amount, expiration: expiration});
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        PermitAllowance storage allowed = allowances[from][token][msg.sender];
        require(block.timestamp <= allowed.expiration, "PERMIT_EXPIRED");
        require(allowed.amount >= amount, "PERMIT_ALLOWANCE_LOW");
        allowed.amount -= amount;
        require(IERC20Permit2Token(token).transferFrom(from, to, amount), "TRANSFER_FAILED");
    }
}

interface IERC20Permit2Token {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract RegentStakingFundingMock {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;

    uint256 public totalFundedRegent;
    uint256 public callCount;
    bool public failAfterPull;

    function setFailAfterPull(bool fail) external {
        failAfterPull = fail;
    }

    function fundRegentRewards(uint256 amount) external returns (uint256 received) {
        ++callCount;
        require(
            IERC20Permit2Token(REGENT).transferFrom(msg.sender, address(this), amount),
            "TRANSFER_FAILED"
        );
        totalFundedRegent += amount;
        require(!failAfterPull, "FUNDING_FAILED");
        return amount;
    }
}

contract IdentityRegistryMock {
    mapping(uint256 => address) internal owners;

    function setOwner(uint256 agentId, address owner) external {
        owners[agentId] = owner;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        address owner = owners[agentId];
        require(owner != address(0), "NOT_MINTED");
        return owner;
    }
}

contract StakingRouterBindingMock {
    address public immutable usdc;
    address public immutable subjectRegistry;
    address public immutable regentRevenueStaking;
    uint16 public constant protocolSkimBps = 200;

    constructor(address usdc_, address subjectRegistry_, address staking_) {
        usdc = usdc_;
        subjectRegistry = subjectRegistry_;
        regentRevenueStaking = staking_;
    }
}

contract AgentSafeWalletMock {
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;

    function launch(AutolaunchFactoryV1 factory, IAutolaunchFactoryV1.LaunchParams calldata params)
        external
        returns (IAutolaunchFactoryV1.LaunchResult memory)
    {
        if (params.expectedFee != 0) {
            IERC20Permit2Token(REGENT).approve(address(factory), params.expectedFee);
        }
        return factory.launch(params);
    }

    function migrate(address strategy) external {
        RegentLBPStrategy(strategy).migrate();
    }

    function progress(address strategy, uint256 bound) external returns (bool) {
        return RegentLBPStrategy(strategy).progressFinalization(bound);
    }

    function sweepQuote(address strategy) external {
        RegentLBPStrategy(strategy).sweepQuoteToken();
    }

    function sweepToken(address strategy) external {
        RegentLBPStrategy(strategy).sweepToken();
    }

    function recover(address strategy) external {
        RegentLBPStrategy(strategy).recoverFailedAuction();
    }
}

contract ReentrantTokenFactory is ITokenFactory {
    AutolaunchFactoryV1 internal factory;

    function setFactory(AutolaunchFactoryV1 factory_) external {
        factory = factory_;
    }

    function createToken(
        string calldata,
        string calldata,
        uint8,
        uint256,
        address,
        bytes calldata,
        bytes32
    ) external returns (address) {
        IAutolaunchFactoryV1.LaunchParams memory nested =
            IAutolaunchFactoryV1.LaunchParams({
                agentId: 0,
                tokenName: "nested",
                tokenSymbol: "NEST",
                startBlock: uint64(block.number + 300),
                floorPrice: 79_228_162_514_264_337_593_543_950,
                requiredRegentRaised: 1,
                expectedFee: factory.launchFee(),
                launchFeeHookSalt: bytes32(0)
            });
        (bool ok,) = address(factory)
            .call(abi.encodeWithSelector(IAutolaunchFactoryV1.launch.selector, nested));
        require(ok, "REENTRY_REJECTED");
        return address(0);
    }
}

contract LateSeamStrategyFactory is IDistributionStrategy {
    mapping(address => bool) public authorizedCreators;
    address internal failureTarget;
    bytes4 internal failureSelector;

    constructor() {
        RegentLBPStrategyDeployer deployer = new RegentLBPStrategyDeployer();
        require(address(deployer) == _strategyDeployer(), "DEPLOYER_ADDRESS_MISMATCH");
    }

    function configure(address creator, address target, bytes4 selector) external {
        authorizedCreators[creator] = true;
        failureTarget = target;
        failureSelector = selector;
    }

    function initializeDistribution(
        address token,
        uint256 amount,
        bytes calldata configData,
        bytes32
    ) external returns (IDistributionContract distributionContract) {
        require(authorizedCreators[msg.sender], "ONLY_AUTHORIZED_CREATOR");
        require(amount <= type(uint128).max, "STRATEGY_SUPPLY_TOO_LARGE");
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))))
            .mockCallRevert(failureTarget, abi.encodeWithSelector(failureSelector), bytes("SEAM"));

        RegentLBPStrategyFactory.RegentLBPStrategyConfig memory cfg =
            abi.decode(configData, (RegentLBPStrategyFactory.RegentLBPStrategyConfig));
        bytes memory constructorArguments = abi.encode(
            RegentLBPStrategy.StrategyConfig({
                token: token,
                quoteToken: cfg.quoteToken,
                auctionInitializerFactory: cfg.auctionInitializerFactory,
                auctionParameters: cfg.auctionParameters,
                officialPoolHook: cfg.officialPoolHook,
                agentSafe: cfg.agentSafe,
                vestingWallet: cfg.vestingWallet,
                operator: cfg.operator,
                positionManager: cfg.positionManager,
                poolManager: cfg.poolManager,
                subjectRegistry: cfg.subjectRegistry,
                officialPoolFee: cfg.officialPoolFee,
                officialPoolTickSpacing: cfg.officialPoolTickSpacing,
                auctionCreator: msg.sender,
                migrationBlock: cfg.migrationBlock,
                sweepBlock: cfg.sweepBlock,
                tokenSplitToAuctionMps: cfg.tokenSplitToAuctionMps,
                totalStrategySupply: uint128(amount),
                auctionTokenAmount: cfg.auctionTokenAmount,
                reserveTokenAmount: cfg.reserveTokenAmount
            })
        );
        distributionContract = IDistributionContract(
            RegentLBPStrategyDeployer(_strategyDeployer()).deploy(constructorArguments)
        );
    }

    function _strategyDeployer() private view returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(this), hex"01"))))
            );
    }
}

contract AtomicFactoryDeployer {
    SubjectRegistry public subjectRegistry;
    StakingRouterBindingMock public stakingRouter;
    RevenueShareSplitterV2Deployer public splitterDeployer;
    RevenueShareFactory public revenueShareFactory;
    RevenueIngressFactory public revenueIngressFactory;
    PaymentLinkFactory public paymentLinkFactory;
    RegentLBPStrategyFactory public strategyFactory;
    LaunchFeeInfraDeployer public feeInfraDeployer;

    function deployDependencies(
        address predictedFactory,
        address governance,
        address guardian,
        address usdc,
        address staking
    ) external {
        subjectRegistry = new SubjectRegistry(predictedFactory, governance, guardian);
        stakingRouter = new StakingRouterBindingMock(usdc, address(subjectRegistry), staking);
        splitterDeployer = new RevenueShareSplitterV2Deployer();
        revenueShareFactory = new RevenueShareFactory(
            governance, usdc, subjectRegistry, address(stakingRouter), address(splitterDeployer)
        );
        revenueIngressFactory =
            new RevenueIngressFactory(usdc, address(subjectRegistry), governance);
        paymentLinkFactory = new PaymentLinkFactory(governance, usdc, address(subjectRegistry));
        strategyFactory = new RegentLBPStrategyFactory(governance);
        feeInfraDeployer = new LaunchFeeInfraDeployer(predictedFactory);
    }

    function deployFactory(address tokenFactory, address identityRegistry, address operationsSafe)
        external
        returns (AutolaunchFactoryV1 factory)
    {
        factory = new AutolaunchFactoryV1(
            tokenFactory,
            address(strategyFactory),
            address(revenueShareFactory),
            address(revenueIngressFactory),
            address(paymentLinkFactory),
            address(feeInfraDeployer),
            identityRegistry,
            operationsSafe
        );
    }

    function deployFactoryWithStrategyFactory(
        address tokenFactory,
        address identityRegistry,
        address operationsSafe,
        address strategyFactoryOverride
    ) external returns (AutolaunchFactoryV1 factory) {
        factory = new AutolaunchFactoryV1(
            tokenFactory,
            strategyFactoryOverride,
            address(revenueShareFactory),
            address(revenueIngressFactory),
            address(paymentLinkFactory),
            address(feeInfraDeployer),
            identityRegistry,
            operationsSafe
        );
    }
}

contract AutolaunchFactoryV1Test is Test {
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant LIVE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;
    address internal constant CCA_FACTORY = 0x000000001F26a0044BaA66024e7b6599c61963F8;
    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address internal constant GUARDIAN = address(0x600D);
    uint256 internal constant SUPPLY = 100_000_000_000e18;
    uint256 internal constant TICK = 79_228_162_514_264_337_593_543_950;
    uint160 internal constant REQUIRED_HOOK_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG
        | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    struct RollbackState {
        bytes32 subjectId;
        address token;
        address vesting;
        address splitter;
        address feeRegistry;
        address feeVault;
        address feeHook;
        address strategy;
        address auction;
        address ingress;
        address paymentLink;
        address splitterDeployer;
        address strategyDeployer;
        uint64 factoryNonce;
        uint64 tokenFactoryNonce;
        uint64 splitterDeployerNonce;
        uint64 feeInfraDeployerNonce;
        uint64 strategyDeployerNonce;
        uint64 ingressFactoryNonce;
        uint64 paymentLinkFactoryNonce;
        uint64 ccaFactoryNonce;
        uint256 entryUsdcBalance;
        uint256 entryRegentBalance;
        uint256 entrySafeRegentBalance;
        uint256 entryStakingRegentBalance;
        uint256 entryTotalFundedRegent;
        uint256 entryFundingCallCount;
        uint256 entryUsdcAllowance;
        uint256 entryRegentAllowance;
        uint256 entrySafeRegentAllowance;
        uint256 entryStakingRegentAllowance;
        bytes32 ingressSentinelCodehash;
    }

    AutolaunchFactoryV1 internal factory;
    AtomicFactoryDeployer internal deployer;
    AgentSafeWalletMock internal agentSafe;
    AgentSafeWalletMock internal operationsSafe;
    UERC20Factory internal tokenFactory;
    SubjectRegistry internal subjectRegistry;
    RevenueShareFactory internal revenueShareFactory;
    RevenueIngressFactory internal revenueIngressFactory;
    PaymentLinkFactory internal paymentLinkFactory;
    RegentLBPStrategyFactory internal strategyFactory;
    LaunchFeeInfraDeployer internal feeInfraDeployer;
    IdentityRegistryMock internal identityRegistry;
    MintableERC20Mock internal usdc;
    MintableERC20Mock internal regent;
    RegentStakingFundingMock internal staking;

    function setUp() external {
        vm.chainId(8453);
        vm.roll(1000);
        vm.warp(1_800_000_000);
        AutolaunchBindingsTest bindingsFixture = new AutolaunchBindingsTest();
        bindingsFixture.setUp();
        usdc = _installToken(USDC, "USD Coin", "USDC");
        regent = _installToken(REGENT, "REGENT", "REGENT");
        Permit2Mock permit2Implementation = new Permit2Mock();
        vm.etch(PERMIT2, address(permit2Implementation).code);
        IdentityRegistryMock identityImplementation = new IdentityRegistryMock();
        vm.etch(IDENTITY_REGISTRY, address(identityImplementation).code);
        identityRegistry = IdentityRegistryMock(IDENTITY_REGISTRY);
        agentSafe = new AgentSafeWalletMock();
        operationsSafe = new AgentSafeWalletMock();
        tokenFactory = new UERC20Factory();
        _deployFactory(address(tokenFactory));
        staking = new RegentStakingFundingMock();
        vm.etch(LIVE_STAKING, address(staking).code);
        staking = RegentStakingFundingMock(LIVE_STAKING);
        regent.mint(address(agentSafe), 10_000_000e18);
        identityRegistry.setOwner(0, address(agentSafe));
    }

    function testLAUNCH_FEE_STATE_AND_ADMINInitialGetterGovernanceSetterAndZero() external {
        assertEq(factory.launchFee(), 1_000_000e18);

        vm.expectRevert("ONLY_GOVERNANCE");
        vm.prank(address(agentSafe));
        factory.setLaunchFee(7);

        vm.expectEmit(false, false, false, true, address(factory));
        emit IAutolaunchFactoryV1.LaunchFeeUpdated(1_000_000e18, 0);
        factory.setLaunchFee(0);
        assertEq(factory.launchFee(), 0);
    }

    function testFuzzLAUNCH_FEE_STATE_AND_ADMINRejectsEveryNonGovernance(
        address caller,
        uint256 fee
    ) external {
        vm.assume(caller != address(this));
        vm.expectRevert("ONLY_GOVERNANCE");
        vm.prank(caller);
        factory.setLaunchFee(fee);
        assertEq(factory.launchFee(), 1_000_000e18);
    }

    function testPOSITIVE_FEE_FUNDINGExactPullFundingAllowanceClearAndFinality() external {
        uint256 fee = factory.launchFee();
        uint256 safeBefore = regent.balanceOf(address(agentSafe));
        uint256 stakingBefore = regent.balanceOf(LIVE_STAKING);

        IAutolaunchFactoryV1.LaunchResult memory result =
            agentSafe.launch(factory, _params(0, "Positive Fee", "PFEE"));

        assertTrue(result.token.code.length != 0);
        assertEq(safeBefore - regent.balanceOf(address(agentSafe)), fee);
        assertEq(regent.balanceOf(LIVE_STAKING) - stakingBefore, fee);
        assertEq(staking.totalFundedRegent(), fee);
        assertEq(staking.callCount(), 1);
        assertEq(regent.balanceOf(address(factory)), 0);
        assertEq(regent.allowance(address(agentSafe), address(factory)), 0);
        assertEq(regent.allowance(address(factory), LIVE_STAKING), 0);
    }

    function testCARRIED_LAUNCH_FEE_PROOFGovernanceSelectedPositiveFeeLaunchesExactly() external {
        uint256 changedFee = 2_000_000e18;
        factory.setLaunchFee(changedFee);
        IAutolaunchFactoryV1.LaunchParams memory params = _params(0, "Changed Fee", "CFEE");
        uint256 safeBefore = regent.balanceOf(address(agentSafe));
        uint256 stakingBefore = regent.balanceOf(LIVE_STAKING);

        IAutolaunchFactoryV1.LaunchResult memory result = agentSafe.launch(factory, params);

        assertGt(result.token.code.length, 0);
        assertEq(safeBefore - regent.balanceOf(address(agentSafe)), changedFee);
        assertEq(regent.balanceOf(LIVE_STAKING) - stakingBefore, changedFee);
        assertEq(staking.totalFundedRegent(), changedFee);
        assertEq(regent.balanceOf(address(factory)), 0);
        assertEq(regent.allowance(address(agentSafe), address(factory)), 0);
        assertEq(regent.allowance(address(factory), LIVE_STAKING), 0);
    }

    function testCARRIED_LAUNCH_FEE_PROOFInsufficientSafeBalanceRollsBackAtPull() external {
        uint256 insufficientFee = regent.balanceOf(address(agentSafe)) + 1;
        factory.setLaunchFee(insufficientFee);
        IAutolaunchFactoryV1.LaunchParams memory params = _params(0, "No Balance", "NOBAL");
        address predictedToken = _predictedToken(params);
        bytes32 predictedSubjectId = keccak256(abi.encode(block.chainid, predictedToken));
        uint256 safeBefore = regent.balanceOf(address(agentSafe));
        uint256 stakingBefore = regent.balanceOf(LIVE_STAKING);
        uint64 factoryNonceBefore = vm.getNonce(address(factory));

        vm.expectRevert("BALANCE_LOW");
        agentSafe.launch(factory, params);

        assertEq(regent.balanceOf(address(agentSafe)), safeBefore);
        assertEq(regent.balanceOf(address(factory)), 0);
        assertEq(regent.balanceOf(LIVE_STAKING), stakingBefore);
        assertEq(staking.totalFundedRegent(), 0);
        assertEq(staking.callCount(), 0);
        assertEq(regent.allowance(address(agentSafe), address(factory)), 0);
        assertEq(regent.allowance(address(factory), LIVE_STAKING), 0);
        assertEq(predictedToken.code.length, 0);
        assertEq(subjectRegistry.subjectForIdentity(8453, IDENTITY_REGISTRY, 0), bytes32(0));
        assertEq(subjectRegistry.subjectOfStakeToken(predictedToken), bytes32(0));
        assertEq(predictedSubjectId, keccak256(abi.encode(uint256(8453), predictedToken)));
        assertEq(vm.getNonce(address(factory)), factoryNonceBefore);
    }

    function testZERO_FEE_BRANCHSkipsFeeCallsAndResidue() external {
        factory.setLaunchFee(0);
        uint256 safeBefore = regent.balanceOf(address(agentSafe));
        uint256 factoryBefore = regent.balanceOf(address(factory));
        uint256 stakingBefore = regent.balanceOf(LIVE_STAKING);

        IAutolaunchFactoryV1.LaunchResult memory result =
            agentSafe.launch(factory, _params(0, "Zero Fee", "ZFEE"));

        assertTrue(result.token.code.length != 0);
        assertEq(regent.balanceOf(address(agentSafe)), safeBefore);
        assertEq(regent.balanceOf(address(factory)), factoryBefore);
        assertEq(regent.balanceOf(LIVE_STAKING), stakingBefore);
        assertEq(staking.totalFundedRegent(), 0);
        assertEq(staking.callCount(), 0);
        assertEq(regent.allowance(address(agentSafe), address(factory)), 0);
        assertEq(regent.allowance(address(factory), LIVE_STAKING), 0);
    }

    function testREVIEWED_FEE_FRESHNESSStaleExpectedFeeRollsBackBeforePull() external {
        IAutolaunchFactoryV1.LaunchParams memory params = _params(0, "Stale Fee", "STALE");
        factory.setLaunchFee(params.expectedFee + 1);
        uint256 safeBefore = regent.balanceOf(address(agentSafe));
        uint64 factoryNonceBefore = vm.getNonce(address(factory));

        vm.expectRevert("LAUNCH_FEE_CHANGED");
        agentSafe.launch(factory, params);

        assertEq(regent.balanceOf(address(agentSafe)), safeBefore);
        assertEq(regent.balanceOf(address(factory)), 0);
        assertEq(regent.balanceOf(LIVE_STAKING), 0);
        assertEq(staking.totalFundedRegent(), 0);
        assertEq(staking.callCount(), 0);
        assertEq(regent.allowance(address(agentSafe), address(factory)), 0);
        assertEq(regent.allowance(address(factory), LIVE_STAKING), 0);
        assertEq(vm.getNonce(address(factory)), factoryNonceBefore);
    }

    function testATOMIC_FEE_FINALITYFundingFailureRestoresAllFeeResidue() external {
        staking.setFailAfterPull(true);
        IAutolaunchFactoryV1.LaunchParams memory params = _params(0, "Funding Fail", "FAIL");
        uint256 safeBefore = regent.balanceOf(address(agentSafe));
        uint64 factoryNonceBefore = vm.getNonce(address(factory));

        vm.expectRevert("FUNDING_FAILED");
        agentSafe.launch(factory, params);

        assertEq(regent.balanceOf(address(agentSafe)), safeBefore);
        assertEq(regent.balanceOf(address(factory)), 0);
        assertEq(regent.balanceOf(LIVE_STAKING), 0);
        assertEq(staking.totalFundedRegent(), 0);
        assertEq(staking.callCount(), 0);
        assertEq(regent.allowance(address(agentSafe), address(factory)), 0);
        assertEq(regent.allowance(address(factory), LIVE_STAKING), 0);
        assertEq(vm.getNonce(address(factory)), factoryNonceBefore);
    }

    function testDirectSafeLaunchCreatesExactCanonicalStackAndVectors() external {
        usdc.mint(address(factory), 7);
        IAutolaunchFactoryV1.LaunchParams memory params = _params(0, "Agent Coin", "AGENT");
        bytes32 expectedGraffiti = keccak256(abi.encode(address(agentSafe), uint256(0)));
        bytes32 expectedSubjectId = keccak256(abi.encode(uint256(8453), _predictedToken(params)));

        vm.recordLogs();
        IAutolaunchFactoryV1.LaunchResult memory result = agentSafe.launch(factory, params);
        _assertLaunchCreatedLog(vm.getRecordedLogs(), params, result, expectedSubjectId);

        assertEq(result.subjectId, keccak256(abi.encode(uint256(8453), result.token)));
        assertEq(result.subjectId, subjectRegistry.subjectOfStakeToken(result.token));
        assertEq(
            keccak256(abi.encode(uint256(8453), address(0x1001))),
            0x5945656ba578affa0fdfd3ad5a03bf38fd6899b395fbb0324b374357a0da3bce
        );
        IUERC20LaunchToken token = IUERC20LaunchToken(result.token);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.creator(), address(factory));
        assertEq(token.graffiti(), expectedGraffiti);
        assertEq(token.balanceOf(result.auction), SUPPLY / 10);
        assertEq(token.balanceOf(result.strategy), SUPPLY / 20);
        assertEq(token.balanceOf(result.vestingWallet), (SUPPLY * 85) / 100);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.allowance(address(factory), result.strategy), 0);
        assertEq(usdc.balanceOf(address(factory)), 7);

        AgentTokenVestingWallet vesting = AgentTokenVestingWallet(result.vestingWallet);
        assertEq(vesting.beneficiary(), address(agentSafe));
        assertEq(vesting.startTimestamp(), 1_800_000_000);
        assertEq(vesting.durationSeconds(), 31_536_000);
        assertEq(vesting.strategy(), result.strategy);

        RegentLBPStrategy strategy = RegentLBPStrategy(result.strategy);
        AuctionParameters memory auction = _auctionParameters(strategy);
        assertEq(auction.startBlock, params.startBlock);
        assertEq(auction.endBlock, params.startBlock + 86_401);
        assertEq(auction.claimBlock, params.startBlock + 86_465);
        assertEq(auction.tickSpacing, TICK);
        assertEq(auction.floorPrice, params.floorPrice);
        assertEq(auction.requiredCurrencyRaised, params.requiredRegentRaised);
        assertEq(auction.validationHook, address(0));
        assertEq(auction.auctionStepsData, _schedule());
        assertEq(strategy.migrationBlock(), params.startBlock + 86_529);
        assertEq(strategy.sweepBlock(), params.startBlock + 86_785);
        assertEq(strategy.tokenSplitToAuctionMps(), 6_666_666);
        assertEq(strategy.LP_CURRENCY_BPS(), 4000);
        assertEq(strategy.operator(), address(operationsSafe));
        assertEq(strategy.auctionCreator(), address(factory));

        ISubjectRegistry.SubjectConfig memory subject = subjectRegistry.getSubject(result.subjectId);
        assertEq(subject.identityAgentId, 0);
        assertEq(subject.identityChainId, 8453);
        assertEq(subject.identityRegistry, IDENTITY_REGISTRY);
        assertEq(subject.treasurySafe, address(agentSafe));
        assertEq(subject.safeRuntime, address(operationsSafe));
        assertEq(subject.ingress, result.defaultIngress);
        assertEq(subject.splitter, result.revenueShare);
        assertEq(RevenueShareSplitterV2(result.revenueShare).owner(), address(agentSafe));
        assertEq(RevenueShareSplitterV2(result.revenueShare).pendingOwner(), address(0));

        PaymentLinkReceiver link = PaymentLinkReceiver(payable(result.canonicalPaymentLink));
        assertTrue(result.defaultIngress != result.canonicalPaymentLink);
        assertEq(link.label(), params.tokenName);
        assertEq(link.subjectId(), result.subjectId);
        assertEq(link.controller(), address(agentSafe));
        assertEq(link.beneficiary(), address(agentSafe));
        assertEq(link.referralBps(), 0);
        assertTrue(link.canonical());

        LaunchFeeRegistry registry = LaunchFeeRegistry(subject.launchFeeRegistry);
        LaunchFeeVault vault = LaunchFeeVault(payable(subject.feeVault));
        assertEq(registry.setupAuthority(), address(0));
        assertEq(vault.hookSetupAuthority(), address(0));
        assertEq(vault.tokenSetupAuthority(), address(0));
        assertEq(vault.canonicalLaunchToken(), result.token);
        assertEq(vault.canonicalQuoteToken(), REGENT);
        assertTrue(registry.isRegisteredPool(result.poolId));
    }

    function testNonzeroIdentityLaunchAndDuplicateIdentityRollback() external {
        identityRegistry.setOwner(42, address(agentSafe));
        IAutolaunchFactoryV1.LaunchParams memory first = _params(42, "First", "FIRST");
        IAutolaunchFactoryV1.LaunchResult memory result = agentSafe.launch(factory, first);
        assertEq(subjectRegistry.subjectForIdentity(8453, IDENTITY_REGISTRY, 42), result.subjectId);

        IAutolaunchFactoryV1.LaunchParams memory duplicate = _params(42, "Second", "SECOND");
        address predicted = tokenFactory.getUERC20Address(
            duplicate.tokenName,
            duplicate.tokenSymbol,
            18,
            address(factory),
            keccak256(abi.encode(address(agentSafe), uint256(42)))
        );
        vm.expectRevert("IDENTITY_ALREADY_LINKED");
        agentSafe.launch(factory, duplicate);
        assertEq(predicted.code.length, 0);
        assertEq(subjectRegistry.subjectForIdentity(8453, IDENTITY_REGISTRY, 42), result.subjectId);
        assertEq(usdc.balanceOf(address(factory)), 0);
    }

    function testDuplicateIdentityZeroRollsBackWithoutFactoryPrecheck() external {
        IAutolaunchFactoryV1.LaunchResult memory result =
            agentSafe.launch(factory, _params(0, "Zero", "ZERO"));
        IAutolaunchFactoryV1.LaunchParams memory duplicate = _params(0, "Zero Two", "ZERO2");
        address predicted = tokenFactory.getUERC20Address(
            duplicate.tokenName,
            duplicate.tokenSymbol,
            18,
            address(factory),
            keccak256(abi.encode(address(agentSafe), uint256(0)))
        );
        vm.expectRevert("IDENTITY_ALREADY_LINKED");
        agentSafe.launch(factory, duplicate);
        assertEq(predicted.code.length, 0);
        assertEq(subjectRegistry.subjectForIdentity(8453, IDENTITY_REGISTRY, 0), result.subjectId);
    }

    function testRejectsEoaNonownerAndOperationsSafeCallers() external {
        address eoa = address(0xE0A);
        identityRegistry.setOwner(7, eoa);
        IAutolaunchFactoryV1.LaunchParams memory eoaParams = _params(7, "EOA", "EOA");
        vm.prank(eoa);
        vm.expectRevert("CALLER_NOT_CONTRACT");
        factory.launch(eoaParams);

        AgentSafeWalletMock nonowner = new AgentSafeWalletMock();
        identityRegistry.setOwner(8, address(agentSafe));
        IAutolaunchFactoryV1.LaunchParams memory nonownerParams = _params(8, "No", "NO");
        vm.expectRevert("IDENTITY_NOT_OWNED");
        nonowner.launch(factory, nonownerParams);

        identityRegistry.setOwner(9, address(operationsSafe));
        IAutolaunchFactoryV1.LaunchParams memory operationsParams = _params(9, "Ops", "OPS");
        vm.expectRevert("OPERATIONS_SAFE_FORBIDDEN");
        operationsSafe.launch(factory, operationsParams);
    }

    function testRejectsAllOmittedOperationsSafeDependencyCollisions() external {
        assertEq(POOL_MANAGER.code.length, 0);
        assertEq(POSITION_MANAGER.code.length, 0);
        _installCanonicalPoolContracts();
        address[6] memory canonicalDependencies =
            [USDC, REGENT, CCA_FACTORY, POOL_MANAGER, POSITION_MANAGER, LIVE_STAKING];

        for (uint256 i; i < 8; ++i) {
            AtomicFactoryDeployer collisionDeployer = new AtomicFactoryDeployer();
            uint64 nonce = vm.getNonce(address(collisionDeployer));
            address predictedFactory =
                vm.computeCreateAddress(address(collisionDeployer), nonce + 8);
            collisionDeployer.deployDependencies(
                predictedFactory, address(this), GUARDIAN, USDC, LIVE_STAKING
            );
            collisionDeployer.strategyFactory().setAuthorizedCreator(predictedFactory, true);

            address collision;
            if (i == 0) collision = address(collisionDeployer.stakingRouter());
            else if (i == 1) collision = address(collisionDeployer.splitterDeployer());
            else collision = canonicalDependencies[i - 2];

            assertGt(collision.code.length, 0);
            vm.expectRevert("OPERATIONS_SAFE_IS_DEPENDENCY");
            collisionDeployer.deployFactory(address(tokenFactory), IDENTITY_REGISTRY, collision);
        }
    }

    function testStaleHookWitnessFullyRollsBack() external {
        IAutolaunchFactoryV1.LaunchParams memory first = _params(0, "First", "FIRST");
        bytes32 staleSalt = first.launchFeeHookSalt;
        agentSafe.launch(factory, first);
        identityRegistry.setOwner(1, address(agentSafe));
        IAutolaunchFactoryV1.LaunchParams memory second = _params(1, "Second", "SECOND");
        second.launchFeeHookSalt = staleSalt;
        address predicted = _predictedToken(second);
        vm.expectRevert("HOOK_FLAGS_INVALID");
        agentSafe.launch(factory, second);
        assertEq(predicted.code.length, 0);
        assertEq(subjectRegistry.subjectForIdentity(8453, IDENTITY_REGISTRY, 1), bytes32(0));
    }

    function testReentryAtTokenCreationFullyRollsBack() external {
        ReentrantTokenFactory reentrant = new ReentrantTokenFactory();
        _deployFactory(address(reentrant));
        reentrant.setFactory(factory);
        identityRegistry.setOwner(0, address(agentSafe));
        IAutolaunchFactoryV1.LaunchParams memory params = _params(0, "Reentry", "RE");
        vm.expectRevert("REENTRY_REJECTED");
        agentSafe.launch(factory, params);
        assertEq(subjectRegistry.subjectForIdentity(8453, IDENTITY_REGISTRY, 0), bytes32(0));
    }

    function testTokenCreationSeamRollsBack() external {
        _assertSeamRollback(0);
    }

    function testRevenueCreationSeamRollsBack() external {
        _assertSeamRollback(1);
    }

    function testFeeInfrastructureCreationSeamRollsBack() external {
        _assertSeamRollback(2);
    }

    function testStrategyCreationSeamRollsBack() external {
        _assertSeamRollback(3);
    }

    function testSubjectRegistrationSeamRollsBack() external {
        _assertSeamRollback(4);
    }

    function testIngressCollisionSeamRollsBack() external {
        _assertSeamRollback(5);
    }

    function testCanonicalLinkCreationSeamRollsBack() external {
        _assertSeamRollback(6);
    }

    function testAuctionCreationSeamRollsBack() external {
        _assertSeamRollback(7);
    }

    function testPoolRegistrationSeamRollsBack() external {
        _assertSeamRollback(8);
    }

    function testFinalSetupAuthoritySeamRollsBack() external {
        _assertSeamRollback(9);
    }

    function testSuccessfulMigrationUsesFortySixtyRegentAndFinalSafeAuthority() external {
        _installCanonicalPoolContracts();
        IAutolaunchFactoryV1.LaunchParams memory params = _params(0, "Migrate", "MIG");
        IAutolaunchFactoryV1.LaunchResult memory result = agentSafe.launch(factory, params);
        RegentLBPStrategy strategy = RegentLBPStrategy(result.strategy);
        regent.mint(address(this), 201e18);
        _approveBid(result.auction, 201e18);
        vm.roll(params.startBlock);
        IContinuousClearingAuction(result.auction)
            .submitBid(
                params.floorPrice + TICK, 201e18, address(this), params.floorPrice, bytes("")
            );
        uint256 safeBefore = regent.balanceOf(address(agentSafe));

        vm.roll(params.startBlock + 86_402);
        IContinuousClearingAuction(result.auction).checkpoint();
        operationsSafe.progress(result.strategy, params.floorPrice);
        vm.roll(strategy.migrationBlock());
        operationsSafe.migrate(result.strategy);
        assertTrue(strategy.migrated());
        assertEq(strategy.migratedQuoteTokenForLP(), (201e18 * 4000) / 10_000);

        vm.roll(strategy.sweepBlock());
        operationsSafe.sweepQuote(result.strategy);
        uint256 safeQuote = regent.balanceOf(address(agentSafe)) - safeBefore;
        assertGe(safeQuote, (201e18 * 6000) / 10_000);
        assertEq(safeQuote + regent.balanceOf(POOL_MANAGER), 201e18);
        assertEq(regent.balanceOf(address(factory)), 0);
    }

    function testObjectiveFailedAuctionRetiresSubjectBurnsSupplyAndKeepsBidExitAvailable()
        external
    {
        IAutolaunchFactoryV1.LaunchParams memory params = _params(0, "Failed", "FAIL");
        IAutolaunchFactoryV1.LaunchResult memory result = agentSafe.launch(factory, params);
        RegentLBPStrategy strategy = RegentLBPStrategy(result.strategy);
        IContinuousClearingAuction auction = IContinuousClearingAuction(result.auction);
        regent.mint(address(this), 1e18);
        _approveBid(result.auction, 1e18);
        vm.roll(params.startBlock);
        uint256 bidId = auction.submitBid(
            params.floorPrice + TICK, 1e18, address(this), params.floorPrice, bytes("")
        );

        vm.roll(params.startBlock + 86_402);
        auction.checkpoint();
        operationsSafe.progress(result.strategy, params.floorPrice);
        vm.roll(strategy.sweepBlock());
        operationsSafe.recover(result.strategy);
        assertEq(
            uint256(subjectRegistry.lifecycleOf(result.subjectId)),
            uint256(ISubjectRegistry.Lifecycle.Retired)
        );
        assertEq(IUERC20LaunchToken(result.token).balanceOf(strategy.BURN_ADDRESS()), SUPPLY);
        uint256 beforeRefund = regent.balanceOf(address(this));
        auction.exitBid(bidId);
        assertEq(regent.balanceOf(address(this)) - beforeRefund, 1e18);
    }

    function testSelectorEventConstructorAndScheduleVectorsAreExact() external pure {
        assertEq(
            IAutolaunchFactoryV1.launch.selector,
            bytes4(
                keccak256("launch((uint256,string,string,uint64,uint256,uint128,uint256,bytes32))")
            )
        );
        assertEq(_schedule().length, 104);
        assertEq(
            keccak256(
                "LaunchCreated(bytes32,uint256,address,address,address,address,address,address,address,address,bytes32)"
            ),
            0xb94615399bcd85c2768d93dd0d311a8b2bf5f21033f836bfee1a08992018db18
        );
    }

    function _deployFactory(address tokenFactory_) internal {
        deployer = new AtomicFactoryDeployer();
        uint64 nonce = vm.getNonce(address(deployer));
        address predictedFactory = vm.computeCreateAddress(address(deployer), nonce + 8);
        deployer.deployDependencies(predictedFactory, address(this), GUARDIAN, USDC, LIVE_STAKING);
        assertEq(vm.getNonce(address(deployer)), nonce + 8);
        deployer.strategyFactory().setAuthorizedCreator(predictedFactory, true);
        factory = deployer.deployFactory(tokenFactory_, IDENTITY_REGISTRY, address(operationsSafe));
        assertEq(address(factory), predictedFactory);
        subjectRegistry = deployer.subjectRegistry();
        revenueShareFactory = deployer.revenueShareFactory();
        revenueIngressFactory = deployer.revenueIngressFactory();
        paymentLinkFactory = deployer.paymentLinkFactory();
        strategyFactory = deployer.strategyFactory();
        feeInfraDeployer = deployer.feeInfraDeployer();
    }

    function _deployLateSeamFactory(uint256 seam) internal {
        deployer = new AtomicFactoryDeployer();
        uint64 nonce = vm.getNonce(address(deployer));
        address predictedFactory = vm.computeCreateAddress(address(deployer), nonce + 8);
        deployer.deployDependencies(predictedFactory, address(this), GUARDIAN, USDC, LIVE_STAKING);
        feeInfraDeployer = deployer.feeInfraDeployer();

        uint64 feeNonce = vm.getNonce(address(feeInfraDeployer));
        address failureTarget =
            vm.computeCreateAddress(address(feeInfraDeployer), feeNonce + (seam == 9 ? 1 : 0));
        bytes4 failureSelector = seam == 9
            ? LaunchFeeVault.setCanonicalTokens.selector
            : LaunchFeeRegistry.registerPool.selector;
        LateSeamStrategyFactory lateStrategyFactory = new LateSeamStrategyFactory();
        lateStrategyFactory.configure(predictedFactory, failureTarget, failureSelector);

        factory = deployer.deployFactoryWithStrategyFactory(
            address(tokenFactory),
            IDENTITY_REGISTRY,
            address(operationsSafe),
            address(lateStrategyFactory)
        );
        assertEq(address(factory), predictedFactory);
        subjectRegistry = deployer.subjectRegistry();
        revenueShareFactory = deployer.revenueShareFactory();
        revenueIngressFactory = deployer.revenueIngressFactory();
        paymentLinkFactory = deployer.paymentLinkFactory();
        strategyFactory = RegentLBPStrategyFactory(address(lateStrategyFactory));
    }

    function _assertSeamRollback(uint256 seam) internal {
        if (seam == 8 || seam == 9) _deployLateSeamFactory(seam);
        uint256 agentId = seam + 100;
        identityRegistry.setOwner(agentId, address(agentSafe));
        IAutolaunchFactoryV1.LaunchParams memory params =
            _params(agentId, string.concat("Seam", vm.toString(seam)), "SEAM");
        usdc.mint(address(factory), 7);
        RollbackState memory state = _rollbackState(params);
        if (seam == 5) {
            vm.etch(state.ingress, hex"00");
            state.ingressSentinelCodehash = state.ingress.codehash;
            assertEq(state.ingressSentinelCodehash, keccak256(hex"00"));
        }
        if (seam == 0) {
            vm.mockCallRevert(address(tokenFactory), ITokenFactory.createToken.selector, "SEAM");
        }
        if (seam == 1) {
            vm.mockCallRevert(
                address(revenueShareFactory),
                RevenueShareFactory.createSubjectSplitter.selector,
                "SEAM"
            );
        }
        if (seam == 2) {
            vm.mockCallRevert(
                address(feeInfraDeployer), LaunchFeeInfraDeployer.deploy.selector, "SEAM"
            );
        }
        if (seam == 3) {
            vm.mockCallRevert(
                address(strategyFactory),
                IDistributionStrategy.initializeDistribution.selector,
                "SEAM"
            );
        }
        if (seam == 4) {
            vm.mockCallRevert(
                address(subjectRegistry), ISubjectRegistry.registerSubject.selector, "SEAM"
            );
        }
        if (seam == 6) {
            vm.mockCallRevert(
                address(paymentLinkFactory),
                PaymentLinkFactory.createCanonicalPaymentLink.selector,
                "SEAM"
            );
        }
        if (seam == 7) {
            vm.mockCallRevert(
                CCA_FACTORY, IContinuousClearingAuctionFactory.create.selector, "SEAM"
            );
        }
        if (seam == 8) {
            vm.expectCall(
                state.feeRegistry, abi.encodeWithSelector(LaunchFeeRegistry.registerPool.selector)
            );
        }
        if (seam == 9) {
            vm.expectCall(
                state.feeVault, abi.encodeWithSelector(LaunchFeeVault.setCanonicalTokens.selector)
            );
        }
        vm.recordLogs();
        if (seam == 5) vm.expectRevert();
        else vm.expectRevert(bytes("SEAM"));
        agentSafe.launch(factory, params);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        vm.clearMockedCalls();
        _assertRollbackState(state, agentId, seam == 5, entries);
    }

    function _rollbackState(IAutolaunchFactoryV1.LaunchParams memory params)
        internal
        view
        returns (RollbackState memory state)
    {
        state.token = _predictedToken(params);
        state.subjectId = keccak256(abi.encode(uint256(8453), state.token));
        state.factoryNonce = vm.getNonce(address(factory));
        state.vesting = vm.computeCreateAddress(address(factory), state.factoryNonce);

        state.splitterDeployer = address(deployer.splitterDeployer());
        state.splitterDeployerNonce = vm.getNonce(state.splitterDeployer);
        state.splitter =
            vm.computeCreateAddress(state.splitterDeployer, state.splitterDeployerNonce);

        state.feeInfraDeployerNonce = vm.getNonce(address(feeInfraDeployer));
        state.feeRegistry =
            vm.computeCreateAddress(address(feeInfraDeployer), state.feeInfraDeployerNonce);
        state.feeVault =
            vm.computeCreateAddress(address(feeInfraDeployer), state.feeInfraDeployerNonce + 1);
        state.feeHook = HookMiner.computeCreate2Address(
            address(feeInfraDeployer),
            params.launchFeeHookSalt,
            keccak256(
                abi.encodePacked(
                    type(LaunchPoolFeeHook).creationCode,
                    abi.encode(
                        address(feeInfraDeployer), POOL_MANAGER, state.feeRegistry, state.feeVault
                    )
                )
            )
        );

        state.strategyDeployer = vm.computeCreateAddress(address(strategyFactory), 1);
        state.strategyDeployerNonce = vm.getNonce(state.strategyDeployer);
        state.strategy =
            vm.computeCreateAddress(state.strategyDeployer, state.strategyDeployerNonce);
        state.auction = _predictedAuction(params, state.token, state.strategy);
        state.ingress =
            revenueIngressFactory.predictDefaultIngress(state.subjectId, address(agentSafe));
        state.paymentLink = _predictedCanonicalPaymentLink(params, state.subjectId, state.splitter);

        state.tokenFactoryNonce = vm.getNonce(address(tokenFactory));
        state.ingressFactoryNonce = vm.getNonce(address(revenueIngressFactory));
        state.paymentLinkFactoryNonce = vm.getNonce(address(paymentLinkFactory));
        state.ccaFactoryNonce = vm.getNonce(CCA_FACTORY);
        state.entryUsdcBalance = usdc.balanceOf(address(factory));
        state.entryRegentBalance = regent.balanceOf(address(factory));
        state.entrySafeRegentBalance = regent.balanceOf(address(agentSafe));
        state.entryStakingRegentBalance = regent.balanceOf(LIVE_STAKING);
        state.entryTotalFundedRegent = staking.totalFundedRegent();
        state.entryFundingCallCount = staking.callCount();
        state.entryUsdcAllowance = usdc.allowance(address(factory), state.splitter);
        state.entryRegentAllowance = regent.allowance(address(factory), state.strategy);
        state.entrySafeRegentAllowance = regent.allowance(address(agentSafe), address(factory));
        state.entryStakingRegentAllowance = regent.allowance(address(factory), LIVE_STAKING);
    }

    function _assertRollbackState(
        RollbackState memory state,
        uint256 agentId,
        bool ingressCollision,
        Vm.Log[] memory entries
    ) internal view {
        assertEq(state.token.code.length, 0);
        assertEq(state.vesting.code.length, 0);
        assertEq(state.splitter.code.length, 0);
        assertEq(state.feeRegistry.code.length, 0);
        assertEq(state.feeVault.code.length, 0);
        assertEq(state.feeHook.code.length, 0);
        assertEq(state.strategy.code.length, 0);
        assertEq(state.auction.code.length, 0);
        assertEq(state.paymentLink.code.length, 0);
        if (ingressCollision) {
            assertEq(state.ingress.code.length, 1);
            assertEq(state.ingress.codehash, state.ingressSentinelCodehash);
        } else {
            assertEq(state.ingress.code.length, 0);
        }

        assertEq(revenueShareFactory.splitterOfStakeToken(state.token), address(0));
        assertEq(revenueShareFactory.splitterOfSubject(state.subjectId), address(0));
        assertEq(subjectRegistry.subjectOfStakeToken(state.token), bytes32(0));
        assertEq(subjectRegistry.subjectCountForStakeToken(state.token), 0);
        assertEq(subjectRegistry.subjectForIdentity(8453, IDENTITY_REGISTRY, agentId), bytes32(0));
        assertEq(revenueIngressFactory.defaultIngressOfSubject(state.subjectId), address(0));
        assertFalse(revenueIngressFactory.isIngressAccount(state.ingress));
        assertEq(paymentLinkFactory.canonicalPaymentLinkCountForSubject(state.subjectId), 0);
        assertFalse(paymentLinkFactory.isPaymentLink(state.paymentLink));
        assertEq(paymentLinkFactory.paymentLinkCountForCreator(address(factory)), 0);

        assertEq(usdc.balanceOf(address(factory)), state.entryUsdcBalance);
        assertEq(regent.balanceOf(address(factory)), state.entryRegentBalance);
        assertEq(regent.balanceOf(address(agentSafe)), state.entrySafeRegentBalance);
        assertEq(regent.balanceOf(LIVE_STAKING), state.entryStakingRegentBalance);
        assertEq(staking.totalFundedRegent(), state.entryTotalFundedRegent);
        assertEq(staking.callCount(), state.entryFundingCallCount);
        assertEq(state.entryRegentBalance, 0);
        assertEq(usdc.allowance(address(factory), state.splitter), state.entryUsdcAllowance);
        assertEq(state.entryUsdcAllowance, 0);
        assertEq(regent.allowance(address(factory), state.strategy), state.entryRegentAllowance);
        assertEq(state.entryRegentAllowance, 0);
        assertEq(
            regent.allowance(address(agentSafe), address(factory)), state.entrySafeRegentAllowance
        );
        assertEq(
            regent.allowance(address(factory), LIVE_STAKING), state.entryStakingRegentAllowance
        );

        assertEq(vm.getNonce(address(factory)), state.factoryNonce);
        assertEq(vm.getNonce(address(tokenFactory)), state.tokenFactoryNonce);
        assertEq(vm.getNonce(state.splitterDeployer), state.splitterDeployerNonce);
        assertEq(vm.getNonce(address(feeInfraDeployer)), state.feeInfraDeployerNonce);
        assertEq(vm.getNonce(state.strategyDeployer), state.strategyDeployerNonce);
        assertEq(vm.getNonce(address(revenueIngressFactory)), state.ingressFactoryNonce);
        assertEq(vm.getNonce(address(paymentLinkFactory)), state.paymentLinkFactoryNonce);
        assertEq(vm.getNonce(CCA_FACTORY), state.ccaFactoryNonce);
        _assertNoLaunchCreatedLog(entries);
    }

    function _predictedAuction(
        IAutolaunchFactoryV1.LaunchParams memory params,
        address token,
        address strategy
    ) internal view returns (address) {
        uint64 endBlock = params.startBlock + 86_401;
        AuctionParameters memory auction = AuctionParameters({
            currency: REGENT,
            tokensRecipient: strategy,
            fundsRecipient: strategy,
            startBlock: params.startBlock,
            endBlock: endBlock,
            claimBlock: endBlock + 64,
            tickSpacing: TICK,
            validationHook: address(0),
            floorPrice: params.floorPrice,
            requiredCurrencyRaised: params.requiredRegentRaised,
            auctionStepsData: _schedule()
        });
        return address(
            IContinuousClearingAuctionFactory(CCA_FACTORY)
                .getAddress(token, SUPPLY / 10, abi.encode(auction), bytes32(0), strategy)
        );
    }

    function _predictedCanonicalPaymentLink(
        IAutolaunchFactoryV1.LaunchParams memory params,
        bytes32 subjectId,
        address splitter
    ) internal view returns (address) {
        bytes32 deploymentSalt = keccak256(
            abi.encode(
                address(factory),
                address(agentSafe),
                address(agentSafe),
                uint16(0),
                subjectId,
                subjectId,
                true
            )
        );
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(PaymentLinkReceiver).creationCode,
                abi.encode(
                    USDC,
                    address(subjectRegistry),
                    subjectId,
                    splitter,
                    address(agentSafe),
                    address(factory),
                    address(agentSafe),
                    address(agentSafe),
                    uint16(0),
                    true,
                    params.tokenName
                )
            )
        );
        return
            HookMiner.computeCreate2Address(
                address(paymentLinkFactory), deploymentSalt, initCodeHash
            );
    }

    function _assertLaunchCreatedLog(
        Vm.Log[] memory entries,
        IAutolaunchFactoryV1.LaunchParams memory params,
        IAutolaunchFactoryV1.LaunchResult memory result,
        bytes32 expectedSubjectId
    ) internal view {
        bytes32 signature = keccak256(
            "LaunchCreated(bytes32,uint256,address,address,address,address,address,address,address,address,bytes32)"
        );
        uint256 factoryLogCount;
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].emitter != address(factory)) continue;
            ++factoryLogCount;
            assertEq(entries[i].topics.length, 4);
            assertEq(entries[i].topics[0], signature);
            assertEq(entries[i].topics[1], expectedSubjectId);
            assertEq(uint256(entries[i].topics[2]), params.agentId);
            assertEq(address(uint160(uint256(entries[i].topics[3]))), address(agentSafe));

            IAutolaunchFactoryV1.LaunchResult memory logged;
            (
                logged.token,
                logged.auction,
                logged.strategy,
                logged.vestingWallet,
                logged.revenueShare,
                logged.defaultIngress,
                logged.canonicalPaymentLink,
                logged.poolId
            ) =
                abi.decode(
                    entries[i].data,
                    (address, address, address, address, address, address, address, bytes32)
                );
            assertEq(logged.token, result.token);
            assertEq(logged.auction, result.auction);
            assertEq(logged.strategy, result.strategy);
            assertEq(logged.vestingWallet, result.vestingWallet);
            assertEq(logged.revenueShare, result.revenueShare);
            assertEq(logged.defaultIngress, result.defaultIngress);
            assertEq(logged.canonicalPaymentLink, result.canonicalPaymentLink);
            assertEq(logged.poolId, result.poolId);
        }
        assertEq(factoryLogCount, 1);
    }

    function _assertNoLaunchCreatedLog(Vm.Log[] memory entries) internal view {
        bytes32 signature = keccak256(
            "LaunchCreated(bytes32,uint256,address,address,address,address,address,address,address,address,bytes32)"
        );
        uint256 launchCreatedCount;
        for (uint256 i; i < entries.length; ++i) {
            if (
                entries[i].emitter == address(factory) && entries[i].topics.length != 0
                    && entries[i].topics[0] == signature
            ) ++launchCreatedCount;
        }
        assertEq(launchCreatedCount, 0);
    }

    function _approveBid(address auction, uint160 amount) internal {
        regent.approve(PERMIT2, amount);
        IAllowanceTransfer(PERMIT2).approve(REGENT, auction, amount, type(uint48).max);
    }

    function _params(uint256 agentId, string memory name, string memory symbol)
        internal
        view
        returns (IAutolaunchFactoryV1.LaunchParams memory params)
    {
        params = IAutolaunchFactoryV1.LaunchParams({
            agentId: agentId,
            tokenName: name,
            tokenSymbol: symbol,
            startBlock: uint64(block.number + 300),
            floorPrice: TICK * 100,
            requiredRegentRaised: 100e18,
            expectedFee: factory.launchFee(),
            launchFeeHookSalt: _launchFeeHookSalt()
        });
    }

    function _launchFeeHookSalt() internal view returns (bytes32 hookSalt) {
        uint64 nonce = vm.getNonce(address(feeInfraDeployer));
        address launchFeeRegistry = vm.computeCreateAddress(address(feeInfraDeployer), nonce);
        address feeVault = vm.computeCreateAddress(address(feeInfraDeployer), nonce + 1);
        (hookSalt,) = HookMiner.find(
            address(feeInfraDeployer),
            REQUIRED_HOOK_FLAGS,
            type(LaunchPoolFeeHook).creationCode,
            abi.encode(address(feeInfraDeployer), POOL_MANAGER, launchFeeRegistry, feeVault)
        );
    }

    function _predictedToken(IAutolaunchFactoryV1.LaunchParams memory params)
        internal
        view
        returns (address)
    {
        return tokenFactory.getUERC20Address(
            params.tokenName,
            params.tokenSymbol,
            18,
            address(factory),
            keccak256(abi.encode(address(agentSafe), params.agentId))
        );
    }

    function _auctionParameters(RegentLBPStrategy strategy)
        internal
        view
        returns (AuctionParameters memory parameters)
    {
        (
            parameters.currency,
            parameters.tokensRecipient,
            parameters.fundsRecipient,
            parameters.startBlock,
            parameters.endBlock,
            parameters.claimBlock,
            parameters.tickSpacing,
            parameters.validationHook,
            parameters.floorPrice,
            parameters.requiredCurrencyRaised,
            parameters.auctionStepsData
        ) = strategy.auctionParameters();
    }

    function _installToken(address target, string memory name, string memory symbol)
        internal
        returns (MintableERC20Mock token)
    {
        MintableERC20Mock implementation = new MintableERC20Mock(name, symbol);
        vm.etch(target, address(implementation).code);
        token = MintableERC20Mock(target);
    }

    function _installCanonicalPoolContracts() internal {
        PoolManager poolImplementation = new PoolManager(address(this));
        vm.etch(
            POOL_MANAGER,
            _canonicalPoolRuntime(address(poolImplementation).code, address(poolImplementation))
        );
        vm.copyStorage(address(poolImplementation), POOL_MANAGER);
        WETH weth = new WETH();
        PositionDescriptor descriptor =
            new PositionDescriptor(PoolManager(POOL_MANAGER), address(weth), bytes32("ETH"));
        PositionManager positionImplementation = new PositionManager(
            PoolManager(POOL_MANAGER),
            IAllowanceTransfer(address(0xBEEF)),
            100_000,
            descriptor,
            IWETH9(address(weth))
        );
        vm.etch(POSITION_MANAGER, address(positionImplementation).code);
        vm.copyStorage(address(positionImplementation), POSITION_MANAGER);
    }

    function _canonicalPoolRuntime(bytes memory original, address implementation)
        internal
        pure
        returns (bytes memory patched)
    {
        bytes20 implementationBytes = bytes20(implementation);
        bytes20 canonicalBytes = bytes20(POOL_MANAGER);
        uint256 replacementOffset = type(uint256).max;
        uint256 implementationOccurrences;
        uint256 canonicalOccurrences;
        for (uint256 i; i + 20 <= original.length; ++i) {
            bool implementationMatch = true;
            bool canonicalMatch = true;
            for (uint256 j; j < 20; ++j) {
                if (original[i + j] != implementationBytes[j]) implementationMatch = false;
                if (original[i + j] != canonicalBytes[j]) canonicalMatch = false;
            }
            if (implementationMatch) {
                replacementOffset = i;
                ++implementationOccurrences;
            }
            if (canonicalMatch) ++canonicalOccurrences;
        }
        assertEq(implementationOccurrences, 1);
        assertEq(canonicalOccurrences, 0);
        assertNotEq(replacementOffset, type(uint256).max);

        patched = abi.encodePacked(original);
        for (uint256 i; i < original.length; ++i) {
            if (i >= replacementOffset && i < replacementOffset + 20) {
                patched[i] = canonicalBytes[i - replacementOffset];
                assertEq(patched[i], canonicalBytes[i - replacementOffset]);
            } else {
                assertEq(patched[i], original[i]);
            }
        }
    }

    function _schedule() internal pure returns (bytes memory) {
        return hex"0000360000002a8e000044000000214500004b0000001e7b00004f0000001ccd0000530000001b9c0000550000001ab300005800000019f700005a000000195a00005c00000018d400005e000000185e00005f00000017f8000061000000179b2d97e60000000001";
    }
}
