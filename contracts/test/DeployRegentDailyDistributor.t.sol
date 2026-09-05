// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployRegentDailyDistributorScript} from "script/DeployRegentDailyDistributor.s.sol";
import {RegentDailyDistributor} from "src/autolaunch/revenue/RegentDailyDistributor.sol";

contract DeployMockERC20 {
    mapping(address => uint256) public balanceOf;
}

contract DeployMockStakingReader {
    address public stakeToken;

    constructor(address stakeToken_) {
        stakeToken = stakeToken_;
    }
}

/// @notice Proves the deploy script requires every address explicitly and refuses
///         placeholders — no silent defaults, no zero/dead/precompile values, no
///         role collisions.
contract DeployRegentDailyDistributorTest is Test {
    DeployRegentDailyDistributorScript internal deployer;
    DeployMockERC20 internal regent;
    DeployMockStakingReader internal staking;

    address internal poster = address(0x9057E5);
    address internal owner = address(0xb0B0000000000000000000000000000000000001);
    address internal treasury = address(0x77Ea5000000000000000000000000000000000AA);

    function setUp() public {
        deployer = new DeployRegentDailyDistributorScript();
        regent = new DeployMockERC20();
        staking = new DeployMockStakingReader(address(regent));
    }

    function _config()
        internal
        view
        returns (DeployRegentDailyDistributorScript.ScriptConfig memory cfg)
    {
        cfg.regentToken = address(regent);
        cfg.staking = address(staking);
        cfg.poster = poster;
        cfg.owner = owner;
        cfg.treasury = treasury;
    }

    function test_DeploysWithExplicitConfig() public {
        RegentDailyDistributor distributor = deployer.deploy(_config());
        assertEq(distributor.regent(), address(regent));
        assertEq(distributor.staking(), address(staking));
        assertEq(distributor.poster(), poster);
        assertEq(distributor.owner(), owner);
        assertEq(distributor.treasury(), treasury);
    }

    function test_RejectsZeroAndPlaceholderAddresses() public {
        DeployRegentDailyDistributorScript.ScriptConfig memory cfg = _config();
        cfg.treasury = address(0);
        vm.expectRevert(bytes("TREASURY_ZERO"));
        deployer.validateConfig(cfg);

        cfg = _config();
        cfg.poster = address(0x1); // precompile-range placeholder
        vm.expectRevert(bytes("POSTER_PLACEHOLDER"));
        deployer.validateConfig(cfg);

        cfg = _config();
        cfg.owner = 0x000000000000000000000000000000000000dEaD;
        vm.expectRevert(bytes("OWNER_PLACEHOLDER"));
        deployer.validateConfig(cfg);
    }

    function test_RejectsCodelessContractsAndRoleCollisions() public {
        DeployRegentDailyDistributorScript.ScriptConfig memory cfg = _config();
        cfg.staking = address(0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa); // no code
        vm.expectRevert(bytes("STAKING_NO_CODE"));
        deployer.validateConfig(cfg);

        cfg = _config();
        cfg.poster = cfg.owner;
        vm.expectRevert(bytes("POSTER_IS_OWNER"));
        deployer.validateConfig(cfg);

        cfg = _config();
        cfg.treasury = cfg.regentToken;
        vm.expectRevert(bytes("TREASURY_IS_CONTRACT"));
        deployer.validateConfig(cfg);
    }

    function test_LoadFromEnvRequiresEveryVariable() public {
        // No DISTRIBUTOR_* env is set in tests: the loader must revert rather than
        // fall back to any default.
        vm.expectRevert();
        deployer.loadConfigFromEnv();
    }
}
