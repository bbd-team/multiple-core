// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

interface ICompoundCERC20 {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

     function balanceOf(address account) external view returns (uint256);
}
