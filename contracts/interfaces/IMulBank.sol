// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

interface IMulBank {
    // borrow from bank
	function pay(address token, uint256 amount, address to) external;

	function WETH9() external view returns(address);

	function isClosePeriod() external view returns(bool);

	function payCommision(address token, uint256 amount, address to) external;
}