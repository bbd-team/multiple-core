// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./interfaces/IMulBank.sol";
import "./base/Permission.sol";

contract MulWork is Permission {
	using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint constant public MAG = 1e18;

	IERC721 public GPToken;
	IMulBank public bank;

	struct Worker {
		bool created;
		uint totalProfit;
		uint createTime;
		uint lastWorkTime;
		uint workerId;
	}

	mapping (address => Worker) public workers;
	mapping (address => mapping(address => int128)) public profits;

	mapping (address => uint) public baseQuota;

	uint public cntOfWorker;
	uint public basePercent = MAG;

	event AccountCreated(address indexed user, uint tokenId);
	event SetBaseQuota(address indexed token, uint amount);
	event Settle(address indexed user, address token, int128 profit);

	constructor(IERC721 _gpToken, IMulBank _bank) {
		require(address(_gpToken) != address(0), "INVALID_ADDRESS");
		require(address(_bank) != address(0), "INVALID_ADDRESS");
		GPToken = _gpToken;
		bank = _bank;
	}

	function onERC721Received(address, address, uint, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

	function createAccount(uint tokenId) external {
		require(!workers[msg.sender].created, "ALREADY CREATED");
		GPToken.safeTransferFrom(msg.sender, address(this), tokenId);
		cntOfWorker++;
		workers[msg.sender] = Worker({
			created: true,
			totalProfit: 0,
			createTime: block.number,
			lastWorkTime: 0,
			workerId: cntOfWorker
			});
		emit AccountCreated(msg.sender, tokenId);
	}

	function setBaseQuota(address[] memory tokens, uint[] memory amounts) external onlyOwner {
		for(uint i = 0;i < tokens.length;i++) {
			baseQuota[tokens[i]] = amounts[i];
			emit SetBaseQuota(tokens[i], amounts[i]);
		}
	}

	function upgrade(address newContract, uint[] memory tokenIds) external onlyOwner {
		uint cnt = tokenIds.length;
		for(uint i = 0;i < cnt;i++) {
			GPToken.safeTransferFrom(address(this), newContract, tokenIds[i]);
		}
	}

	function getRemainQuota(address user, address token) external view returns(uint) {
		Worker memory worker = workers[user];
		if(!worker.created) {
			return 0;
		}
		
		int128 profit = profits[user][token];
		int128 quota = int128(baseQuota[token]) + profit > 0 ? int128(baseQuota[token]) + profit: 0;
		return uint(quota);
	}


	function settle(address user, address token, int128 profit) external onlyPermission {
		profits[user][token] = profits[user][token] + profit;
		emit Settle(user, token, profit);
	}
}

