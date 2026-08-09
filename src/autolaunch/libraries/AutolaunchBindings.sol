// SPDX-License-Identifier: MIT
// slither-disable-next-line pragma
pragma solidity ^0.8.26;

import {
    IRegentRevenueStakingFunding
} from "src/autolaunch/interfaces/IRegentRevenueStakingFunding.sol";

library AutolaunchBindings {
    uint256 internal constant BASE_CHAIN_ID = 8453;

    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant REGENT_REVENUE_STAKING = 0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5;
    bytes32 internal constant REGENT_REVENUE_STAKING_RUNTIME_CODE_HASH =
        0xcaef93094fa27d35f5ff9e619d5ee75528c7c18f19f4f31a0a5eaba62a976497;

    address internal constant CCA_FACTORY = 0x000000001F26a0044BaA66024e7b6599c61963F8;
    uint256 internal constant CCA_FACTORY_RUNTIME_SIZE = 24_214;
    bytes32 internal constant CCA_FACTORY_RUNTIME_CODE_HASH =
        0xa1d2a90564f4f63580b25de42efaff92505c254b00fc666f65ab38126cce5cfa;

    address internal constant QUOTE_TOKEN = REGENT;
    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;

    bytes4 internal constant FUND_REGENT_REWARDS_SELECTOR =
        IRegentRevenueStakingFunding.fundRegentRewards.selector;

    struct Bindings {
        address regent;
        address staking;
        address ccaFactory;
        address quoteToken;
        address poolManager;
        address positionManager;
    }

    error WrongChain(uint256 actual);
    error BindingMismatch(bytes32 binding, address actual);
    error RuntimeMismatch(address target, bytes32 actual);
    error RuntimeSizeMismatch(address target, uint256 actual);

    function canonical() internal pure returns (Bindings memory bindings) {
        bindings = Bindings({
            regent: REGENT,
            staking: REGENT_REVENUE_STAKING,
            ccaFactory: CCA_FACTORY,
            quoteToken: QUOTE_TOKEN,
            poolManager: POOL_MANAGER,
            positionManager: POSITION_MANAGER
        });
    }

    function validate(Bindings memory bindings) internal view {
        if (block.chainid != BASE_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _requireAddress("REGENT", bindings.regent, REGENT);
        _requireAddress("STAKING", bindings.staking, REGENT_REVENUE_STAKING);
        _requireAddress("CCA_FACTORY", bindings.ccaFactory, CCA_FACTORY);
        _requireAddress("QUOTE_TOKEN", bindings.quoteToken, QUOTE_TOKEN);
        _requireAddress("POOL_MANAGER", bindings.poolManager, POOL_MANAGER);
        _requireAddress("POSITION_MANAGER", bindings.positionManager, POSITION_MANAGER);
        _requireRuntime(bindings.staking, REGENT_REVENUE_STAKING_RUNTIME_CODE_HASH);
        _requireRuntime(bindings.ccaFactory, CCA_FACTORY_RUNTIME_CODE_HASH);
        if (bindings.ccaFactory.code.length != CCA_FACTORY_RUNTIME_SIZE) {
            revert RuntimeSizeMismatch(bindings.ccaFactory, bindings.ccaFactory.code.length);
        }
    }

    function _requireAddress(bytes32 binding, address actual, address expected) private pure {
        if (actual != expected) revert BindingMismatch(binding, actual);
    }

    function _requireRuntime(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (actual != expected) revert RuntimeMismatch(target, actual);
    }
}
