// Root file: contracts/core/interfaces/IMulFactory.sol

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.6.6;

interface IMulFactory {
	function router() external returns (address);
	function getPool(address token) external returns (address);
}