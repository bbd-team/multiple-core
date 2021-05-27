// Root file: contracts/core/interfaces/IMulBank.sol

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

interface IMulBank {
	// get TotalShare
	function getTotalShare(address token) external view returns(uint);

	// repay to pool
    function notifyRepay(
        address token,
        uint256 amount
    ) external;
    
    // borrow from bank
	function borrow(address token, uint256 amount, address to) external;
}