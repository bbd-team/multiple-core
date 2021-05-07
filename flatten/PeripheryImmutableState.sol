// Dependency file: contracts/external/uniswap-v3-periphery/interfaces/IPeripheryImmutableState.sol

// SPDX-License-Identifier: GPL-2.0-or-later
// pragma solidity >=0.5.0;

/// @title Immutable state
/// @notice Functions that return immutable state of the router
interface IPeripheryImmutableState {
    /// @return Returns the address of the Uniswap V3 factory
    function factory() external view returns (address);

    /// @return Returns the address of WETH9
    function WETH9() external view returns (address);
}


// Root file: contracts/external/uniswap-v3-periphery/base/PeripheryImmutableState.sol

pragma solidity =0.7.6;

// import 'contracts/external/uniswap-v3-periphery/interfaces/IPeripheryImmutableState.sol';

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
abstract contract PeripheryImmutableState is IPeripheryImmutableState {
    /// @inheritdoc IPeripheryImmutableState
    address public immutable override factory;
    /// @inheritdoc IPeripheryImmutableState
    address public immutable override WETH9;

    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
    }
}
