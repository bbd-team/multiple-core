// Root file: contracts/core/interfaces/IPayCallback.sol

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

interface IPayCallback {
	function pay(
        address token,
        address payer,
        uint256 value
    ) external ;
}