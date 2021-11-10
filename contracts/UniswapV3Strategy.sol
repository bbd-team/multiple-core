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

contract UniswapV3Strategy is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    struct Tick {
        int24   tickLower;
        int24   tickUpper;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 liquidity;
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

    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
    
    Position[] public positions;

    event Invest(address indexed user, uint positionId, address pool, address token0, address token1, uint invest0, uint invest1, uint128 liquidity);
    event Divest(address indexed user, uint positionId, uint amount0, uint amount1);
    event Add(address indexed user, uint positionId, uint amount0, uint amount1, uint128 liquidity);
    event Switching(address indexed user, uint positionId, uint exit0, uint exit1, uint invest0, uint invest1, uint128 liquidity);

    constructor(IUniswapV3Factory _factory, IMulWork _work, IMulBank _bank, address _rewardAddr) {
        require(address(_factory) != address(0), "INVALID_ADDRESS");
        require(address(_work) != address(0), "INVALID_ADDRESS");
        require(address(_bank) != address(0), "INVALID_ADDRESS");
        require(_rewardAddr != address(0), "INVALID_ADDRESS");
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

    struct SwapCallbackData {
        address token0;
        address token1;
        uint24 fee;
        address payer;
        bool isGP;
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

    struct SwapParams {
        address token0;
        address token1;
        uint24 fee;
        int256 amountSpecified;
        int256 amountRequire;
        bool zeroOne;
    }
    
    struct SwitchParams {
        int24 tickLower;
        int24 tickUpper;
        uint amount0Desired;
        uint amount1Desired;
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
        require(msg.sender == factory.getPool(decoded.token0, decoded.token1, decoded.fee), "INVALID MINT CALLBACK");

        if (amount0Owed > 0) borrow(decoded.token0, decoded.payer, amount0Owed, msg.sender, true);
        if (amount1Owed > 0) borrow(decoded.token1, decoded.payer, amount1Owed, msg.sender, true);

        work.settle(decoded.payer, msg.sender, decoded.token0, decoded.token1, -int128(amount0Owed), -int128(amount1Owed));
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory decoded = abi.decode(_data, (SwapCallbackData));
        require(msg.sender == factory.getPool(decoded.token0, decoded.token1, decoded.fee), "INVALID SWAP CALLBACK");

        if(amount0Delta > 0) borrow(decoded.token0, decoded.payer, uint(amount0Delta), msg.sender, decoded.isGP);
        if(amount1Delta > 0) borrow(decoded.token1, decoded.payer, uint(amount1Delta), msg.sender, decoded.isGP);

        if(decoded.isGP) {
            work.settle(decoded.payer, msg.sender, decoded.token0, decoded.token1, -int128(amount0Delta), -int128(amount1Delta));
        } 
    }

    function borrow(address token, address payer, uint amount, address to, bool isGP) internal {
        require(isGP && work.getRemainQuota(payer, token) >= amount, "NO ENOUGH QUOTA");
        bank.borrow(token, amount, to);
    } 

    function _settle(uint positionId, address poolAddress, uint amount0, uint amount1) internal nonReentrant {
        Position storage pos = positions[positionId];
        
        uint balance0 = IERC20(pos.token0).balanceOf(address(this));
        uint balance1 = IERC20(pos.token1).balanceOf(address(this));

        work.settle(pos.operator, poolAddress, pos.token0, pos.token1, int128(balance0), int128(balance1));

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
            feeGrowthInside1LastX128: feeGrowthInside1LastX128
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

        emit Invest(msg.sender, _nextId, address(pool), params.token0, params.token1, amount0, amount1, liquidity);
        _nextId++;
    }

    function divest(uint positionId) external onlyOperator(positionId)  returns(uint amount0, uint amount1){
        Position storage pos = positions[positionId];
        collect(positionId);
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(pos.token0, pos.token1, pos.fee));
        (amount0, amount1) = pool.burn(pos.tick.tickLower, pos.tick.tickUpper, pos.tick.liquidity);
        
        pool.collect(address(this), pos.tick.tickLower, pos.tick.tickUpper, uint128(amount0), uint128(amount1));
        _settle(positionId, address(pool), amount0, amount1);
        pos.tick.liquidity = 0;
        pos.exit0 = amount0;
        pos.exit1 = amount1;
        pos.close = true;

        emit Divest(msg.sender, positionId, amount0, amount1);
    }

    function add(uint positionId, uint amount0Desired, uint amount1Desired) external onlyOperator(positionId) returns(uint amount0, uint amount1, uint128 liquidity) {
        Position storage pos = positions[positionId]; 
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

        collect(positionId);

        pos.tick.liquidity = pos.tick.liquidity + liquidity;
        pos.debt0 = pos.debt0.add(amount0);
        pos.debt1 = pos.debt1.add(amount1);
        
        
        emit Add(msg.sender, positionId, amount0, amount1, liquidity);
    }
    
    function switching(uint positionId, SwitchParams memory params)
    external onlyOperator(positionId) returns(uint amount0, uint amount1, uint128 liquidity, uint exit0, uint exit1) {
        Position storage pos = positions[positionId];
        Tick storage tick = pos.tick;
        collect(positionId);

        
        require(params.tickLower != tick.tickLower || params.tickUpper != tick.tickUpper, "NO CHANGE");
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(pos.token0, pos.token1, pos.fee));
        (exit0, exit1) = pool.burn(tick.tickLower, tick.tickUpper, tick.liquidity);
        pool.collect(address(this), tick.tickLower, tick.tickUpper, uint128(exit0), uint128(exit1));
        _settle(positionId, address(pool), exit0, exit1);

        (pool, amount0, amount1, liquidity) = _mint(MintParams({
            token0: pos.token0,
            token1: pos.token1,
            fee: pos.fee,
            amount0Desired: params.amount0Desired,
            amount1Desired: params.amount1Desired,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper
        }));
        
        tick.tickLower = params.tickLower;
        tick.tickUpper = params.tickUpper;
        pos.debt0 = amount0;
        pos.debt1 = amount1;
        tick.liquidity = liquidity;

        (, tick.feeGrowthInside0LastX128, tick.feeGrowthInside1LastX128, , ) =
                pool.positions(PositionKey.compute(address(this), tick.tickLower, tick.tickUpper));
        
        emit Switching(msg.sender, positionId, exit0, exit1, amount0, amount1, liquidity);
    }

    function collect(uint positionId) public nonReentrant onlyOperator(positionId) returns(uint128 fee0, uint128 fee1) {
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

        (fee0, fee1) = pool.collect(address(this), tick.tickLower, tick.tickUpper, fee0, fee1);

        tick.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        tick.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;

        work.settle(msg.sender, address(pool), pos.token0, pos.token1, int128(fee0), int128(fee1));
    }

    function swap(SwapParams memory params) external returns (int256 amount0, int256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(params.token0, params.token1, params.fee));
        (int256 quota0, int256 quota1) = work.getSwapQuota(msg.sender, address(pool));

        (amount0, amount1) = pool.swap(address(this), params.zeroOne, params.amountSpecified, 0, new bytes(0));
        // if(zeroone) {
        //     if(params.amountSpecified > 0)
        // }
    }

    // function distributeFee(address token, uint amount) internal nonReentrant {
    //     if(amount > 0) {
    //         uint toBank = amount.mul(9).div(10);
    //         IERC20(token).transfer(address(bank), toBank);
    //         // work.settle(msg.sender, token, 0, int128(toBank));
    //         work.settle(msg.sender, token, int128(toBank));
    //         IERC20(token).transfer(msg.sender, amount.sub(toBank));
    //     }
    // }
}