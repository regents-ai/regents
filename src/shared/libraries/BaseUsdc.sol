// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library BaseUsdc {
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;

    address internal constant BASE_MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function canonicalUsdc(uint256 chainId) internal pure returns (address) {
        if (chainId == BASE_MAINNET_CHAIN_ID) return BASE_MAINNET_USDC;
        revert("BASE_CHAIN_ONLY");
    }

    function requireCanonical(address usdc) internal view {
        require(usdc == canonicalUsdc(block.chainid), "USDC_NOT_CANONICAL");
    }
}
