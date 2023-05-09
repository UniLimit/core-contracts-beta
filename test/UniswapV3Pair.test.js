const MyContract = artifacts.require("UniV3TradingPair");
const BigNumber = require('bignumber.js');

contract("MyContract", async (accounts) => {
  let myContract;

  beforeEach(async () => {
    myContract = await MyContract.deployed();
  });

  it("Open order, verify owner, increase size, verify quantity + slippage, decrease position, and close position", async () => {
    const side = true;
    const sqrtPriceX96 = '4339505179874790000000000';;
    const quantity = '10000000000000000000';
    const _qty = new BigNumber(quantity, 10);
    const sender = accounts[8];
    
    console.log("Step1");
    // Step 1
    const positionId = await myContract.createOrder(side, sqrtPriceX96, quantity, {
      from: sender,
      value: quantity,
    });
    
    pos = positionId.receipt.logs[0].args.positionId.toString(10);
    console.log("position ID:", pos);

    let liq = await myContract.getPositionLiquidity(pos)
    console.log("Liq:",liq.toString(10));

    console.log("Step2");
    // Step 2
    const owner = await myContract.getOwner(pos);
    assert.equal(owner, sender);

    console.log("Step3");
    // Step 3

    qty_test1= '9000000000000000000';
    //_qty_test1= 9000000000000000000;

    await myContract.increaseSize(pos, qty_test1, {
        from: sender,
        value: qty_test1,
    });
    
    liq = await myContract.getPositionLiquidity(pos)
    console.log("Liq:",liq.toString(10));

    console.log("Quantity + slippage check");
    // Step 4
    const resultQuantity = await myContract.getQuantity(pos);

    console.log("Arg quantities:", (new BigNumber(qty_test1) + new BigNumber(_qty)).toString(10))
    console.log("New quantity: ", resultQuantity.toString(10));
    
    //Slippage check
    //assert(resultQuantity / (new BigNumber(qty_test1) + new BigNumber(_qty)) >= 0.99);

    //decrease order
    const decreaseQty = '8000000000000000000'
    console.log("decreasing order by",decreaseQty/1E18, "ETH");

    await myContract.decreaseSize(pos, decreaseQty, {
        from: sender
    });

    liq = await myContract.getPositionLiquidity(pos)
    
    console.log("Liq:",liq.toString(10));

    // Step 4
    const resultDecreaseQuantity = await myContract.getQuantity(pos);

    console.log("Arg quantities:", (new BigNumber(qty_test1) + new BigNumber(_qty) - new BigNumber(decreaseQty) ).toString(10) )
    console.log("New quantity: ", resultDecreaseQuantity.toString(10));
    console.log("Assert slippage: ", new BigNumber(resultQuantity) / (new BigNumber(qty_test1) + new BigNumber(_qty) - new BigNumber(decreaseQty)));

    console.log("closing position...");
    await myContract.closePositionOwner(pos, {
        from: sender,
    });

    console.log("verify position is inactive")
    const posStatus = await myContract.getActivityStatus(pos)
    assert(posStatus == false)

    /*
    assert(resultQuantity.gte("19900000000000000"));
    assert(resultQuantity.lte("20000000000000000"));
    */

    
    /*console.log("Step5");
    // Step 5
    await myContract.returnPositionToUser(pos, { from: sender });

    */
  });
});