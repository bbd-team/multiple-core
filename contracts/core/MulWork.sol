// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IMulBank.sol";
import "./base/Permission.sol";

contract MulWork is Permission {
	using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint constant public MAG = 1e18;

	IERC20 public GPToken;
	IERC20 public MulToken;
	IMulBank public bank;

	address public strategy;

	struct Worker {
		bool created;
		uint totalProfit;
		uint createTime;
		uint lastWorkTime;
		uint workerId;
	}

	mapping (address => Worker) public workers;
	mapping (address => mapping(address => uint)) public invested;
	mapping (address => mapping(address => int128)) public profits;

	mapping (address => uint) totalProfits;
	uint public cntOfWorker;
	uint public basePercent = MAG;

	event AccountCreated(address indexed user);
	event UpdateBasePercent(uint oldBasePercent, uint newBasePercent);
	event SetStrategy(address indexed strategy);
	event Invest(address indexed user, address token, uint amount);
	event Settle(address indexed user, address token, uint amount, int128 profit);

	constructor(IERC20 _gpToken, IERC20 _mulToken, IMulBank _bank) {
		GPToken = _gpToken;
		MulToken = _mulToken;
		bank = _bank;
	}

	modifier onlyStrategy() {
        require(msg.sender == strategy, 'FORBIDDEN');
        _;
      } 

    function setBasePercent(uint _newBasePercent) onlyOwner external {
    	require(_newBasePercent >= 0 && _newBasePercent <= MAG, "INVALID BASE PERCENT");
    	emit UpdateBasePercent(basePercent, _newBasePercent);
    	basePercent = _newBasePercent;
    }

    function setStrategy(address _strategy) onlyOwner external {
    	strategy = _strategy;
		emit SetStrategy(strategy);
    }

	function createAccount() external {
		require(!workers[msg.sender].created, "ALREADY CREATED");
		// GPToken.safeTransferFrom(msg.sender, address(this), 1);
		cntOfWorker++;
		workers[msg.sender] = Worker({
			created: true,
			totalProfit: 0,
			createTime: block.number,
			lastWorkTime: 0,
			workerId: cntOfWorker
			});
		emit AccountCreated(msg.sender);
	}

	function getRemainQuota(address user, address token) external view returns(uint) {
		Worker memory worker = workers[user];
		if(!worker.created) {
			return 0;
		}

		uint quota = bank.getTotalShare(token).div(cntOfWorker).mul(basePercent).div(MAG);
		int128 profit = profits[user][token];
		if(profit > 0) {
			uint totalProfit = totalProfits[token];
			quota = quota.add(uint(profit).mul(MAG.sub(basePercent)).div(totalProfit).div(MAG));
		} else {
			uint subQuota = uint(-profit);
			quota = quota > subQuota ? quota.sub(subQuota): 0;
		}

		uint investedAmount = invested[user][token];
		return quota > investedAmount ? quota.sub(investedAmount): 0;
	}

	function addInvestAmount(address user, address token, uint amount) external onlyPermission {
		invested[user][token] = invested[user][token].add(amount);
		emit Invest(user, token, amount);
	}

	function settle(address user, address token, uint amount, int128 profit) external onlyPermission {
		invested[user][token] = invested[user][token].sub(amount);
		
		int128 oldProfit = profits[user][token];
		uint totalProfit = totalProfits[token];
		if(oldProfit > 0) 
			totalProfit = totalProfit.sub(uint(oldProfit));
		int128 newProfit = oldProfit + profit;
		if(newProfit > 0) 
			totalProfit = totalProfit.add(uint(newProfit));

		totalProfits[token] = totalProfit;
		profits[user][token] = profits[user][token] + profit;
		emit Settle(user, token, amount, profit);
	}
}

