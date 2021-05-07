// Root file: contracts/core/interfaces/IUniswapV3Strategy.sol

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

pragma solidity ^0.7.0;

interface IUniswapV3Strategy {
	struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

	function getRemainQuota(address user, address token) external view returns(uint);
}