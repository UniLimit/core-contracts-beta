// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2; 

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IUniV3TradingPair is 
    IERC721Receiver
{

    /// @notice Emitted when a new order is opened
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @param trader The address of the wallet that opened the position
    /// @param side Buy/Sell switch. True: buying token0 with token1, False: buying token1 with token0
    /// @param sqrtPriceX96 The price of the order in the UniV3 format
    /// @param quantity Position size in token value
    event Open(uint256 positionId, address indexed trader, bool side, uint160 sqrtPriceX96, uint256 quantity);
    
    /// @notice Emitted when a position is closed by a user
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @param trader The address of the wallet that owns the position
    event Close(uint256 positionId, address indexed trader);

    /// @notice Emitted when a position size is adjusted by a user
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @param trader The address of the wallet that owns the position
    /// @param newQuantity Updated position quantity in token value
    event SizeChanged(uint256 positionId, address indexed trader, uint256 newQuantity);
    
    /// @notice Emitted when a position size is filled by a settler (=/= user)
    /// @param side Buy/Sell switch. True: buying token0 with token1, False: buying token1 with token0
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @param trader The address of the wallet that owns the position
    /// @param executionPrice The final execution price of the order (the average between the lower and upper boundary of the UniV3 LP)
    /// @param quantity Updated position quantity in token value
    event Settled(bool side, uint256 positionId, address indexed trader, uint256 executionPrice, uint256 quantity);
    
    /// @notice Opens a new limit order with ETH
    /// @dev This function handles native ETH and token payments
    /// @param side Buy/Sell switch. True: buying token0 with token1, False: buying token1 with token0
    /// @param sqrtPriceX96 The price of the order in the UniV3 format
    /// @param quantity Position size in token value
    /// @return positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    function createOrder(
        bool side,
        uint160 sqrtPriceX96, 
        uint256 quantity
    )
    external 
    payable  
    returns (
        uint256 positionId
    );
    
    /// @notice Increases an existing order's size with native ETH
    /// @dev Call this only when the user wants to sell native ETH
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @param quantity The incremental quantity you want to add to the existing position
    function increaseSize(
        uint256 positionId,
        uint256 quantity
    )
    payable
    external;

    /// @notice Decreases an existing order's size
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @param quantity The quantity you want to remove from the existing position
    function decreaseSize(
        uint256 positionId,
        uint256 quantity
    ) 
    external;


    /// @notice Closes a limit order position, has to be triggered by the owner of the position
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    function closePositionOwner(uint256 positionId) external;

    /// @notice Closes a limit order position, has to be triggered by the owner of the position
    /// @dev has to be called when the position is fully out of bounds
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @return settlerFees0 The amount of fees collected in token0 for the settler
    /// @return settlerFees1 The amount of fees collected in token1 for the settler
    function settleOrder(uint256 positionId) external returns (uint256 settlerFees0, uint256 settlerFees1);
    
    /// @notice Returns the Uniswap NFT position to the position owner
    /// @dev only for user issues
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    function returnPositionToUser(uint256 positionId) external;

    /// @notice Getter to fetch current pool price
    /// @return price current pool price as sqrtPriceX96
    function getPoolPrice() external view returns (uint160 price);
    
    /// @notice Getter to fetch a given position's side 
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @return side Buy/Sell switch. True: buying token0 with token1, False: buying token1 with token0
    function getSide(uint256 positionId) external view returns (bool side);

    /// @notice Getter to fetch a given position's lower tick 
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @return tickLower lower price tick for position
    function getTickLower(uint256 positionId) external view returns (int24 tickLower);

    /// @notice Getter to fetch a given position's upper tick 
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @return tickUpper upper price tick for position
    function getTickUpper(uint256 positionId) external view returns (int24 tickUpper);

    /// @notice Getter to fetch a given position's size
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @return quantity Position size in token value
    function getQuantity(uint256 positionId) external view returns (uint256 quantity);

    /// @notice Getter to fetch a given position's owner
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @return _owner Position owner's address
    function getOwner(uint256 positionId) external view returns (address _owner);

    /// @notice Getter to fetch a given position's status
    /// @param positionId The position ID linking the open order to its Uniswap Liquidity Position NFT
    /// @return active Position status (true: open, false: closed/filled)
    function getActivityStatus(uint256 positionId) external view returns (bool active);

    /// @notice The first of the two tokens of the underlying Uniswap V3 pool, sorted by address
    /// @return The token contract address
    function poolToken0() external view returns (address);

    /// @notice The second of the two tokens of the underlying Uniswap V3 pool, sorted by address
    /// @return The token contract address
    function poolToken1() external view returns (address);

    receive() external payable;

    fallback() external payable;
}