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
    function slot0() external returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
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

pragma abicoder v2;
interface IMulticall {
    /// @notice Call multiple functions in the current contract and return the data from all of them if they all succeed
    /// @dev The `msg.value` should not be trusted for any method callable from multicall.
    /// @param data The encoded function data for each of the calls to make to this contract
    /// @return results The results from each of the calls passed in via data
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}

abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) external payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}

contract Sandbox is Multicall {
    address public owner;

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    IUniswapV3Factory public factory;
    
    struct Pool {
        address token0;
        address token1;
        uint24 fee;
    }
    
    constructor(IUniswapV3Factory _factory) public {
        factory = _factory;
        owner = msg.sender;
    }
    
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external {
        Pool memory decoded = abi.decode(_data, (Pool));
        require(msg.sender == factory.getPool(decoded.token0, decoded.token1, decoded.fee), "FORBIDDEN");
       if(amount0Delta > 0) IERC20(decoded.token0).transfer(msg.sender, uint256(amount0Delta));
       if(amount1Delta > 0) IERC20(decoded.token1).transfer(msg.sender, uint256(amount1Delta));
    }
    
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        Pool memory decoded = abi.decode(data, (Pool));
        require(msg.sender == factory.getPool(decoded.token0, decoded.token1, decoded.fee), "FORBIDDEN");
        if (amount0Owed > 0) IERC20(decoded.token0).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) IERC20(decoded.token1).transfer(msg.sender, amount1Owed);
    }
    
    function swap(
        Pool memory pool,
        uint256 amountSpecified,
        bool zeroForOne
    ) external returns (uint160 sqrtPriceX96, int24 tick){
        require(msg.sender == owner, "FORBIDDEN");
        IV3Pool poolInterface = IV3Pool(factory.getPool(pool.token0, pool.token1, pool.fee));
        poolInterface.swap(address(this), zeroForOne, toInt256(amountSpecified), zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1, abi.encode(pool));
        (sqrtPriceX96, tick, , , , ,) = poolInterface.slot0();
    }
    
    function initialize(Pool memory pool, uint160 sqrtPriceX96) external {
        require(msg.sender == owner, "FORBIDDEN");
        IV3Pool poolInterface = IV3Pool(factory.getPool(pool.token0, pool.token1, pool.fee));
        poolInterface.initialize(sqrtPriceX96);
    }
    
    function mint(
        Pool memory pool, 
        int24 tickLower,
        int24 tickUpper,
        uint128 amount) external {
            require(msg.sender == owner, "FORBIDDEN");
            IV3Pool poolInterface = IV3Pool(factory.getPool(pool.token0, pool.token1, pool.fee));
            poolInterface.mint(address(this), tickLower, tickUpper, amount, abi.encode(pool));
        }
    
    function burn(Pool memory pool, int24 tickLower, int24 tickUpper, uint128 amount) external {
        require(msg.sender == owner, "FORBIDDEN");
        IV3Pool poolInterface = IV3Pool(factory.getPool(pool.token0, pool.token1, pool.fee));
        poolInterface.burn(tickLower, tickUpper, amount);
        poolInterface.collect(address(this), tickLower, tickUpper, uint128(-1), uint128(-1));
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