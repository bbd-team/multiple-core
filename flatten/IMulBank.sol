// Root file: contracts/core/interfaces/IMulBank.sol

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

interface IMulBank {
	// get pool info by pid
	function poolInfo(address token) view external returns (address, address, uint, uint, uint, uint);

	// get pid of pool
	function getPidOfPool(address token) external returns(uint);

	// repay to pool
    function repay(address token, uint amount, uint debt) external;
    
    // borrow from bank
	function borrow(address token, uint256 amount, address to) external;
}