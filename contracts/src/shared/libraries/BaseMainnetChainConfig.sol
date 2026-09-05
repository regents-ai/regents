// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library BaseMainnetChainConfig {
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;

    address internal constant REGENT = 0x6f89bcA4eA5931EdFCB09786267b251DeE752b07;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant UNISWAP_V4_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant UNISWAP_V4_POSITION_MANAGER =
        0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address internal constant UNISWAP_UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function requireBaseMainnet() internal view {
        require(block.chainid == BASE_MAINNET_CHAIN_ID, "BASE_MAINNET_ONLY");
    }

    function requireRegent(address token) internal view {
        requireBaseMainnet();
        require(token == REGENT, "REGENT_NOT_CANONICAL");
    }

    function requireUsdc(address token) internal view {
        requireBaseMainnet();
        require(token == USDC, "USDC_NOT_CANONICAL");
    }

    function requirePoolManager(address poolManager) internal view {
        requireBaseMainnet();
        require(poolManager == UNISWAP_V4_POOL_MANAGER, "POOL_MANAGER_NOT_CANONICAL");
    }

    function requirePositionManager(address positionManager) internal view {
        requireBaseMainnet();
        require(positionManager == UNISWAP_V4_POSITION_MANAGER, "POSITION_MANAGER_NOT_CANONICAL");
    }

    function requireUniversalRouter(address universalRouter) internal view {
        requireBaseMainnet();
        require(universalRouter == UNISWAP_UNIVERSAL_ROUTER, "UNIVERSAL_ROUTER_NOT_CANONICAL");
    }

    function requirePermit2(address permit2) internal view {
        requireBaseMainnet();
        require(permit2 == PERMIT2, "PERMIT2_NOT_CANONICAL");
    }
}
