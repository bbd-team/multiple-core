// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "./interfaces/IMulWork.sol";
import "./interfaces/IMulBank.sol";

contract UniswapV3Strategy is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    struct Tick {
        int24   tickLower;
        int24   tickUpper;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 liquidity;
        uint fee0;
        uint fee1;
    }

    struct Position {
        bool    close;
        address token0;
        address token1;
        uint24  fee;
        uint    debt0;
        uint    debt1;
        address operator;
        uint exit0;
        uint exit1;
        Tick tick;
    }

    IUniswapV3Factory public factory;

    IMulBank public bank;
    IMulWork public work;
    uint176 public _nextId = 0;
    address public rewardAddr;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
    
    Position[] public positions;

    event Invest(address indexed user, uint positionId, address token0, address token1, uint invest0, uint invest1, uint128 liquidity);
    event Divest(address indexed user, uint positionId, uint amount0, uint amount1);
    event Collect(address indexed user, uint positionId, uint fee0, uint fee1);
    event Add(address indexed user, uint positionId, uint amount0, uint amount1, uint128 liquidity);
    event Switching(address indexed user, uint positionId, uint invest0, uint invest1, uint128 liquidity);

    constructor(IUniswapV3Factory _factory, IMulWork _work, IMulBank _bank, address _rewardAddr) {
        factory = _factory;
        work = _work;
        bank = _bank;
        rewardAddr = _rewardAddr;
    }

    struct MintCallbackData {
        address token0;
        address token1;
        uint24 fee;
        address payer;
    }

    // struct SwapCallbackData {
    //     address tokenIn;
    //     address tokenOut;
    //     uint24 fee;
    //     uint positionId;
    // }
    
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
      
    modifier onlyOperator(uint positionId) {
        Position memory pos = positions[positionId];
        require(msg.sender == pos.operator && !pos.close && pos.tick.liquidity > 0, "FORBIDDEN");
        _;
    }

    function toInt128(int256 y) internal pure returns (int128 z) {
        require((z = int128(y)) == y);
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        require(msg.sender == factory.getPool(decoded.token0, decoded.token1, decoded.fee), "INVALID CALLBACK");

        if (amount0Owed > 0) borrow(decoded.token0, decoded.payer, amount0Owed, msg.sender);
        if (amount1Owed > 0) borrow(decoded.token1, decoded.payer, amount1Owed, msg.sender);
    }

    function borrow(address token, address payer, uint amount, address to) internal {
        require(work.getRemainQuota(payer, token) >= amount, "NO ENOUGH QUOTA");
        bank.borrow(token, amount, to);
        work.addInvestAmount(payer, token, amount);
    } 

    function _settle(uint positionId, uint amount0, uint amount1, bool hedge) internal {
        Position storage pos = positions[positionId];
        if(hedge) {
            if(amount0 > pos.debt0) {
                IERC20(pos.token0).transfer(msg.sender, amount0.sub(pos.debt0));
                IERC20(pos.token1).transferFrom(msg.sender, address(this), pos.debt1.sub(amount1));
            } 
            
            if(amount1 > pos.debt1) {
                IERC20(pos.token0).transferFrom(msg.sender, address(this), pos.debt0.sub(amount0));
                IERC20(pos.token1).transfer(msg.sender, amount1.sub(pos.debt1));
            }
        }
        
        uint balance0 = IERC20(pos.token0).balanceOf(address(this));
        uint balance1 = IERC20(pos.token1).balanceOf(address(this));
        
        int128 profit0 = balance0 > pos.debt0 ? int128(balance0.sub(pos.debt0)): -int128(pos.debt0.sub(balance0));
        int128 profit1 = balance1 > pos.debt1 ? int128(balance1.sub(pos.debt1)): -int128(pos.debt1.sub(balance1));
        
        work.settle(pos.operator, pos.token0, pos.debt0, profit0);
        work.settle(pos.operator, pos.token1, pos.debt1, profit1);

        IERC20(pos.token0).transfer(address(bank), balance0);
        IERC20(pos.token1).transfer(address(bank), balance1);
        bank.notifyRepay(pos.token0, pos.debt0);
        bank.notifyRepay(pos.token1, pos.debt1);
    }

    function _mint(MintParams memory params) internal 
    returns (IUniswapV3Pool pool, uint amount0, uint amount1, uint128 liquidity) {
        pool = IUniswapV3Pool(factory.getPool(params.token0, params.token1, params.fee));
        require(params.token0 == pool.token0() && params.token1 == pool.token1(), "ORDER");
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(params.tickLower),
                TickMath.getSqrtRatioAtTick(params.tickUpper),
                params.amount0Desired,
                params.amount1Desired
            );
        require(liquidity > 0, "INVALID LIQUIDITY");
        (amount0, amount1) = pool.mint(
            address(this),
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({token0: params.token0, token1: params.token1, fee: params.fee, payer: msg.sender}))
        );
    }
    
    function invest(MintParams calldata params) external returns (uint amount0, uint amount1, uint128 liquidity) {
        IUniswapV3Pool pool;
        (pool, amount0, amount1, liquidity) = _mint(params);
        bytes32 positionKey = PositionKey.compute(address(this), params.tickLower, params.tickUpper);
        (, uint feeGrowthInside0LastX128, uint feeGrowthInside1LastX128, , ) = pool.positions(positionKey);
        
        Tick memory tick = Tick({
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            fee0: 0,
            fee1: 0
        });
        positions.push(Position({
            close:  false,
            token0: params.token0,
            token1: params.token1,
            fee:    params.fee,
            debt0: amount0,
            debt1: amount1,
            operator: msg.sender,
            exit0: 0,
            exit1: 0,
            tick: tick
        }));

        emit Invest(msg.sender, _nextId, params.token0, params.token1, amount0, amount1, liquidity);
        _nextId++;
    }

    function divest(uint positionId, bool hedge) external onlyOperator(positionId)  returns(uint amount0, uint amount1){
        Position memory pos = positions[positionId];
        collect(positionId);
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(pos.token0, pos.token1, pos.fee));
        (amount0, amount1) = pool.burn(pos.tick.tickLower, pos.tick.tickUpper, pos.tick.liquidity);
        
        pool.collect(address(this), pos.tick.tickLower, pos.tick.tickUpper, uint128(amount0), uint128(amount1));
        _settle(positionId, amount0, amount1, hedge);
        pos.tick.liquidity = 0;
        pos.exit0 = hedge ? pos.debt0: amount0;
        pos.exit1 = hedge ? pos.debt1: amount1;
        pos.close = true;

        emit Divest(msg.sender, positionId, amount0, amount1);
    }

    function add(uint positionId, uint amount0Desired, uint amount1Desired) external returns(uint amount0, uint amount1, uint128 liquidity) {
        Position storage pos = positions[positionId];
        require(msg.sender == pos.operator && !pos.close && pos.tick.liquidity > 0, "FORBIDDEN");
        
        IUniswapV3Pool pool;
        (pool, amount0, amount1, liquidity) = _mint(MintParams({
            token0: pos.token0,
            token1: pos.token1,
            fee: pos.fee,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            tickLower: pos.tick.tickLower,
            tickUpper: pos.tick.tickUpper
        }));
        
        pos.tick.liquidity = pos.tick.liquidity + liquidity;
        pos.debt0 = pos.debt0.add(amount0);
        pos.debt1 = pos.debt1.add(amount1);
        collect(positionId);
        
        emit Add(msg.sender, positionId, amount0, amount1, liquidity);
    }
    
    function switching(uint positionId, int24 tickLower, int24 tickUpper, uint amount0Desired, uint amount1Desired, bool hedge)
    external onlyOperator(positionId) returns(uint amount0, uint amount1, uint128 liquidity) {
        Position storage pos = positions[positionId];
        collect(positionId);
        
        require(tickLower != pos.tick.tickLower || tickUpper != pos.tick.tickUpper, "NO CHANGE");
        collect(positionId);
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(pos.token0, pos.token1, pos.fee));
        (amount0, amount1) = pool.burn(pos.tick.tickLower, pos.tick.tickUpper, pos.tick.liquidity);
        pool.collect(address(this), pos.tick.tickLower, pos.tick.tickUpper, uint128(amount0), uint128(amount1));
        _settle(positionId, amount0, amount1, hedge);
        
        (pool, amount0, amount1, liquidity) = _mint(MintParams({
            token0: pos.token0,
            token1: pos.token1,
            fee: pos.fee,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            tickLower: tickLower,
            tickUpper: tickUpper
        }));
        
        pos.tick.tickLower = tickLower;
        pos.tick.tickUpper = tickUpper;
        pos.debt0 = amount0;
        pos.debt1 = amount1;
        pos.tick.liquidity = liquidity;
        
        emit Switching(msg.sender, positionId, amount0, amount1, liquidity);
    }

    function collect(uint positionId) internal returns(uint128 fee0, uint128 fee1) {
        Position storage pos = positions[positionId];
        Tick storage tick = pos.tick;
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(pos.token0, pos.token1, pos.fee));
        pool.burn(tick.tickLower, tick.tickUpper, 0);

        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) =
                pool.positions(PositionKey.compute(address(this), tick.tickLower, tick.tickUpper));
        fee0 = uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - tick.feeGrowthInside0LastX128,
                    tick.liquidity,
                    Q128
                )
            );
        fee1 = uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - tick.feeGrowthInside1LastX128,
                    tick.liquidity,
                    Q128
                )
            );

        pool.collect(address(this), tick.tickLower, tick.tickUpper, fee0, fee1);
        tick.fee0 = tick.fee0.add(fee0);
        tick.fee1 = tick.fee1.add(fee1);

        distributeFee(pos.token0);
        distributeFee(pos.token1);

        tick.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        tick.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;

        emit Collect(pos.operator, positionId, fee0, fee1);
    }

    function distributeFee(address token) internal {
        uint balance = IERC20(token).balanceOf(address(this));
        if(balance > 0) {
            uint toBank = balance.mul(9).div(10);
            IERC20(token).transfer(address(bank), toBank);
            IERC20(token).transfer(msg.sender, balance.sub(toBank));
        }
    }
}