// Dependency file: contracts/external/uniswap-v3-periphery/base/BlockTimestamp.sol

// SPDX-License-Identifier: GPL-2.0-or-later
// pragma solidity =0.7.6;

/// @title Function for getting block timestamp
/// @dev Base contract that is overridden for tests
abstract contract BlockTimestamp {
    /// @dev Method that exists purely to be overridden for tests
    /// @return The current block timestamp
    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}


// Root file: contracts/external/uniswap-v3-periphery/base/PeripheryValidation.sol

pragma solidity =0.7.6;

// import 'contracts/external/uniswap-v3-periphery/base/BlockTimestamp.sol';

abstract contract PeripheryValidation is BlockTimestamp {
    modifier checkDeadline(uint256 deadline) {
        require(_blockTimestamp() <= deadline, 'Transaction too old');
        _;
    }
}
