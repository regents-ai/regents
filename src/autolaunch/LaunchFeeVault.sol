// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LaunchFeeRegistry} from "src/autolaunch/LaunchFeeRegistry.sol";
import {
    IRegentRevenueStakingFunding
} from "src/autolaunch/interfaces/IRegentRevenueStakingFunding.sol";
import {SafeTransferLib} from "src/shared/libraries/SafeTransferLib.sol";

interface IERC20FeeVaultView {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address account, address spender) external view returns (uint256);
}

interface IRegentRevenueStakingView is IRegentRevenueStakingFunding {
    function totalFundedRegent() external view returns (uint256);
}

contract LaunchFeeVault {
    using SafeTransferLib for address;

    address public constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address public constant REGENT_REVENUE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;

    LaunchFeeRegistry public immutable registryContract;
    address public hook;
    address public hookSetupAuthority;
    address public tokenSetupAuthority;
    address public canonicalLaunchToken;
    address public canonicalQuoteToken;
    uint256 private _reentrancyGuard = 1;

    mapping(bytes32 => mapping(address => uint256)) public treasuryAccrued;
    mapping(bytes32 => mapping(address => uint256)) public regentAccrued;

    event HookSet(address indexed hook);
    event FeeAccrued(
        bytes32 indexed poolId,
        address indexed currency,
        uint256 treasuryAmount,
        uint256 regentAmount
    );
    event TreasuryWithdrawn(
        bytes32 indexed poolId, address indexed currency, address indexed recipient, uint256 amount
    );
    event RegentShareFunded(bytes32 indexed poolId, uint256 amount);
    event CanonicalTokensSet(address indexed launchToken, address indexed quoteToken);

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    constructor(address registry_) {
        require(registry_ != address(0), "REGISTRY_ZERO");
        registryContract = LaunchFeeRegistry(registry_);
        hookSetupAuthority = msg.sender;
        tokenSetupAuthority = registryContract.setupAuthority();
    }

    function setHook(address hook_) external {
        require(msg.sender == hookSetupAuthority, "ONLY_HOOK_SETUP_AUTHORITY");
        require(hook_ != address(0), "HOOK_ZERO");
        hook = hook_;
        hookSetupAuthority = address(0);
        emit HookSet(hook_);
    }

    function setCanonicalTokens(bytes32 poolId) external {
        require(msg.sender == tokenSetupAuthority, "ONLY_TOKEN_SETUP_AUTHORITY");
        LaunchFeeRegistry.PoolConfig memory config = registryContract.getPoolConfig(poolId);
        registryContract.requireActiveFeeInfrastructure(address(this), config.hook);
        canonicalLaunchToken = config.launchToken;
        canonicalQuoteToken = config.quoteToken;
        tokenSetupAuthority = address(0);
        emit CanonicalTokensSet(config.launchToken, config.quoteToken);
    }

    function recordAccrual(
        bytes32 poolId,
        address currency,
        uint256 treasuryAmount,
        uint256 regentAmount
    ) external {
        require(msg.sender == hook, "ONLY_HOOK");
        LaunchFeeRegistry.PoolConfig memory config = registryContract.getPoolConfig(poolId);
        require(config.hookEnabled, "HOOK_DISABLED");
        require(currency == REGENT && currency == config.quoteToken, "CURRENCY_MISMATCH");
        registryContract.requireActiveFeeInfrastructure(address(this), msg.sender);

        treasuryAccrued[poolId][currency] += treasuryAmount;
        regentAccrued[poolId][currency] += regentAmount;
        emit FeeAccrued(poolId, currency, treasuryAmount, regentAmount);
    }

    function withdrawTreasury(bytes32 poolId) external nonReentrant {
        address recipient = registryContract.treasuryRecipient(poolId);
        uint256 amount = treasuryAccrued[poolId][REGENT];
        require(amount != 0, "NOTHING_ACCRUED");
        treasuryAccrued[poolId][REGENT] = 0;
        emit TreasuryWithdrawn(poolId, REGENT, recipient, amount);
        REGENT.safeTransfer(recipient, amount);
    }

    // Slither cannot infer the shared custom one-slot guard; the malicious callback/reentry
    // rollback test is the executable proof that both value-moving paths are mutually guarded.
    // slither-disable-next-line reentrancy-balance
    function fundRegentShare(bytes32 poolId) external nonReentrant {
        require(
            registryContract.regentRecipient(poolId) == REGENT_REVENUE_STAKING,
            "STAKING_DESTINATION_MISMATCH"
        );
        uint256 amount = regentAccrued[poolId][REGENT];
        require(amount != 0, "NOTHING_ACCRUED");

        IERC20FeeVaultView regent = IERC20FeeVaultView(REGENT);
        IRegentRevenueStakingView staking = IRegentRevenueStakingView(REGENT_REVENUE_STAKING);
        require(regent.allowance(address(this), REGENT_REVENUE_STAKING) == 0, "ALLOWANCE_NOT_ZERO");
        uint256 vaultBalanceBefore = regent.balanceOf(address(this));
        uint256 stakingBalanceBefore = regent.balanceOf(REGENT_REVENUE_STAKING);
        uint256 totalFundedBefore = staking.totalFundedRegent();

        regentAccrued[poolId][REGENT] = 0;
        REGENT.forceApprove(REGENT_REVENUE_STAKING, amount);
        uint256 received = staking.fundRegentRewards(amount);
        REGENT.forceApprove(REGENT_REVENUE_STAKING, 0);

        require(received == amount, "STAKING_RETURN_MISMATCH");
        // Exact token deltas are required; fee-on-transfer or donation mismatches must roll back.
        // slither-disable-next-line incorrect-equality
        require(
            regent.balanceOf(address(this)) + amount == vaultBalanceBefore, "VAULT_BALANCE_MISMATCH"
        );
        // slither-disable-next-line incorrect-equality
        require(
            regent.balanceOf(REGENT_REVENUE_STAKING) == stakingBalanceBefore + amount,
            "STAKING_BALANCE_MISMATCH"
        );
        require(
            staking.totalFundedRegent() == totalFundedBefore + amount, "STAKING_ACCOUNTING_MISMATCH"
        );
        require(
            regent.allowance(address(this), REGENT_REVENUE_STAKING) == 0, "ALLOWANCE_NOT_CLEARED"
        );
        emit RegentShareFunded(poolId, amount);
    }

    receive() external payable {
        revert("ETH_NOT_ACCEPTED");
    }
}
