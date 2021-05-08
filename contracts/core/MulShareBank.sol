// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./MulERC20.sol";
import "./interfaces/ICompoundCERC20.sol";
import "./interfaces/ICompoundCETH.sol";
import "./MulERC20.sol";

contract MulShareBank is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    struct PoolInfo {
        ERC20 supplyToken;
        uint256 totalDeposit;
    }

    address public strategy;

    mapping(address => bool) public hasInit;
    mapping(address => uint256) public pidOfPool;
    mapping(address => PoolInfo) public poolInfo;

    uint256 public cntOfPool;

    event PoolInitialized(address indexed supplyToken);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

  
    function initPool(ERC20 supplyToken) external onlyOwner {
        require(!hasInit[address(supplyToken)], "ALREADY INIT");
        hasInit[address(supplyToken)] = true;
        PoolInfo memory pool =PoolInfo(supplyToken, 0);
        poolInfo[address(supplyToken)] = pool;
        emit PoolInitialized(address(supplyToken));
        cntOfPool++;
    }

    function getPidOfPool(address token) public view returns (uint256) {
        require(hasInit[token], "NOT SUPPORT NOW");
        return pidOfPool[token];
    }

    function deposit(address token, uint256 amount) external {
        require(amount > 0, "INVALID DEPOSIT AMOUNT");
        PoolInfo storage pool = poolInfo[token];
        pool.supplyToken.safeTransferFrom(msg.sender, address(this), amount);
        pool.totalDeposit = pool.totalDeposit.add(amount);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(address token, uint256 amount) external {
        PoolInfo storage pool = poolInfo[token];
        require(
            pool.supplyToken.balanceOf(address(this)) >= amount,
            "NO ENOUGH AMOUNT"
        );
        pool.supplyToken.safeTransfer(msg.sender, amount);
        pool.totalDeposit = pool.totalDeposit.sub(amount);
        emit Withdraw(msg.sender, amount);
    }

}
