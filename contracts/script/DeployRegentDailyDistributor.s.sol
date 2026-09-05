// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {RegentDailyDistributor} from "src/autolaunch/revenue/RegentDailyDistributor.sol";

/// @notice Deploys the disposable daily REGENT revenue distributor.
///
///         The entire parameter surface is FIVE ADDRESSES, all immutable at deployment
///         and all required explicitly from the environment — the script refuses
///         placeholders, unset values, and duplicates. No silent defaults exist.
///
///         Required environment variables:
///           DISTRIBUTOR_REGENT_TOKEN     REGENT token (must equal staking.stakeToken())
///           DISTRIBUTOR_STAKING          live RegentRevenueStaking
///                                        (Base mainnet: 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5)
///           DISTRIBUTOR_POSTER           automated daily-root poster key
///           DISTRIBUTOR_OWNER            treasury multisig (its only right: sweep())
///           DISTRIBUTOR_TREASURY         protocol treasury — the pinned sweep destination
///
///         Values come from Sean's address confirmation (bd regent-ux9j). DO NOT run
///         against any network beyond local/test until Sean's explicit deploy go, after
///         the human audit.
contract DeployRegentDailyDistributorScript is Script {
    struct ScriptConfig {
        address regentToken;
        address staking;
        address poster;
        address owner;
        address treasury;
    }

    function deployFromEnv() external returns (RegentDailyDistributor distributor) {
        return deploy(loadConfigFromEnv());
    }

    function deploy(ScriptConfig memory cfg) public returns (RegentDailyDistributor distributor) {
        validateConfig(cfg);

        vm.startBroadcast();
        distributor = new RegentDailyDistributor(
            cfg.regentToken, cfg.staking, cfg.poster, cfg.owner, cfg.treasury
        );
        vm.stopBroadcast();

        console2.log("RegentDailyDistributor deployed:", address(distributor));
        console2.log("  regent:  ", distributor.regent());
        console2.log("  staking: ", distributor.staking());
        console2.log("  poster:  ", distributor.poster());
        console2.log("  owner:   ", distributor.owner());
        console2.log("  treasury:", distributor.treasury());
    }

    function validateConfig(ScriptConfig memory cfg) public view {
        _requireReal(cfg.regentToken, "REGENT_TOKEN");
        _requireReal(cfg.staking, "STAKING");
        _requireReal(cfg.poster, "POSTER");
        _requireReal(cfg.owner, "OWNER");
        _requireReal(cfg.treasury, "TREASURY");

        // Contracts must actually be deployed code; the constructor additionally
        // asserts staking.stakeToken() == regent on-chain.
        require(cfg.regentToken.code.length != 0, "REGENT_TOKEN_NO_CODE");
        require(cfg.staking.code.length != 0, "STAKING_NO_CODE");

        // Role-separation sanity: the automated poster key must not double as the
        // multisig or the treasury, and the token/staking addresses are not roles.
        require(cfg.poster != cfg.owner, "POSTER_IS_OWNER");
        require(cfg.poster != cfg.treasury, "POSTER_IS_TREASURY");
        require(cfg.poster != cfg.regentToken && cfg.poster != cfg.staking, "POSTER_IS_CONTRACT");
        require(cfg.owner != cfg.regentToken && cfg.owner != cfg.staking, "OWNER_IS_CONTRACT");
        require(
            cfg.treasury != cfg.regentToken && cfg.treasury != cfg.staking, "TREASURY_IS_CONTRACT"
        );
    }

    function loadConfigFromEnv() public view returns (ScriptConfig memory cfg) {
        // vm.envAddress reverts when the variable is unset or malformed, so every
        // value below is explicit — there is no default to fall through to.
        cfg.regentToken = vm.envAddress("DISTRIBUTOR_REGENT_TOKEN");
        cfg.staking = vm.envAddress("DISTRIBUTOR_STAKING");
        cfg.poster = vm.envAddress("DISTRIBUTOR_POSTER");
        cfg.owner = vm.envAddress("DISTRIBUTOR_OWNER");
        cfg.treasury = vm.envAddress("DISTRIBUTOR_TREASURY");
    }

    /// @dev Rejects unset/zero values and the well-known placeholder addresses people
    ///      leave in env templates (0x0, 0xdead, 0x1, precompile range).
    function _requireReal(address value, string memory label) internal pure {
        require(value != address(0), string.concat(label, "_ZERO"));
        require(uint160(value) > 0xFFFF, string.concat(label, "_PLACEHOLDER"));
        require(
            value != 0x000000000000000000000000000000000000dEaD,
            string.concat(label, "_PLACEHOLDER")
        );
    }
}
