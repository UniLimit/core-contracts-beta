// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2; 

import './UniV3TradingPair.sol';
import './interfaces/IUnilimitFactory.sol';

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract UnilimitFactory is IUnilimitFactory{

    address public immutable nftManager;
    address public immutable WETH9;
    IUniswapV3Factory public immutable uniswapV3Factory;

    constructor(
        address _nftManager,
        address _WETH9,
        address _uniswapV3FactoryAddress
    ){
        nftManager = _nftManager;
        WETH9 = _WETH9;
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3FactoryAddress);
    }

    function deployPair(
        address tokenA,
        address tokenB,
        uint24 fee,
        address settlerAddress
    ) 
    external
    override
    returns (
        UniV3TradingPair newPair
    ){
        //compute Uni pool address and check that it's already created exists
        address poolAddress = uniswapV3Factory.getPool(tokenA, tokenB, fee);
        require(poolAddress != address(0), "No corresponding pool for token & fee combination");

        //We assume the settler address exists? or require(msg.sender == settlerAddress) ?
        require(msg.sender == settlerAddress, "settler needs to be sender");
        
        //create contract
        newPair = new UniV3TradingPair(
            poolAddress,
            nftManager,
            settlerAddress,
            WETH9
        );
    }
}