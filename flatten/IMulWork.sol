// Root file: contracts/core/interfaces/IMulWork.sol

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

interface IMulWork {
	// get worker remain quota
	function getRemainQuota(address user, address token) external view returns(uint);

	function addInvestAmount(address user, address token, uint amount) external;

	// function settle(address user, address token, uint amount, int128 profit) external; 
	function settle(address user, address token, int128 profit) external; 
}