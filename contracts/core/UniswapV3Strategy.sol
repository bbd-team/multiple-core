// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "./interfaces/IMulWork.sol";
import "./interfaces/IMulBank.sol";

contract UniswapV3Strategy is Ownable {
	struct Position {
		address token0;
		address token1;
		uint    fee;
		uint    liquidity;
		uint    debt0;
		uint    debt1;
		uint    createTime;
	}

	IUniswapV3Factory public factory;

	IMulBank public bank;
	IMulWork public work;
	uint176 public _nextId = 0;
	
	mapping (uint => Position) positions;

	constructor(IUniswapV3Factory _factory) {
	    factory = _factory;
	}

	struct MintCallbackData {
        address token0;
        address token1;
        uint24 fee;
        address payer;
    }
    
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        uint amount0Desired;
        uint amount1Desired;
        int24 tickLower;
        int24 tickUpper;
    }

    modifier onlyEOA() {
        require(msg.sender == tx.origin, 'not eoa');
        _;
      }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        // CallbackValidation.verifyCallback(factory, decoded.poolKey);
        require(msg.sender == IUniswapV3Factory(factory).getPool(decoded.token0, decoded.token1, decoded.fee), "INVALID CALLBACK");

        if (amount0Owed > 0) pay(decoded.token0, decoded.payer, amount0Owed, msg.sender);
        if (amount1Owed > 0) pay(decoded.token1, decoded.payer, amount1Owed, msg.sender);
    }

    function pay(address token, address payer, uint amount, address to) internal {
    	require(work.getRemainQuota(msg.sender, token) >= amount, "NO ENOUGH QUOTA");
    	bank.borrow(token, amount, to);
    	work.addInvestAmount(token, payer, amount);
    } 

	function invest(MintParams calldata params) onlyEOA external returns (uint amount0, uint amount1){
		address pool = factory.getPool(params.token0, params.token1, params.fee);

		(uint160 sqrtPriceX96, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();
		require(params.tickLower < currentTick && currentTick < params.tickUpper, "INVALID TICK SELECT");

		uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(params.tickLower),
                TickMath.getSqrtRatioAtTick(params.tickUpper),
                params.amount0Desired,
                params.amount1Desired
            );

		(amount0, amount1) = IUniswapV3Pool(pool).mint(
            address(this),
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({token0: params.token0, token1: params.token1, fee: params.fee, payer: msg.sender}))
        );
        
        uint positionId = ++_nextId;
        positions[positionId] = Position({
            token0: params.token0,
            token1: params.token1,
            fee:    params.fee,
            liquidity: liquidity,
            debt0: amount0,
            debt1: amount1,
            createTime: block.number
        });
	}

// 	function divest() {

// 	}
}