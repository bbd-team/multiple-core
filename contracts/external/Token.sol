// SPDX-License-Identifier: MIT
/**
 *Submitted for verification at Etherscan.io on 2019-05-09
 */

pragma solidity >=0.6.5 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// 测试生成ERC20的合约

// ----------------------------------------------------------------------------
// ERC20 Token, with the addition of symbol, name and decimals and a
// fixed supply
// ----------------------------------------------------------------------------
contract Token is ERC20 {
    constructor(
        string memory _symbol,
        string memory _name,
        uint8 _decimals,
        uint256 _total
    )  ERC20(_name, _symbol) {
        _setupDecimals(_decimals);

        if (_total > 0) {
            _mint(msg.sender, _total * 10**uint256(decimals()));
        }
    }
}
