// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

interface IUniswapV3WorkCenter {
	// get worker remain quota
	function getRemainQuota(address user, address token) external view returns(uint);

	function getSwapQuota(address worker, address poolAddress) external view returns(int256 amount0, int256 amount1);

	function addInvestAmount(address user, address token, uint amount) external;

	function claim(address worker) external returns (address[] memory tokens, uint[] memory commision);

	function commisionPercent(address) external returns(uint);

	function devPercent() external returns(uint);

	function settle(address worker, address poolAddress, address token0, address token1, int128 profit0, int128 profit1) external; 
}