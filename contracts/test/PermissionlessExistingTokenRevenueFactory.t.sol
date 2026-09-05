// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {
    IPermissionlessExistingTokenRevenueFactory
} from "src/autolaunch/revenue/interfaces/IPermissionlessExistingTokenRevenueFactory.sol";
import {
    PermissionlessExistingTokenRevenueFactory
} from "src/autolaunch/revenue/PermissionlessExistingTokenRevenueFactory.sol";
import {RevenueIngressFactory} from "src/autolaunch/revenue/RevenueIngressFactory.sol";
import {SubjectRegistry} from "src/autolaunch/revenue/SubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockRegentStakingRevenueRouter} from "test/mocks/MockRegentStakingRevenueRouter.sol";

contract NoTotalSupplyToken {}

contract PermissionlessExistingTokenRevenueFactoryTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant CREATOR = address(0x1111);
    address internal constant OTHER_CREATOR = address(0x2222);
    address internal constant TREASURY = address(0x3333);
    bytes32 internal constant SALT = keccak256("salt");

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    RevenueIngressFactory internal ingressFactory;
    MockRegentStakingRevenueRouter internal feeRouter;
    PermissionlessExistingTokenRevenueFactory internal factory;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        stakeToken = new MintableERC20Mock("Agent", "AGENT");
        stakeToken.mint(address(0x9999), 1000e18);
        subjectRegistry = new SubjectRegistry(address(this), OWNER, address(0x600D));
        ingressFactory = new RevenueIngressFactory(address(usdc), address(subjectRegistry), OWNER);
        feeRouter = new MockRegentStakingRevenueRouter(address(usdc), address(0x8888));
        factory = new PermissionlessExistingTokenRevenueFactory(
            OWNER, address(usdc), address(ingressFactory), subjectRegistry, feeRouter
        );
    }

    function testPermissionlessCreationIsDisabledBeforeEffects() external {
        vm.prank(CREATOR);
        vm.expectRevert("FACTORY_NOT_REGISTRAR");
        factory.createExistingTokenRevenueSubject(_config(TREASURY, SALT));

        bytes32 subjectId = keccak256(
            abi.encode(
                block.chainid, address(factory), address(stakeToken), TREASURY, CREATOR, SALT
            )
        );
        assertEq(factory.splitterOfSubject(subjectId), address(0));
        assertEq(subjectRegistry.subjectCountForStakeToken(address(stakeToken)), 0);
    }

    function testEveryCallerIsBlockedFromLegacyCreation() external {
        vm.prank(CREATOR);
        vm.expectRevert("FACTORY_NOT_REGISTRAR");
        factory.createExistingTokenRevenueSubject(_config(TREASURY, SALT));

        vm.prank(OTHER_CREATOR);
        vm.expectRevert("FACTORY_NOT_REGISTRAR");
        factory.createExistingTokenRevenueSubject(_config(address(0x4444), keccak256("second")));

        assertEq(subjectRegistry.subjectCountForStakeToken(address(stakeToken)), 0);
    }

    function testDisablementPrecedesBadInputValidation() external {
        IPermissionlessExistingTokenRevenueFactory.ExistingTokenRevenueConfig memory cfg =
            _config(address(0), SALT);

        vm.expectRevert("FACTORY_NOT_REGISTRAR");
        factory.createExistingTokenRevenueSubject(cfg);

        cfg = _config(TREASURY, SALT);
        cfg.stakeToken = address(0);
        vm.expectRevert("FACTORY_NOT_REGISTRAR");
        factory.createExistingTokenRevenueSubject(cfg);

        cfg.stakeToken = address(0xABCD);
        vm.expectRevert("FACTORY_NOT_REGISTRAR");
        factory.createExistingTokenRevenueSubject(cfg);
    }

    function testDisablementPrecedesMalformedTokenCall() external {
        IPermissionlessExistingTokenRevenueFactory.ExistingTokenRevenueConfig memory cfg =
            _config(TREASURY, SALT);
        cfg.stakeToken = address(new NoTotalSupplyToken());

        vm.expectRevert("FACTORY_NOT_REGISTRAR");
        factory.createExistingTokenRevenueSubject(cfg);
    }

    function testDisablementPrecedesZeroSupplyCheck() external {
        MintableERC20Mock emptyToken = new MintableERC20Mock("Empty", "EMPTY");
        IPermissionlessExistingTokenRevenueFactory.ExistingTokenRevenueConfig memory cfg =
            _config(TREASURY, SALT);
        cfg.stakeToken = address(emptyToken);

        vm.expectRevert("FACTORY_NOT_REGISTRAR");
        factory.createExistingTokenRevenueSubject(cfg);
    }

    function _config(address treasury, bytes32 salt)
        internal
        view
        returns (IPermissionlessExistingTokenRevenueFactory.ExistingTokenRevenueConfig memory)
    {
        return IPermissionlessExistingTokenRevenueFactory.ExistingTokenRevenueConfig({
            stakeToken: address(stakeToken),
            treasury: treasury,
            stakerPoolBps: 2500,
            label: "Existing token",
            salt: salt
        });
    }
}
