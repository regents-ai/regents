// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeployUERC20FactoryScript} from "script/DeployUERC20Factory.s.sol";
import {UERC20Factory} from "@uniswap/uerc20-factory/src/factories/UERC20Factory.sol";
import {UERC20Metadata} from "@uniswap/uerc20-factory/src/libraries/UERC20MetadataLibrary.sol";

interface IUERC20LaunchToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function creator() external view returns (address);
    function graffiti() external view returns (bytes32);
    function tokenURI() external view returns (string memory);
}

contract DeployUERC20FactoryScriptTest is Test {
    address internal constant RECIPIENT = address(0xCAFE);
    uint256 internal constant TOTAL_SUPPLY = 100_000_000_000e18;

    DeployUERC20FactoryScript internal script;

    function setUp() external {
        script = new DeployUERC20FactoryScript();
    }

    function testDeployCreatesUerc20Factory() external {
        UERC20Factory factory = script.deploy();

        assertTrue(address(factory).code.length > 0);
    }

    function testFactoryCreatesUerc20TokenWithMetadataAndGraffiti() external {
        UERC20Factory factory = script.deploy();
        bytes32 graffiti = keccak256(abi.encode(RECIPIENT));
        bytes memory metadataData = abi.encode(
            UERC20Metadata({
                description: "Regent rehearsal token",
                website: "https://autolaunch.sh",
                image: "ipfs://regent-token-image"
            })
        );

        address predicted =
            factory.getUERC20Address("Regent Agent Token", "RAGENT", 18, address(this), graffiti);
        address tokenAddress = factory.createToken(
            "Regent Agent Token", "RAGENT", 18, TOTAL_SUPPLY, RECIPIENT, metadataData, graffiti
        );
        IUERC20LaunchToken token = IUERC20LaunchToken(tokenAddress);

        assertEq(tokenAddress, predicted);
        assertEq(token.name(), "Regent Agent Token");
        assertEq(token.symbol(), "RAGENT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(RECIPIENT), TOTAL_SUPPLY);
        assertEq(token.creator(), address(this));
        assertEq(token.graffiti(), graffiti);
        assertTrue(bytes(token.tokenURI()).length > 0);
    }

    function testFactoryRejectsZeroRecipient() external {
        UERC20Factory factory = script.deploy();
        UERC20Metadata memory metadata = UERC20Metadata({description: "", website: "", image: ""});

        vm.expectRevert();
        factory.createToken(
            "Regent Agent Token", "RAGENT", 18, TOTAL_SUPPLY, address(0), abi.encode(metadata), 0
        );
    }

    function testFactoryRejectsZeroSupply() external {
        UERC20Factory factory = script.deploy();
        UERC20Metadata memory metadata = UERC20Metadata({description: "", website: "", image: ""});

        vm.expectRevert();
        factory.createToken(
            "Regent Agent Token", "RAGENT", 18, 0, RECIPIENT, abi.encode(metadata), 0
        );
    }
}
