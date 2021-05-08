// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IMulBank.sol";

contract MulWork is Ownable {
	using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint constant public BasePower = 10000;

	IERC20 public GPToken;
	IERC20 public MulToken;
	IMulBank public bank;

	address public strategy;

	struct Worker {
		bool created;
		uint totalProfit;
		uint createTime;
		uint power;
		uint lastWorkTime;
		uint workerId;
	}

	mapping (address => Worker) public workers;
	mapping (address => mapping(address => uint)) invested;

	uint public totalPower;
	uint public cntOfWorker;

	event AccountCreated(address indexed user);

	constructor(IERC20 _gpToken, IERC20 _mulToken, IMulBank _bank) {
		GPToken = _gpToken;
		MulToken = _mulToken;
		bank = _bank;
	}

	modifier onlyStrategy() {
        require(msg.sender == strategy, 'FORBIDDEN');
        _;
      } 

    function setStrategy(address _strategy) onlyOwner external {
    	strategy = _strategy;
    }

	function createAccount() external {
		require(!workers[msg.sender].created, "ALREADY CREATED");
		// GPToken.safeTransferFrom(msg.sender, address(this), 1);
		cntOfWorker++;
		workers[msg.sender] = Worker({
			created: true,
			totalProfit: 0,
			createTime: block.number,
			power: BasePower,
			lastWorkTime: 0,
			workerId: cntOfWorker
			});
		totalPower = totalPower.add(BasePower);
		emit AccountCreated(msg.sender);
	}

	function getRemainQuota(address user, address token) external view returns(uint) {
		(,,,,uint total) = bank.poolInfo(token);
		Worker memory worker = workers[user];
		uint quota = total.mul(worker.power).div(totalPower);
		uint investedAmount = invested[msg.sender][token];
		return quota > investedAmount ? quota.sub(investedAmount): 0;
	}

	function addInvestAmount(address user, address token, uint amount) external onlyStrategy {
		invested[msg.sender][token] = invested[msg.sender][token].add(amount);
	} 
}

