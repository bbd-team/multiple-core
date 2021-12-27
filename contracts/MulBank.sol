// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IWETH9.sol";
import "./base/Permission.sol";

pragma abicoder v2;

contract MulBank is Permission {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    enum Period { Close, Settle, Withdraw, Disable } 
    Period public period = Period.Close;

    struct PoolInfo {
        bool init;
        bool enable;
        uint minDeposit;
        uint index;
    }

    mapping(address => PoolInfo) public poolInfo;
    mapping(address => bool) public whiteList;
    mapping(address => mapping(address => uint)) public userBalance;

    uint256 public cntOfPool;
    address public WETH9;
    address[] public pools;
    
    event PoolInitialized(address indexed supplyToken, uint minAmount);
    event UpdateMinDeposit(address pool, uint minAmount);
    event SwitchPoolDeposit(address pool, bool enable);
    event SwitchWhiteList(address user, bool enable);
    event SetUserBalance(address user, address token, uint amount);
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event UpdatePeriod(Period period);

    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    constructor(address _WETH9) {
        WETH9 = _WETH9;
    }

    modifier checkDeposit(address token, uint amount) {
        require(period == Period.Close, "CANNOT DEPOSIT NOW");
        require(poolInfo[token].init && poolInfo[token].enable, "NOT SUPPORT NOW");
        require(amount > 0 && amount >= poolInfo[token].minDeposit, "INVALID DEPOSIT AMOUNT");
        require(whiteList[msg.sender], "NOT WHITE LIST");
        _;
    }

    modifier checkWithdraw(address token, uint amount) {
        require(period == Period.Withdraw, "CANNOT DEPOSIT NOW");
        require(userBalance[msg.sender][token] >= amount);
        require(IERC20(token).balanceOf(address(this)) >= amount, "NOT ENOUGH AMOUNT");
        _;
    }

    function initPoolList(address[] memory supplyTokens, uint[] memory minAmounts) external onlyOwner {
        require(supplyTokens.length == minAmounts.length, "INVALID FORMAT");
        uint length = supplyTokens.length;
        for(uint i = 0;i < length;i++) {
            require(!poolInfo[supplyTokens[i]].init, "ALREADY INIT");
            poolInfo[supplyTokens[i]] = PoolInfo({
                init: true,
                enable: true,
                minDeposit: minAmounts[i],
                index: cntOfPool + i
                });
            emit PoolInitialized(supplyTokens[i], minAmounts[i]);
            pools.push(supplyTokens[i]);
        }
        
        cntOfPool += length;
    }

    function updateMinDeposit(address[] memory supplyTokens, uint[] memory amounts) external onlyOwner {
        require(supplyTokens.length == amounts.length, "INVALID FORMAT");
        for(uint i = 0;i < supplyTokens.length;i++) {
            require(poolInfo[supplyTokens[i]].init, "NOT INIT");
            poolInfo[supplyTokens[i]].minDeposit = amounts[i];
            emit UpdateMinDeposit(supplyTokens[i], amounts[i]);
        }
    }

    function switchPool(address[] memory supplyTokens, bool[] memory enable) external onlyOwner {
        require(supplyTokens.length == enable.length, "INVALID FORMAT");
        for(uint i = 0;i < supplyTokens.length;i++) {
            require(poolInfo[supplyTokens[i]].init, "NOT INIT");
            poolInfo[supplyTokens[i]].enable = enable[i];
            emit SwitchPoolDeposit(supplyTokens[i], enable[i]);
        }
    }

    function switchWhiteList(address[] memory users, bool[] memory enable) external onlyOwner {
        require(users.length == enable.length, "INVALID FORMAT");
        for(uint i = 0;i < users.length;i++) {
            whiteList[users[i]] = enable[i];
            emit SwitchWhiteList(users[i], enable[i]);
        }
    }

    function isClosePeriod() public view returns(bool) {
        return period == Period.Close;
    }

    function deposit(address token, uint256 amount) external checkDeposit(token, amount) payable {
        if(token == WETH9) {
            require(msg.value == amount, "INVALID ETH VALUE");
            IWETH9(WETH9).deposit{value: msg.value}();
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external checkWithdraw(token, amount) {
        userBalance[msg.sender][token] = userBalance[msg.sender][token].sub(amount);
        if(token == WETH9) {
            IWETH9(WETH9).withdraw(amount);
            msg.sender.transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Withdraw(msg.sender, token, amount);
    }

    function setUserBalance(address[] memory users, address[][] memory tokens, uint[][] memory amounts) external onlyOwner {
        uint userCnt = users.length;
        uint[] memory total = new uint[](pools.length);
        for(uint i = 0;i < userCnt;i++) {
            address[] memory userTokens = tokens[i];
            uint[] memory userAmounts = amounts[i];
            require(userTokens.length == userAmounts.length, "INVALID FORMAT");
            for(uint j = 0;j < userTokens.length;j++) {
                userBalance[users[i]][userTokens[i]] = userAmounts[i];
                uint index = poolInfo[userTokens[i]].index;
                total[index] = total[index].add(userAmounts[i]);

                emit SetUserBalance(users[i], userTokens[i], userAmounts[i]); 
            }
        }

        for(uint i = 0;i < pools.length;i++) {
            uint index = poolInfo[pools[i]].index;
            require(total[index] <= IERC20(pools[i]).balanceOf(address(this)), "NOT ENOUGH MONEY");
        }
    }
    
    function setPeriod(Period _period) external onlyOwner {
        period = _period;
        emit UpdatePeriod(_period);
    }

    function pay(
        address token,
        uint256 amount,
        address to
    ) external onlyPermission {
        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "NOT ENOUGH MONEY"
        );
        IERC20(token).safeTransfer(to, amount);
    }
}