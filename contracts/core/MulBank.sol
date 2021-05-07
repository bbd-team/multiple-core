// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./MulERC20.sol";

contract MulBank is Ownable {
	using SafeMath for uint;
    using SafeERC20 for ERC20;

    struct PoolInfo {
    	ERC20 supplyToken;
    	MulERC20 shareToken;
    	uint totalBorrow;
    	uint debt;
    	uint totalDeposit;
    }

    address public strategy;

    mapping (address => bool) public hasInit;
    mapping (address => uint) public pidOfPool;
    mapping (address => PoolInfo) public poolInfo;

    uint public cntOfPool;

    event PoolInitialized(address indexed supplyToken, address shareToken);
    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);

    modifier onlyStrategy() {
        require(msg.sender == strategy, 'FORBIDDEN');
        _;
      } 

    function setStrategy(address _strategy) onlyOwner external {
    	strategy = _strategy;
    }

    function initPool(ERC20 supplyToken) external onlyOwner {
	    require(!hasInit[address(supplyToken)], "ALREADY INIT");
	    hasInit[address(supplyToken)] = true;

	    string memory symbol = string(abi.encodePacked("mul", supplyToken.symbol()));
    	string memory name = string(abi.encodePacked("MUL", supplyToken.symbol()));

	    bytes memory bytecode = abi.encodePacked(type(MulERC20).creationCode, abi.encode(name, symbol));
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, supplyToken));
        address shareToken = Create2.deploy(0, salt, bytecode);
	    PoolInfo memory pool = PoolInfo(
	    	supplyToken,
	    	MulERC20(shareToken),
	    	0,
	    	0,
	    	0
	    );
	    poolInfo[address(supplyToken)] = pool;
	    emit PoolInitialized(address(supplyToken), shareToken);
	    cntOfPool++;
	  }

	function getPidOfPool(address token) public view returns(uint) {
		require(hasInit[token], "NOT SUPPORT NOW");
		return pidOfPool[token];
	}

	function deposit(address token, uint amount) external {
		require(amount > 0, "INVALID DEPOSIT AMOUNT");

		PoolInfo storage pool = poolInfo[token];

		pool.shareToken.mint(msg.sender, amount);
		pool.supplyToken.safeTransferFrom(msg.sender, address(this), amount);
		pool.totalDeposit = pool.totalDeposit.add(amount);
        emit Deposit(msg.sender, amount);
	}

	function withdraw(address token, uint amount) external {
		PoolInfo storage pool = poolInfo[token];

		require(pool.shareToken.balanceOf(msg.sender) >= amount, "INVALID WITHDRAW AMOUNT");
        require(pool.supplyToken.balanceOf(address(this)) >= amount, "NO ENOUGH AMOUNT");

        pool.shareToken.burn(msg.sender, amount);
        pool.supplyToken.safeTransfer(msg.sender, amount);
        pool.totalDeposit = pool.totalDeposit.sub(amount);

        emit Withdraw(msg.sender, amount);
	}

	function borrow(address token, uint amount, address to) onlyStrategy external {
		PoolInfo storage pool = poolInfo[token];

		require(pool.supplyToken.balanceOf(address(this)) >= amount, "INVALID BORROW AMOUNT");
		pool.supplyToken.safeTransfer(to, amount);
		pool.totalBorrow = pool.totalBorrow.add(amount);
	}

	function repay(address token, uint amount, uint interest) onlyStrategy external {
		PoolInfo storage pool = poolInfo[token];

		require(pool.totalBorrow >= amount, "INVALID REPAY AMOUNT");
		pool.supplyToken.safeTransferFrom(msg.sender, address(this), amount.add(interest));
		pool.totalBorrow = pool.totalBorrow.sub(amount);
	}
	
	function distribute(address token, uint amount) external {
	    PoolInfo storage pool = poolInfo[token];
		pool.supplyToken.safeTransferFrom(msg.sender, address(this), amount);
	}
}