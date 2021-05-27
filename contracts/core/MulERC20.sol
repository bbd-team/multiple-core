// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MulERC20 is ERC20, Ownable {
	constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

	function mint(address _to, uint256 _amount) external onlyOwner {
	   _mint(_to, _amount);
	}

	function setDecimal(uint8 decimal) external onlyOwner {
		_setupDecimals(decimal);
	}

	function burn(address _to, uint256 _amount) external onlyOwner {
	    _burn(_to, _amount);
	}
}