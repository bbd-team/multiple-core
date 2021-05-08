// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./MulERC20.sol";
import "./interfaces/ICompoundCERC20.sol";
import "./interfaces/ICompoundCETH.sol";
import "./MulERC20.sol";

contract MulBank is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    struct PoolInfo {
        ERC20 supplyToken;
        MulERC20 shareToken;
        uint256 totalBorrow;
        uint256 loss;
        uint256 totalDeposit;
    }

    // struct CompoundInfo {
    //     bool eth;
    //     address cToken;
    //     uint256 deposit;
    // }

    address public strategy;

    // mapping(address => CompoundInfo) public compoundInfo;
    mapping(address => bool) public hasInit;
    mapping(address => uint256) public pidOfPool;
    mapping(address => PoolInfo) public poolInfo;

    uint256 public cntOfPool;

    event PoolInitialized(address indexed supplyToken, address shareToken);
    event CompoundInitialized(address indexed token, address cToken);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event SetStrategy(address indexed strategy);

    modifier onlyStrategy() {
        require(msg.sender == strategy, "FORBIDDEN");
        _;
    }

    function setStrategy(address _strategy) external onlyOwner {
        strategy = _strategy;
        emit SetStrategy(_strategy);
    }

    // function initCompound(
    //     address _token,
    //     address _cToken,
    //     bool eth
    // ) external onlyOwner {
    //     require(hasInit[address(_token)], "!POOL");
    //     CompoundInfo storage compound = compoundInfo[_token];
    //     if (compound.cToken != address(0)) {
    //         _withdrawCompound(_token, compound.deposit);
    //     }
    //     compound.eth = eth;
    //     compound.cToken = _cToken;
    //     compound.deposit = 0;
    //     if (eth) {
    //         _depositCompound(_token, address(this).balance);
    //     } else {
    //         ERC20(_token).safeApprove(_cToken, uint256(-1));
    //         _depositCompound(_token, ERC20(_token).balanceOf(address(this)));
    //     }
    //     emit CompoundInitialized(_token, _cToken);
    // }

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
        PoolInfo memory pool =
            PoolInfo(supplyToken, MulERC20(shareToken), 0, 0, 0);
        poolInfo[address(supplyToken)] = pool;
        emit PoolInitialized(address(supplyToken), shareToken);
        cntOfPool++;
    }

    // function _depositCompound(address token, uint256 amount) internal {
    //     amount = amount.div(1e8).mul(1e8);
    //     CompoundInfo storage compound = compoundInfo[token];
    //     if (amount > 0 && compound.cToken != address(0)) {
    //         if (compound.eth) {
    //             ICompoundCETH(compound.cToken).mint{
    //                 value: amount,
    //                 gas: 250000
    //             }();
    //         } else {
    //             ICompoundCERC20(compound.cToken).mint(amount);
    //         }
    //         compound.deposit = compound.deposit.add(amount);
    //     }
    // }

    // function _withdrawCompound(address token, uint256 amount) internal {
    //     CompoundInfo storage compound = compoundInfo[token];
    //     if (compound.cToken != address(0)) {
    //         if (amount > compound.deposit) {
    //             amount = compound.deposit;
    //         }
    //         if (amount > 0) {
    //             if (compound.eth) {
    //                 ICompoundCETH(compound.cToken).redeemUnderlying(amount);
    //             } else {
    //                 ICompoundCERC20(compound.cToken).redeemUnderlying(amount);
    //             }
    //             compound.deposit = compound.deposit.sub(amount);
    //         }
    //     }
    // }

    // function harvestCompound(address token) external {
    //     CompoundInfo storage compound = compoundInfo[token];
    //     if (compound.cToken != address(0)) {
    //         uint256 income = 0;
    //         uint256 beforeTokenBalance = 0;
    //         uint256 afterTokenBalance = 0;
    //         if (compound.eth) {
    //             uint256 cTokenBalance =
    //                 ICompoundCETH(compound.cToken).balanceOf(address(this));
    //             beforeTokenBalance = address(this).balance;
    //             ICompoundCETH(compound.cToken).redeem(cTokenBalance);
    //             afterTokenBalance = address(this).balance;
    //         } else {
    //             uint256 cTokenBalance =
    //                 ICompoundCERC20(compound.cToken).balanceOf(address(this));
    //             beforeTokenBalance = ERC20(token).balanceOf(address(this));
    //             ICompoundCERC20(compound.cToken).redeem(cTokenBalance);
    //             afterTokenBalance = ERC20(token).balanceOf(address(this));
    //         }
    //         income = afterTokenBalance.sub(beforeTokenBalance).sub(
    //             compound.deposit,
    //             "NO INCOME"
    //         );
    //         require(income > 0, "!HARVEST");
    //         uint256 _deposit = compound.deposit;
    //         compound.deposit = 0;
    //         _depositCompound(token, _deposit);
    //     }
    // }

    function deposit(address token, uint256 amount) external {
        require(amount > 0, "INVALID DEPOSIT AMOUNT");

        PoolInfo storage pool = poolInfo[token];

        pool.shareToken.mint(msg.sender, amount);
        pool.supplyToken.safeTransferFrom(msg.sender, address(this), amount);
        pool.totalDeposit = pool.totalDeposit.add(amount);

        // _depositCompound(token, amount);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(address token, uint256 amount) external {
        PoolInfo storage pool = poolInfo[token];

        require(
            pool.shareToken.balanceOf(msg.sender) >= amount,
            "INVALID WITHDRAW AMOUNT"
        );

        // _withdrawCompound(token, amount);

        require(
            pool.supplyToken.balanceOf(address(this)) >= amount,
            "NO ENOUGH AMOUNT"
        );

        pool.shareToken.burn(msg.sender, amount);
        pool.supplyToken.safeTransfer(msg.sender, amount);
        pool.totalDeposit = pool.totalDeposit.sub(amount);

        emit Withdraw(msg.sender, amount);
    }

    function borrow(
        address token,
        uint256 amount,
        address to
    ) external onlyStrategy {
        PoolInfo storage pool = poolInfo[token];

        require(
            pool.supplyToken.balanceOf(address(this)) >= amount,
            "INVALID BORROW AMOUNT"
        );
        pool.supplyToken.safeTransfer(to, amount);
        pool.totalBorrow = pool.totalBorrow.add(amount);
    }

    function increaseLoss(address token, uint loss) external onlyStrategy {
    	poolInfo[token].loss = poolInfo[token].loss.add(loss);
    }

    function decreaseLoss(address token, uint loss) external {
    	PoolInfo storage pool = poolInfo[token];
    	require(pool.loss >= loss, "TOO MUCH AMOUNT");
    	pool.supplyToken.safeTransferFrom(
            msg.sender,
            address(this),
            loss
        );
    }

    function repay(
        address token,
        uint256 amount
    ) external onlyStrategy {
        PoolInfo storage pool = poolInfo[token];

        require(pool.totalBorrow >= amount, "INVALID REPAY AMOUNT");
        pool.supplyToken.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        pool.totalBorrow = pool.totalBorrow.sub(amount);
    }
}
