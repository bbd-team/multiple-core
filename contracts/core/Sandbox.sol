// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.7.0;

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IV3Pool {
    function token0() external returns(address);
    function token1() external returns(address);
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
    function initialize(uint160 sqrtPriceX96) external;
}

interface IUniswapV3Factory {
    function getPool(address token0, address token1, uint24 fee) external returns(address);
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
    function feeAmountTickSpacing(uint24) external returns (uint24);
}

contract Sandbox {
    IV3Pool public pool;
    IERC20 public token0;
    IERC20 public token1;
    address public owner;
    
    uint24 constant public fee = 3000;

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    
    constructor(IUniswapV3Factory _factory, IERC20 _token0, IERC20 _token1) public {
        address _pool = _factory.getPool(address(_token0), address(_token1), fee);
        if(_pool == address(0)) {
            _pool = _factory.createPool(address(_token0), address(_token1), fee);
        }
        owner = msg.sender;
        pool = IV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
    }
    
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external {
        require(msg.sender == address(pool), "FORBIDDEN");
       if(amount0Delta > 0) token0.transfer(address(pool), uint256(amount0Delta));
       if(amount1Delta > 0) token1.transfer(address(pool), uint256(amount1Delta));
    }
    
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        require(msg.sender == address(pool), "FORBIDDEN");
        if (amount0Owed > 0) token0.transfer(address(pool), amount0Owed);
        if (amount1Owed > 0) token1.transfer(address(pool), amount1Owed);
    }
    
    function swap(
        uint256 amountSpecified,
        bool zeroForOne
    ) external {
        require(msg.sender == owner, "FORBIDDEN");
        pool.swap(address(this), zeroForOne, toInt256(amountSpecified), zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1, new bytes(0));
    }
    
    function initialize(uint160 sqrtPriceX96) external {
        require(msg.sender == owner, "FORBIDDEN");
        pool.initialize(sqrtPriceX96);
    }
    
    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount) external {
            require(msg.sender == owner, "FORBIDDEN");
            pool.mint(address(this), tickLower, tickUpper, amount, new bytes(0));
        }
    
    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external {
        require(msg.sender == owner, "FORBIDDEN");
        pool.burn(tickLower, tickUpper, amount);
        pool.collect(address(this), tickLower, tickUpper, uint128(-1), uint128(-1));
    } 

    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2**255);
        z = int256(y);
    }
    
    function withdraw(IERC20 token) external {
        require(msg.sender == owner);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }
}