// Root file: contracts/core/MulWork.sol

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

contract MulWork is Ownable, ERC721 {
	using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint constant public BasePower = 10000;

	address public GPToken;
	address public MulToken;

	address public strategy;

	struct Worker {
		bool created;
		uint totalProfit;
		uint createTime;
		uint workCnt;
		uint power;
		uint lastWorkTime;
		uint workerId;
		mapping (address => uint) invested;
	}

	mapping (uint => Worker) public workers;

	uint public totalPower;
	uint public cntOfWorker;

	event AccountCreated(address indexed user);

	constructor(IERC20 _gpToken, IERC20 _mulToken, IMulBank bank) {
		GPToken = _gpToken;
		MulToken = _mulToken;
	}

	modifier onlyStrategy() {
        require(msg.sender == exchange, 'FORBIDDEN');
        _;
      } 

    function setStrategy(address _strategy) onlyOwner external {
    	strategy = _strategy;
    }

	function createAccount() external {
		GPToken.safeTransferFrom(msg.sender, address(0), 1);
		cntOfWorker++;
		workers[msg.sender] = Worker({
			user: msg.sender,
			created: true,
			createTime: block.number,
			workCnt: 0,
			power: BasePower,
			workerId: cntOfWorker,
			lastWorkTime: 0
			});
		totalPower = totalPower.add(BasePower);
		emit AccountCreated(msg.sender);
	}

	function getRemainQuota(address user, address token) external view returns(uint) {
		(,,,,uint total) = bank.poolInfo(token);
		Worker memory worker = workers[user];
		uint quota = total.mul(worker.power).div(totalPower);
		uint invested = worker.invested[token];
		return quota > invested ? quota.sub(invested): 0;
	}

	function addInvestAmount(address user, address token, uint amount) external onlyStrategy {
		
	} 
}

