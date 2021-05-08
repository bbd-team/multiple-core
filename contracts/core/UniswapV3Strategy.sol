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
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

	struct Position {
        bool    close;
		address token0;
		address token1;
		uint24  fee;
		uint128 liquidity;
		uint    debt0;
		uint    debt1;
        int24   tickLower;
        int24   tickUpper;
		uint    createTime;
        address operator;
	}

	IUniswapV3Factory public factory;

	IMulBank public bank;
	IMulWork public work;
	uint176 public _nextId = 0;
    address public reward;
	
	mapping (uint => Position) positions;

	constructor(IUniswapV3Factory _factory, IMulWork _work, IMulBank _bank, address _reward) {
	    factory = _factory;
        work = _work;
        bank = _bank;
        reward = _reward;
	}

	struct MintCallbackData {
        address token0;
        address token1;
        uint24 fee;
        address payer;
    }

    struct SwapCallbackData {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint positionId;
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
        require(msg.sender == factory.getPool(decoded.token0, decoded.token1, decoded.fee), "INVALID CALLBACK");

        if (amount0Owed > 0) borrow(decoded.token0, decoded.payer, amount0Owed, msg.sender);
        if (amount1Owed > 0) borrow(decoded.token1, decoded.payer, amount1Owed, msg.sender);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));

        require(msg.sender == factory.getPool(decoded.tokenIn, decoded.tokenOut, decoded.fee), "INVALID CALLBACK");
        uint amountToPay = amount0Delta > 0 ? uint256(amount0Delta): uint256(amount1Delta);

        IERC20(decoded.tokenIn).safeTransfer(msg.sender, amountToPay);
        _close(decoded.positionId);
    }

    function borrow(address token, address payer, uint amount, address to) internal {
    	require(work.getRemainQuota(payer, token) >= amount, "NO ENOUGH QUOTA");
    	bank.borrow(token, amount, to);
    	work.addInvestAmount(token, payer, amount);
    } 

    function _close(uint positionId) internal {
        // Position storage pos = positions[positionId];
        // uint balance0 = IERC20(pos.token0).balanceOf(address(this));
        // uint balance1 = IERC20(pos.token1).balanceOf(address(this));

        // uint profit0;
        // if()
    }

    function _repay(address token, uint amount, uint profit) internal {
        if(profit > amount) {
            bank.repay(token, amount, 0);
        }
    }

    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2**255);
        z = int256(y);
    }
    
	function invest(MintParams calldata params) onlyEOA external returns (uint amount0, uint amount1){
		address pool = factory.getPool(params.token0, params.token1, params.fee);
        require(params.token0 == IUniswapV3Pool(pool).token0() && params.token1 == IUniswapV3Pool(pool).token1(), "ORDER");

		(uint160 sqrtPriceX96, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();
		require(params.tickLower < currentTick && currentTick < params.tickUpper, "INVALID TICK SELECT");

		uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(params.tickLower),
                TickMath.getSqrtRatioAtTick(params.tickUpper),
                params.amount0Desired,
                params.amount1Desired
            );

        require(liquidity > 0, "INVALID LIQUIDITY");
		(amount0, amount1) = IUniswapV3Pool(pool).mint(
            address(this),
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({token0: params.token0, token1: params.token1, fee: params.fee, payer: msg.sender}))
        );
        
        positions[++_nextId] = Position({
            close:  false,
            token0: params.token0,
            token1: params.token1,
            fee:    params.fee,
            liquidity: liquidity,
            debt0: amount0,
            debt1: amount1,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            createTime: block.number,
            operator: msg.sender
        });
	}

	function takeProfit(uint positionId) external {
        Position memory pos = positions[positionId];
        require(msg.sender == pos.operator && !pos.close, "FORBIDDEN");

        address pool = factory.getPool(pos.token0, pos.token1, pos.fee);
        IUniswapV3Pool(pool).burn(pos.tickLower, pos.tickUpper, pos.liquidity);
        
        (uint128 amount0, uint128 amount1) = IUniswapV3Pool(pool).collect(address(this), pos.tickLower, pos.tickUpper, uint128(-1), uint128(-1));

        require(amount0 > pos.debt0 || amount1 > pos.debt1, "NO PROFIT NOW");

        if(amount0 < pos.debt0) {
            IUniswapV3Pool(pool).swap(
                address(this),
                false,
                toInt256(amount0 - pos.debt0),
                0, 
                abi.encode(SwapCallbackData({tokenIn: pos.token1, tokenOut: pos.token0, fee: pos.fee, positionId: positionId}))
            );
        } 

        if(amount1 < pos.debt1){
            IUniswapV3Pool(pool).swap(
                address(this),
                true,
                toInt256(amount1 - pos.debt1),
                0, 
                abi.encode(SwapCallbackData({tokenIn: pos.token0, tokenOut: pos.token1, fee: pos.fee, positionId: positionId}))
            );
        }
	}
}