// // SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.0;
// pragma abicoder v2;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// import './interfaces/IMulWork.sol';


// interface IWETH {
//     function deposit() external payable;
//     function withdraw(uint) external;
// }

// contract MulInvest is Ownable, ReentrancyGuard {
//     using SafeMath for uint;
//     using SafeERC20 for IERC20;
    
// 	IWETH public WETH;
// 	IMulBank public bank;
// 	IMulWork public work;

// 	// uint constant public MAG = 1e18;
// 	// uint constant public MAX_LEVERAGE = 100 * 1e18;
// 	// uint constant public DISTRIBUTE_PERCENT = 1e17;
// 	// uint24 constant public UNI_FEE = 3000;
// 	// int24 constant public UNI_SPACING = 60;
// 	// uint internal constant Q96 = 0x1000000000000000000000000;
// 	// uint internal constant interestRate = 2e17;
// 	// uint constant public year = 86400 * 365;
	
// 	uint176 public _nextId = 0;
	
// 	constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {
	    
// 	}

// 	function initialize (IWETH _WETH, IMulBank _bank, IMulWork _work) external onlyOwner{
// 		WETH = _WETH;
// 		bank = _bank;
// 		work = _work;
// 	}

// 	modifier onlyEOA() {
//         require(msg.sender == tx.origin, 'not eoa');
//         _;
//       }

//     function sqrt(uint x) internal pure returns (uint){
//        uint n = x / 2;
//        uint lstX = 0;
//        while (n != lstX){
//            lstX = n;
//            n = (n + x/n) / 2; 
//        }
//        return uint(n);
//    }

//     // function _getTick(address token0, address token1, uint amount0, uint amount1) internal view returns (TickParams memory tickParams) {
//     // 	if (token0 > token1) {
//     // 		(amount0, amount1) = (amount1, amount0);
//     // 		(token0, token1) = (token1, token0);
//     // 	} 
//     // 	uint160 sqrtPrice = uint160(Babylonian.sqrt(amount1.mul(1e12).div(amount0)).mul(Q96).div(1e6));
//     // 	int24 tick = TickMath.getTickAtSqrtRatio(sqrtPrice);
//     // 	int24 tickLower = tick / UNI_SPACING * UNI_SPACING;
//     // 	int24 tickUpper = tickLower + UNI_SPACING;

//     // 	tickParams = TickParams(token0, token1, IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), tickLower, tickUpper);
//     // }

//     // function getTick(uint amount0, uint amount1) public view returns(int24){
//     // 	uint160 sqrtPrice = uint160(100 * Q96);
//     // 	int24 tick = TickMath.getTickAtSqrtRatio(sqrtPrice);
//     // 	int24 tickLower = tick;
//     // 	return tickLower;
//     // }

// 	function investBoth(address token0, address token1, uint amount0, uint amount1, address strategy, bytes calldata data) external onlyEOA { 
// 		uint remain0 = work.getRemainQuota(msg.sender, token0);
// 		uint remain1 = work.getRemainQuota(msg.sender, token1);

// 		require(remain0 >= amount0 && remain1 >= amount1, "NOT ENOUGH QUOTA");


// 	}
	
// 	// function close(uint mulTokenId) external {
// 	//     require(_isApprovedOrOwner(msg.sender, mulTokenId), "INVALID TOKEN OWNER");
// 	//     _close(mulTokenId);
// 	// }
	
// 	// function _close(uint mulTokenId) internal {
// 	//     Position memory position = positions[mulTokenId];
// 	//     uniswapPosManager.decreaseLiquidity(position.uniTokenId, position.liquidity, 0, 0, block.timestamp);
	    
// 	//     uint pid = bank.getPidOfPool(address(position.inputToken));
	    
// 	//     uint balanceBefore0 = position.inputToken.balanceOf(address(this));
// 	//     uint balanceBefore1 = position.buyToken.balanceOf(address(this));
// 	//     uniswapPosManager.collect(position.uniTokenId, address(this), uint128(-1), uint128(-1));
// 	//     uint amount0 = position.inputToken.balanceOf(address(this)).sub(balanceBefore0);
// 	//     uint amount1 = position.inputToken.balanceOf(address(this)).sub(balanceBefore1);
	    
// 	//     if(amount1 > 0) {
// 	//         amount0 = amount0.add(_swapToken(address(position.buyToken), address(position.inputToken), amount1, 0));
// 	//     }
	    
// 	//     require(amount0 >= position.owed, "CAN NOT CLOSE NOW");
	    
// 	//     uint interest = position.owed.mul(position.interestRate).mul(block.timestamp.sub(position.lastInterestTime)).div(MAG).div(year);
// 	//     if(amount0 > interest.add(position.input).add(position.owed)) {
// 	//         uint profit = amount0.sub(interest.add(position.input).add(position.owed));
// 	//         uint poolProfit = interest.add(profit.mul(position.distributePercent).div(MAG));
// 	//         position.inputToken.safeApprove(address(bank), poolProfit.add(interest));
// 	//         bank.repay(pid, position.owed, poolProfit.add(interest));
// 	//     } else {
// 	//         interest = amount0.sub(position.owed);
// 	//         position.inputToken.safeApprove(address(bank), amount0);
// 	//         bank.repay(pid, position.owed, amount0.sub(position.owed));
// 	//     }
	    
// 	//     delete positions[mulTokenId];
// 	//     _burn(mulTokenId);
// 	// }

// 	// function _swapToken(address fromToken, address toToken, uint amountIn, uint amountOutMin) internal returns (uint amountOut){
// 	// 	IERC20(fromToken).safeApprove(address(uniswapV3Router), amountIn);
// 	// 	amountOut = uniswapV3Router.exactInputSingle(ISwapRouter.ExactInputSingleParams({
// 	// 	    tokenIn: fromToken,
// 	// 	    tokenOut: toToken, 
// 	// 	    fee:      UNI_FEE,
// 	// 	    recipient: address(this),
// 	// 	    deadline:  block.timestamp,
// 	// 	    amountIn:  amountIn,
// 	// 	    amountOutMinimum: amountOutMin,
// 	// 	    sqrtPriceLimitX96: 0
// 	// 	}));
// 	// }
// }