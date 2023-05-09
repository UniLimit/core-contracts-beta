// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2; 

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./interfaces/IUniV3TradingPair.sol";


contract UniV3TradingPair is IERC721Receiver, ReentrancyGuard, IUniV3TradingPair {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable override poolToken0;
    address public immutable override poolToken1;
    uint24 public immutable FEE;
    address public immutable nftManagerAddress;
    address public immutable WETH9;
    address public immutable settler;

    uint256 private constant MINT_BURN_SLIPPAGE = 200; // .5% max slippage on order creation

    INonfungiblePositionManager public immutable nftManager;
    IUniswapV3Pool public immutable pool;
    

    struct Order {
        bool side; // true buy 0 with 1, false buy 1 with 0
        int24 tickLower; // lower price tick for position
        int24 tickUpper; // higher price tick for position
        uint256 quantity;
        uint128 liquidity;
        address owner;
        bool active;
    }

    mapping(uint256 => Order) orders;
    
    constructor(
        address pool_address,
        address _nftManager,
        address _settler,
        address _WETH9
    ) {
        //pool = _pool;
        //nftManager = _nftManager;
        pool = IUniswapV3Pool(pool_address);
        nftManagerAddress = _nftManager;
        nftManager = INonfungiblePositionManager(_nftManager);
        poolToken0 = IUniswapV3Pool(pool_address).token0();
        poolToken1 = IUniswapV3Pool(pool_address).token1();
        FEE = IUniswapV3Pool(pool_address).fee();
        settler = _settler;
        WETH9 =  _WETH9;
    }

    /*----------------------------------------------------------*/
    /*                     ERC721 ENABLER                       */
    /*----------------------------------------------------------*/

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata
    ) public override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /*----------------------------------------------------------*/
    /*                  USER FACING FUNCTIONS                   */
    /*----------------------------------------------------------*/
    
    /// Opens a limit order my minting a LP position on the Uniswap v3 Pair
    /// params: 
    /// - side: true if you buy token0 for token1, false if you buy token1 for token0
    /// - sqrtPriceX96: sqrt(tokenRatio) * 2 ** 96 ::see uniswap doc
    /// - quantity: the number of tokens in the position
    function createOrder(
        bool side,
        uint160 sqrtPriceX96, 
        uint256 quantity
    ) external payable override nonReentrant returns (uint256 positionId){
        
        //Price check
        require(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO && sqrtPriceX96 <= TickMath.MAX_SQRT_RATIO, "Invalid price");
        //quantity check
        require(quantity > 0, "Quantity must be greater than zero");

        address tokenOrder = side ? poolToken1 : poolToken0; 

        //If user wants to pay with ETH
        if(msg.value > 0){
            //check that the order is on the right side
            require(tokenOrder == WETH9, "Sent ETH but order doesn't require");

            //check the value and quantity match
            require(msg.value == quantity, "ETH sent and quantity mismatch");

            // Wrap ETH to WETH
            IWETH9(WETH9).deposit{value: msg.value}();

        } else { // If user is paying with token
            //Check user ERC20 balance
            uint256 tokenBalance = IERC20(tokenOrder).balanceOf(msg.sender);
            require(tokenBalance >= quantity, "Insufficient token balance");

            //transfer the token to contract
            IERC20(tokenOrder).safeTransferFrom(
                msg.sender,
                address(this),
                quantity
            );
        }
        
        createOrderInternal(
            side,
            sqrtPriceX96,
            quantity
        );
    }
    

    //mints a new limit order from an ERC20 held by the contract - only called by the external createOrder that pre-processes eventual ETH to WETH wrapping
    function createOrderInternal(
        bool side,
        uint160 sqrtPriceX96, 
        uint256 quantity
    ) private returns (uint256 positionId) {
        address token = side ? poolToken1 : poolToken0;
        //increase NFT Position contract allowance
        IERC20(token).safeIncreaseAllowance(
            address(nftManager),
            quantity
        );

        //Compute corresponding tick range
        int24 tickUpper;
        int24 tickLower;
        ( tickLower, tickUpper) = getTicksFromPrice(side, sqrtPriceX96);

        //Mint position
        uint128 _liquidity;
        uint256 _amount0;
        uint256 _amount1;
        (
            positionId,
            _liquidity,
            _amount0,
            _amount1
        ) = mintNewPosition(side, tickLower, tickUpper, quantity);
        

        //Emit event
        orders[positionId] = Order({
            side: side,
            tickLower: tickLower,
            tickUpper: tickUpper,
            quantity: _amount0.add(_amount1),
            liquidity: _liquidity,
            owner: msg.sender,
            active: true
        });

        emit Open(positionId, msg.sender, side, getPriceFromTicks(tickLower, tickUpper), orders[positionId].quantity);
    }
    
    
    function increaseSize(
        uint256 positionId,
        uint256 quantity
    ) payable external override nonReentrant {
        require(orders[positionId].owner == msg.sender,"Not the owner");
        require(orders[positionId].active, "Not Active");
        require(quantity > 0, "Quantity must be greater than zero");

        address token = getLiquidityToken(positionId);

        if(msg.value > 0){ //increase position with ETH
            require(msg.value == quantity, "ETH sent and quantity mismatch");
            require(token == WETH9, "Position can't accept ETH");
            // Wrap ETH to WETH
            IWETH9(token).deposit{value: msg.value}();
        } else { //Increase position with token
            
            //Check user ERC20 balance
            uint256 tokenBalance = IERC20(token).balanceOf(msg.sender);
            require(tokenBalance >= quantity, "Insufficient token balance");

            //Transfer the requested quantity to the contract
            IERC20(token).safeTransferFrom(
                msg.sender,
                address(this),
                quantity
            );
        }

        increaseSizeInternal(
            positionId,
            quantity
        );
    }
    
    function increaseSizeInternal(
        uint256 positionId,
        uint256 quantity
    ) private {
        address token = getLiquidityToken(positionId);
        //increase NFT Position contract allowance
        IERC20(token).safeIncreaseAllowance(
            address(nftManager),
            quantity
        );
        
        //Increase position
        uint128 _liquidity;
        uint256 _amount0;
        uint256 _amount1;

        //_amount0 and _amount1 are the token spent to get the new _liquidity value
        (_liquidity, _amount0, _amount1) = increaseLiquidityCurrentRange(positionId, quantity);
        
        require(
            _liquidity > 0 && ((_amount0 > 0) != (_amount1 > 0)),
            "Invalid liquidity increase"
        );

        //update state
        orders[positionId].quantity += _amount0.add(_amount1);
        orders[positionId].liquidity = getPositionLiquidity(positionId);
        
        emit SizeChanged(positionId, orders[positionId].owner, orders[positionId].quantity);
    }

    /// notice: Decreases the order size of a limit order position
    function decreaseSize(
        uint256 positionId,
        uint256 quantity
    ) external override nonReentrant {
        require(orders[positionId].owner == msg.sender, "NTO"); //not the owner
        require(orders[positionId].quantity >= quantity, "NEF"); //not enough funds
        require(orders[positionId].active, "NA"); //not active
        
        uint256 amount0;
        uint256 amount1;
        
        (, , amount0, amount1) = withdraw(positionId, quantity);

        refundUser(amount0, amount1, positionId);
        
        //require(amount0 + amount1 >= quantity, "withdrew less than asked ");
        uint128 updatedLiquidity = getPositionLiquidity(positionId);

        orders[positionId].quantity -= amount0 + amount1;
        orders[positionId].liquidity = updatedLiquidity;

        emit SizeChanged(
            positionId,
            orders[positionId].owner,
            orders[positionId].quantity
        );
    }

    /// notice: Closes a limit order position, has to be triggered by the owner of the position
    function closePositionOwner(uint256 positionId) external override nonReentrant {
        require(orders[positionId].owner == msg.sender, "NTO");
        require(orders[positionId].active, "NA");

        uint256 amount0;
        uint256 amount1;

        //In this case the user also collects any accumulated fees
        (, ,amount0, amount1) = withdrawAll(positionId);

        //update liquidity values
        orders[positionId].quantity = 0;
        orders[positionId].liquidity = getPositionLiquidity(positionId);
        
        refundUser(amount0, amount1, positionId);
        
        orders[positionId].active = false;
        emit Close(positionId, orders[positionId].owner);
    }

    function settleOrder(uint256 positionId) external override nonReentrant returns(uint256 settlerFees0, uint256 settlerFees1) {

        require(msg.sender == settler, "not called from the settler contract");

        int24 poolTick = getCurrentPoolTick();

        //Check that the position is fully out of range
        require(
            orders[positionId].side ? 
            poolTick < orders[positionId].tickLower :
            poolTick > orders[positionId].tickUpper
            ,"ONF" // order not filled
        );

        //check that the position is active
        require(
            orders[positionId].active,
            "NA" //not active
        );

        uint256 amount0;
        uint256 amount1;
        uint256 totalAmount0;
        uint256 totalAmount1;

        (amount0, amount1, totalAmount0, totalAmount1) = withdrawAll(
            positionId
        );

        //handles tokens distribution
        (settlerFees0, settlerFees1) = settle(positionId, amount0, amount1, totalAmount0, totalAmount1);

        //update position
        orders[positionId].active = false;

        //calculate executionPrice as token0/token1 -- for USDC/WETH pool: amount of USDC sent/received divided by amount of WETH sent/received
        uint256 executionPrice = getExecutionPrice(positionId, amount0, amount1);

        emit Settled(
            orders[positionId].side,
            positionId,
            orders[positionId].owner,
            executionPrice,
            orders[positionId].quantity
        );
    }

    function settle(
        uint256 positionId,
        //amounts are nominal value
        uint256 amount0, 
        uint256 amount1,
        //totalAmount include accrued fees
        uint256 totalAmount0, 
        uint256 totalAmount1
    ) private returns (
        uint256 settlerFees0,
        uint256 settlerFees1
    ){
        //settler collects uni pool fees
        settlerFees0 = totalAmount0.sub(amount0);
        settlerFees1 = totalAmount1.sub(amount1);

        //settle user amounts, we chose not to send dust (accumulated Uniswap fees on the other side of the trade) to the user
        refundUser(amount0, amount1, positionId);
        
        //settle settler amounts
        if(settlerFees0 > 0) {
            IERC20(poolToken0).safeTransfer(settler, settlerFees0);
        }
        if(settlerFees1 > 0) {
            IERC20(poolToken1).safeTransfer(settler, settlerFees1);
        }
    }

    function refundUser(uint256 amount0, uint256 amount1, uint256 positionId) private {
        //transfer back the input tokens to the msg.sender
        if(amount0 > 0) {
            //if poolToken0 is WETH, unwrap and send ETH to the msg.sender
            if(poolToken0 == WETH9){
                //unwrap WETH
                IWETH9(poolToken0).withdraw(amount0);
                //send ETH
                (bool success, ) = msg.sender.call{value: amount0}('');
                require(success, "Failed to send Ether");
            }else{
                IERC20(poolToken0).safeTransfer(orders[positionId].owner, amount0);
            }
        }

        if(amount1 > 0) {
            //if poolToken1 is WETH, unwrap the ETH for the user
            if(poolToken1 == WETH9){
                //unwrap WETH
                IWETH9(poolToken1).withdraw(amount1);
                //send ETH
                (bool success, ) = msg.sender.call{value: amount1}('');
                require(success, "Failed to send Ether");
            } 
        } else {
            IERC20(poolToken1).safeTransfer(orders[positionId].owner, amount1);
        }
    }

    receive() external payable override {}

    fallback() external payable override {}

    /*----------------------------------------------------------*/
    /*          UNISWAP POSITION MANAGER FUNCTIONS              */
    /*----------------------------------------------------------*/

    function mintNewPosition(
        bool side,
        int24 tickLower,
        int24 tickUpper,
        uint256 quantity
    ) private returns(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ){
        
        uint256 amount0ToMint = side ? 0 : quantity;
        uint256 amount1ToMint = side ? quantity : 0;
        
        (tokenId, liquidity, amount0, amount1) = nftManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: poolToken0,
                token1: poolToken1,
                fee: FEE,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: amount0.sub(amount0.div(MINT_BURN_SLIPPAGE)),
                amount1Min: amount1.sub(amount1.div(MINT_BURN_SLIPPAGE)),
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        //refund unused tokens -- this should be optimized for gas: first calculated the amount to send, then take it from the user
        if(amount0ToMint > amount0){
            uint256 refund0 = amount0ToMint - amount0;
            IERC20(poolToken0).safeTransfer(msg.sender, refund0);
        }

        if(amount1ToMint > amount1){
            uint256 refund1 = amount1ToMint - amount1;
            IERC20(poolToken1).safeTransfer(msg.sender, refund1);
        }

    }

    function increaseLiquidityCurrentRange(
        uint256 positionId,
        uint256 quantity
    ) private returns(
        uint128 newLiquidity,
        uint256 newAmount0,
        uint256 newAmount1
    ){
        (int24 tickLower, int24 tickUpper) = getTicks(positionId);

        //require that pool price is outside of order range
        int24 currentTick = getCurrentPoolTick();
        
        require(
            tickUpper != currentTick && tickLower != currentTick, // ticks are always next to each other so that's enough
            "LPA" // Liquidity position is active
        );

        uint256 amount0toAdd = orders[positionId].side ? 0 : quantity;
        uint256 amount1toAdd = orders[positionId].side ? quantity : 0;

        //add liquidity
        (newLiquidity, newAmount0, newAmount1) = nftManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionId,
                amount0Desired: amount0toAdd,
                amount1Desired: amount1toAdd,
                amount0Min: amount0toAdd.sub(amount0toAdd.div(MINT_BURN_SLIPPAGE)),
                amount1Min: amount1toAdd.sub(amount1toAdd.div(MINT_BURN_SLIPPAGE)),
                deadline: block.timestamp
            })
        );

        //refund unspent tokens to the user
        //uint256 refund = orders[positionId].side ? amount1toAdd + orders[positionId].quantity - newAmount1 : amount0toAdd + orders[positionId].quantity - newAmount0; 
        //IERC20(token).safeTransfer(msg.sender, refund);
    }

    function decreaseLiquidityCurrentRange(
        uint256 positionId,
        uint128 liquidity
    ) private returns (uint256 amount0, uint256 amount1){

        (amount0, amount1) = nftManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
    }

    function withdraw(
        uint256 positionId,
        uint256 amount 
    ) private returns (
        uint256 _amount0,
        uint256 _amount1,
        uint256 totalCollected0,
        uint256 totalCollected1
    ) {
        //translate amount requested into Uni pool's liquidity value
        uint128 _liquidity = getLiquidityFromAmount(positionId, amount);
        require(_liquidity>0, "Liquidity is zero");
        require(_liquidity <= getPositionLiquidity(positionId), "NEF"); 

        //decrease Liq
        (_amount0, _amount1) = decreaseLiquidityCurrentRange(positionId,_liquidity);

        //collect fees + liq
        (totalCollected0, totalCollected1) = collect(positionId); // collected by the contract

        // !!! At the end of the operation, the position's tokens are still held by the contract
        // If the withdraw function is triggered from decreaseSize() or closePositionOwner(), the 
        // full balance is returned to the user (see each functions).
        // If the withdraw function is triggered from settleOrder(), the balance harvested is returned
        // to the user minus service fee. 
    }

    function withdrawAll(
        uint256 positionId
    ) private returns (
        uint256 _amount0,
        uint256 _amount1,
        uint256 totalCollected0,
        uint256 totalCollected1
    ) {
        //translate amount requested into Uni pool's liquidity value
        uint128 _liquidity = getPositionLiquidity(positionId);
        require(_liquidity>0, "Liquidity is zero");
        
        //decrease Liq
        (_amount0, _amount1) = decreaseLiquidityCurrentRange(positionId,_liquidity);

        //collect fees + liq
        (totalCollected0, totalCollected1) = collect(positionId); // collected by the contract

        // !!! At the end of the operation, the position's tokens are still held by the contract
        // If the withdraw function is triggered from decreaseSize() or closePositionOwner(), the 
        // full balance is returned to the user (see each functions).
        // If the withdraw function is triggered from settleOrder(), the balance harvested is returned
        // to the user minus service fee. 
    }

    // Collect fees
    function collect(
        uint256 positionId
    ) private returns (uint256 collected0, uint256 collected1) {
        (collected0, collected1) = collectPosition(
            type(uint128).max,
            type(uint128).max,
            positionId
        );
    }

    //Collect token amounts from pool position -- tokens need to have been withdrawn with decreaseLiquidity
    function collectPosition(
        uint128 amount0,
        uint128 amount1,
        uint256 positionId
    ) private returns (uint256 collected0, uint256 collected1) {

        (collected0, collected1) = nftManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionId,
                recipient: address(this),
                amount0Max: amount0,
                amount1Max: amount1
            })
        );
    }
    
    /*----------------------------------------------------------*/
    /*                   "CUSTOMER SUPPORT"                     */
    /*----------------------------------------------------------*/
    
    function returnPositionToUser(
        uint256 positionId
    ) external override {
        //return the uniswap position NFT to the user so they can manage their position
        //Can be called only by the owner of the position
        require(
            orders[positionId].owner == msg.sender,
            "Not the owner"
        );
        require(
            orders[positionId].active,
            "Not active"
        );
        nftManager.safeTransferFrom(address(this), msg.sender, positionId);
        delete orders[positionId];
    }

    /*----------------------------------------------------------*/
    /*                  TRADING PAIR UTILS                      */
    /*----------------------------------------------------------*/

    function getLiquidityToken(uint256 positionId) private view returns(address token) {
        return orders[positionId].side ? poolToken1 : poolToken0;
    }

    function getLiquidityFromAmount(uint256 positionId, uint256 amount) private view returns (uint128 _liquidity) {

        (int24 tickLower, int24 tickUpper) = getTicks(positionId);

        uint128 _liq;

        if(orders[positionId].side){ //buy 0 with 1
            _liq = LiquidityAmounts.getLiquidityForAmount1(
                getPriceFromTick(tickLower),
                getPriceFromTick(tickUpper),
                amount
            );
        } else {
            _liq = LiquidityAmounts.getLiquidityForAmount0(
                getPriceFromTick(tickLower),
                getPriceFromTick(tickUpper),
                amount
            );
        }
        _liquidity = _liq;
    }

    function getExecutionPrice(
        uint256 positionId,
        uint256 userAmount0,
        uint256 userAmount1
    ) private view returns(
        uint256 price
    ) {
        price = orders[positionId].side ? userAmount0.div(orders[positionId].quantity) : orders[positionId].quantity.div(userAmount1);
    }

    /*----------------------------------------------------------*/
    /*                      UNISWAP UTILS                       */
    /*----------------------------------------------------------*/

    function getPriceFromTick(int24 tick) private pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(tick);
    }

    function getCurrentPoolTick() private view returns (int24 tick){
        (, tick , , , , , ) = pool.slot0();
    }

    function getPositionLiquidity(
        uint256 positionId
    ) public view returns (uint128 liquidity) {
        (, , , , , , , liquidity, , , , ) = nftManager.positions(positionId);
    }

    function getPoolPrice() external view override returns (uint160 price) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return sqrtRatioX96;
    }

    function getTicks(
        uint256 positionId
    ) private view returns (int24 tickLower, int24 tickUpper) {
        (, , , , , tickLower, tickUpper, , , , , ) = nftManager.positions(
            positionId
        );
    }

    function getPriceFromTicks(
        int24 tickLower,
        int24 tickUpper
    ) private pure returns(uint160 sqrtPriceX96){
        uint160 p1 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 p2 = TickMath.getSqrtRatioAtTick(tickUpper);
        sqrtPriceX96 = (p1 + p2) / 2;
    }

    function getTicksFromPrice(
        bool side,
        uint160 sqrtPriceX96
    ) private view returns(
        int24 tickLower,
        int24 tickUpper
    ) {
        int24 tickSpacing = pool.tickSpacing();
        int24 closestTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        if(side) {
            tickUpper = closestTick - (closestTick % tickSpacing);
            tickLower = tickUpper - tickSpacing;
        } else {
            tickLower = closestTick - (closestTick % tickSpacing) + tickSpacing;
            tickUpper = tickLower + tickSpacing;
        }
    }

    /*----------------------------------------------------------*/
    /*                    POSITION GETTERS                      */
    /*----------------------------------------------------------*/

   function getSide(uint256 positionId) external view override returns (bool side) {
        side = orders[positionId].side;
    }
    function getTickLower(uint256 positionId) external view override returns (int24 tickLower) {
        tickLower = orders[positionId].tickLower;
    }
    function getTickUpper(uint256 positionId) external view override returns (int24 tickUpper) {
        tickUpper = orders[positionId].tickUpper;
    }
    function getQuantity(uint256 positionId) external view override returns (uint256 quantity) {
        quantity = orders[positionId].quantity;
    }
    function getOwner(uint256 positionId) external view override returns (address _owner) {
        _owner = orders[positionId].owner;
    }
    function getActivityStatus(uint256 positionId) external view override returns (bool active) {
        active = orders[positionId].active;
    }

}