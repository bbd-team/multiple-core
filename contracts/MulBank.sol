// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./MulERC20.sol";
import "./interfaces/IWETH9.sol";
import "./base/Permission.sol";

contract MulBank is Permission {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    struct PoolInfo {
        ERC20 supplyToken;
        MulERC20 shareToken;
        uint256 totalBorrow;
        uint256 loss;
        uint256 totalDeposit;
    }

    mapping(address => uint) public remains;
    mapping(address => bool) public hasInit;
    mapping(address => PoolInfo) public poolInfo;

    uint256 public cntOfPool;
    address WETH9;

    event PoolInitialized(address indexed supplyToken, address shareToken);
    event CompoundInitialized(address indexed token, address cToken);
    event Deposit(address indexed user, uint256 amount, uint256 share);
    event Withdraw(address indexed user, uint256 amount, uint256 share);

    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    constructor(address _WETH9) {
        WETH9 = _WETH9;
    }

    function addReamins(address[] memory tokens, uint[] memory amounts) external onlyOwner {
        require(tokens.length > 0 && tokens.length == amounts.length, "INVALID PARAMS");
        for(uint i = 0;i < tokens.length;i++) {
            remains[tokens[i]] = remains[tokens[i]].add(amounts[i]);
        }
    }

    function initPool(ERC20 supplyToken) external onlyOwner {
        require(!hasInit[address(supplyToken)], "ALREADY INIT");
        hasInit[address(supplyToken)] = true;

        string memory symbol =
            string(abi.encodePacked("mul", supplyToken.symbol()));
        string memory name =
            string(abi.encodePacked("MUL", supplyToken.symbol()));

        bytes memory bytecode =
            abi.encodePacked(
                type(MulERC20).creationCode,
                abi.encode(name, symbol)
            );
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, supplyToken));
        address shareToken = Create2.deploy(0, salt, bytecode);
        MulERC20(shareToken).setDecimal(supplyToken.decimals());
        PoolInfo memory pool =
            PoolInfo(supplyToken, MulERC20(shareToken), 0, 0, 0);
        poolInfo[address(supplyToken)] = pool;
        emit PoolInitialized(address(supplyToken), shareToken);
        cntOfPool++;
    }

    function getTotalShare(address token) public view returns(uint) {
        PoolInfo memory pool = poolInfo[token];
        return pool.totalBorrow.add(ERC20(pool.supplyToken).balanceOf(address(this)));
    }

    function deposit(address token, uint256 amount) external payable {
        require(hasInit[address(token)], "NOT SUPPORT NOW");
        require(amount > 0, "INVALID DEPOSIT AMOUNT");

        PoolInfo storage pool = poolInfo[token];
        
        uint totalShare = getTotalShare(token);
        uint share = totalShare == 0 ? amount: amount.mul(pool.shareToken.totalSupply()).div(totalShare);

        require(amount <= remains[token], "OVERLIMIT");
        remains[token] = remains[token].sub(amount);

        pool.shareToken.mint(msg.sender, share);
        if(token == WETH9) {
            require(msg.value == amount, "INVALID ETH VALUE");
            IWETH9(WETH9).deposit{value: msg.value};
        } else {
            pool.supplyToken.safeTransferFrom(msg.sender, address(this), amount);
        }
        
        pool.totalDeposit = pool.totalDeposit.add(amount);

        emit Deposit(msg.sender, amount, share);
    }

    function withdraw(address token, uint256 share) external {
        PoolInfo storage pool = poolInfo[token];

        require(pool.shareToken.balanceOf(msg.sender) >= share, "INVALID WITHDRAW SHARE");
        uint totalShare = getTotalShare(address(pool.supplyToken));

        uint amount = share.mul(totalShare).div(pool.shareToken.totalSupply());
        require(pool.supplyToken.balanceOf(address(this)) >= amount, "NO ENOUGH AMOUNT");

        pool.shareToken.burn(msg.sender, share);
        pool.supplyToken.safeTransfer(msg.sender, amount);
        pool.totalDeposit = pool.totalDeposit.sub(amount);

        emit Withdraw(msg.sender, amount, share);
    }

    function borrow(
        address token,
        uint256 amount,
        address to
    ) external onlyPermission {
        PoolInfo storage pool = poolInfo[token];

        require(
            pool.supplyToken.balanceOf(address(this)) >= amount,
            "INVALID BORROW AMOUNT"
        );
        pool.supplyToken.safeTransfer(to, amount);
        pool.totalBorrow = pool.totalBorrow.add(amount);
    }

    function notifyRepay(
        address token,
        uint256 amount
    ) external onlyPermission {
        PoolInfo storage pool = poolInfo[token];
        require(pool.totalBorrow >= amount, "INVALID REPAY AMOUNT");
        pool.totalBorrow = pool.totalBorrow.sub(amount);
    }
}
