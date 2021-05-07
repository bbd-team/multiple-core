// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

interface ICompoundCETH {
    function mint() external payable;

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
}
