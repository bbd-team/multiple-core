// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./interfaces/IMulBank.sol";
import "./base/Permission.sol";

pragma abicoder v2;

contract UniswapV3WorkCenter is Permission, IERC721Receiver {
	using SafeMath for uint;
    using SafeERC20 for IERC20;

	IERC721 public GPToken;

	struct Info {
		int128 unbalance0;
		int128 unbalance1;
	}

	struct Worker {
		bool created;
		uint workerId;
	}

	struct Record {
		address[] list;
		mapping(address => bool) used;
	}


	mapping (address => bool) public commonPools;
	mapping (address => mapping(address => bool)) public whitelist;
	mapping (uint => mapping(address => Info)) public poolInfo;
	mapping (uint => mapping (address => mapping(address => Info))) public userInfo;
	mapping (address => Worker) public workers;
	mapping (address => mapping(address => uint)) public quotas;
	mapping (address => bool) public canSwap;
	mapping (address => bool) public canClaim;
	mapping (address => uint) public commisionPercent;

	mapping (uint => mapping(address => mapping(address => int128))) public profits;

	uint public devPercent = 1000;

	// pools gp invest
	mapping (uint => mapping (address => Record)) private poolRecord;
	// tokens gp invest
	mapping (uint => mapping (address => Record)) private tokenRecord;

	uint public cntOfWorker;
	uint public period;

	event AccountCreated(address indexed user, uint workerId);
	event SetQuota(address worker, address[] tokens, uint[] amounts);
	event Settle(address worker, address poolAddress, address token0, address token1, int128 profit0, int128 profit1);
	event SwitchPool(address[] pools, bool[] enable);
	event SwitchSwap(address[] workers, bool[] enable);
	event SwitchClaim(address[] workers, bool[] enable);
	event SetWhiteList(address worker, address[] pools, bool[] enable);
	event UpdateGPPercent(address worker, uint oldPercent, uint newPercent);
	event UpdateDevPercent(uint oldPercent, uint newPercent);

	constructor(IERC721 _gpToken) {
		require(address(_gpToken) != address(0), "INVALID_ADDRESS");
		GPToken = _gpToken;
	}

	function onERC721Received(address from, address, uint workerId, bytes calldata) override external returns (bytes4) {
		require(!workers[from].created, "ALREADY CREATED");
		require(msg.sender == address(GPToken), "INVALID GP TOKEN");
		cntOfWorker++;
		workers[from] = Worker({
			created: true,
			workerId: cntOfWorker
			});
		commisionPercent[from] = 2000;
		canSwap[from] = true;
		canClaim[from] = true;
		emit AccountCreated(from, workerId);
        return this.onERC721Received.selector;
    }

    function updateDevPercent(uint newPercent) external onlyOwner {
    	require(newPercent >= 0 && newPercent < 10000, "INVALID PARAMS");
    	emit UpdateDevPercent(devPercent, newPercent);
    	devPercent = newPercent;
    }

	function setQuota(address worker, address[] memory tokens, uint[] memory amounts) external onlyOwner {
		require(tokens.length == amounts.length, "INVALID FORMAT");
		for(uint i = 0;i < tokens.length;i++) {
			quotas[worker][tokens[i]] = amounts[i];
		}
		emit SetQuota(worker, tokens, amounts);
	}

	function getRemainQuota(address worker, address token) external view returns(uint) {
		if(!workers[worker].created) {
			return 0;
		}
		
		int128 profit = profits[period][worker][token];
		int128 quota = int128(quotas[worker][token]);
		quota = quota + profit > 0 ? quota + profit: 0;
		return uint(quota);
	}

	function switchSwap(address[] memory users, bool[] memory enable) external onlyOwner {
		for(uint i = 0;i < users.length;i++) {
			canSwap[users[i]] = enable[i];
		}
		emit SwitchSwap(users, enable);
	}

	function switchClaim(address[] memory users, bool[] memory enable) external onlyOwner {
		for(uint i = 0;i < users.length;i++) {
			canClaim[users[i]] = enable[i];
		}
		emit SwitchClaim(users, enable);
	}

	function switchPool(address[] memory pools, bool[] memory enable) external onlyOwner {
		require(pools.length == enable.length, "INVALID FORMAT");
		for(uint i = 0;i < pools.length;i++) {
			commonPools[pools[i]] = enable[i];
		}
		emit SwitchPool(pools, enable);
	}

	function setWhiteList(address worker, address[] memory pools, bool[] memory enable) external onlyOwner  {
		require(pools.length == enable.length, "INVALID FORMAT");
		for(uint i = 0;i < pools.length;i++) {
			whitelist[worker][pools[i]] = enable[i];
		}
		emit SetWhiteList(worker, pools, enable);
	}

	function getSwapQuota(address worker, address poolAddress) external view returns(int256 amount0, int256 amount1) {
		if(!isEnable(worker, poolAddress)) {
			return (0, 0);
		}

		if(!canSwap[worker]) {
			return (0, 0);
		}
		Info memory info = userInfo[period][poolAddress][worker];
		return (int256(info.unbalance0), int256(info.unbalance1));
	}

	function updateCommisionPercent(address worker, uint newPercent) external onlyOwner {
		require(newPercent <= 5000, "INVALID PERCENT");
		emit UpdateGPPercent(worker, commisionPercent[worker], newPercent);
		commisionPercent[worker] = newPercent;
	}

	function isEnable(address worker, address poolAddress) private view returns (bool) {
		return commonPools[poolAddress] == true || whitelist[worker][poolAddress] == true;
	}

	function setPeriod(uint _period) external onlyOwner {
		period = _period;
	}

	function settle(address worker, address poolAddress, address token0, address token1, int128 profit0, int128 profit1) external onlyPermission {
		require(isEnable(worker, poolAddress), "NOT PERMIT");

		if(worker != address(0)) {
			profits[period][worker][token0] = profits[period][worker][token0] + profit0;
			profits[period][worker][token1] = profits[period][worker][token1] + profit1;
			userInfo[period][poolAddress][worker].unbalance0 += profit0;
			userInfo[period][poolAddress][worker].unbalance1 += profit1;

			if(!tokenRecord[period][worker].used[token0]) {
				tokenRecord[period][worker].used[token0] = true;
				tokenRecord[period][worker].list.push(token0);
			}

			if(!tokenRecord[period][worker].used[token1]) {
				tokenRecord[period][worker].used[token1] = true;
				tokenRecord[period][worker].list.push(token1);
			}

			if(!poolRecord[period][worker].used[poolAddress]) {
				poolRecord[period][worker].used[poolAddress] = true;
				poolRecord[period][worker].list.push(poolAddress);
			}
		}
		
		poolInfo[period][poolAddress].unbalance0 += profit0;
		poolInfo[period][poolAddress].unbalance1 += profit1;

		emit Settle(worker, poolAddress, token0, token1, profit0, profit1);
	}

	function claim(address worker) external onlyPermission returns (address[] memory tokens, uint[] memory commision) {
		require(workers[worker].created, "NOT GP");

		uint length = tokenRecord[period][worker].list.length;
		tokens = new address[](length);
		commision = new uint[](length);
		for(uint idx = 0;idx < length;idx++) {
			address token = tokenRecord[period][worker].list[idx];
			require(profits[period][worker][token] >= 0, "PROFIT MUST GREATER THAN ZERO");

			tokens[idx] = token;
			commision[idx] = uint(profits[period][worker][token]);
			profits[period][worker][token] = 0;
		}

		length = poolRecord[period][worker].list.length;
		uint gpPercent = commisionPercent[worker];
		require(gpPercent + devPercent <= 10000, "UNKNOWN ERROR");

		for(uint idx = 0;idx < length;idx++) {
			address poolAddress = poolRecord[period][worker].list[idx];

			int128 unbalance0 = userInfo[period][poolAddress][worker].unbalance0 * (int128)(gpPercent + devPercent) / 10000;
			int128 unbalance1 = userInfo[period][poolAddress][worker].unbalance1 * (int128)(gpPercent + devPercent) / 10000;

			poolInfo[period][poolAddress].unbalance0 -= unbalance0;
			poolInfo[period][poolAddress].unbalance1 -= unbalance1;

			userInfo[period][poolAddress][worker].unbalance0 = 0;
			userInfo[period][poolAddress][worker].unbalance1 = 0;
		}
	}
}

