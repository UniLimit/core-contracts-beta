// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2; 

import '../UniV3TradingPair.sol';

interface IUnilimitFactory {

    /// @notice Deploys a new Unilimit Pair
    /// @param tokenA The address of the first token of the pair
    /// @param tokenB The address of the second token of the pair
    /// @param fee The Uniswap Pool fee in bps * 100
    /// @param settlerAddress The address of the settler entity attached to the pair
    /// @return newPair The newly created pair
    function deployPair(
        address tokenA,
        address tokenB,
        uint24 fee,
        address settlerAddress
    ) 
    external
    returns (
        UniV3TradingPair newPair
    );
}