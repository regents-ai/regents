// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/shared/auth/Owned.sol";
import {
    IDeferredAutolaunchFactory
} from "src/autolaunch/revenue/interfaces/IDeferredAutolaunchFactory.sol";
import {
    IRegentStakingRevenueRouter
} from "src/autolaunch/revenue/interfaces/IRegentStakingRevenueRouter.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/autolaunch/revenue/RevenueShareFactory.sol";

contract DeferredAutolaunchFactory is Owned, IDeferredAutolaunchFactory {
    RevenueShareFactory public immutable revenueShareFactory;
    RevenueIngressFactory public immutable revenueIngressFactory;
    IRegentStakingRevenueRouter public immutable stakingRevenueRouter;
    address public immutable trustedTokenFactory;

    constructor(
        address owner_,
        RevenueShareFactory revenueShareFactory_,
        RevenueIngressFactory revenueIngressFactory_,
        IRegentStakingRevenueRouter stakingRevenueRouter_,
        address trustedTokenFactory_
    ) Owned(owner_) {
        require(address(revenueShareFactory_) != address(0), "REVENUE_SHARE_FACTORY_ZERO");
        require(address(revenueIngressFactory_) != address(0), "REVENUE_INGRESS_FACTORY_ZERO");
        require(address(stakingRevenueRouter_) != address(0), "STAKING_ROUTER_ZERO");
        require(trustedTokenFactory_ != address(0), "TOKEN_FACTORY_ZERO");
        require(trustedTokenFactory_.code.length != 0, "TOKEN_FACTORY_NOT_CONTRACT");
        require(revenueShareFactory_.usdc() == revenueIngressFactory_.usdc(), "USDC_MISMATCH");
        require(
            revenueShareFactory_.stakingRevenueRouter() == address(stakingRevenueRouter_),
            "STAKING_ROUTER_MISMATCH"
        );
        require(
            stakingRevenueRouter_.usdc() == revenueShareFactory_.usdc(),
            "STAKING_ROUTER_USDC_MISMATCH"
        );

        revenueShareFactory = revenueShareFactory_;
        revenueIngressFactory = revenueIngressFactory_;
        stakingRevenueRouter = stakingRevenueRouter_;
        trustedTokenFactory = trustedTokenFactory_;
    }

    function createDeferredAutolaunch(DeferredAutolaunchConfig calldata)
        external
        pure
        override
        returns (DeferredAutolaunchResult memory)
    {
        revert("DEFERRED_AUTOLAUNCH_DISABLED");
    }
}
