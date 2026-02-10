// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./Pool.sol";

/**
 * @title PoolFactory
 * @author Jss
 * @notice 池子工厂合约
 */
contract PoolFactory {
    struct CreateArgs {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
    }

    function createPool(CreateArgs calldata args) external returns (address) {
    }
}