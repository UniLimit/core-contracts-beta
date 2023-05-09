
const nftManager = {
  'Ethereum': '0xC36442b4a4522E871399CD717aBDD847Ab11FE88',
  'goerli': '0xC36442b4a4522E871399CD717aBDD847Ab11FE88',
  'goerli_arbitrum': '0x622e4726a167799826d1E1D150b076A7725f5D81'
};


const _WETH9 = {
  'Ethereum': '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
  'goerli': '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
  'goerli_arbitrum': '0xe39Ab88f8A4777030A534146A9Ca3B52bd5D43A3'
};

const v3FactoryAddress = {
  'Ethereum': '0x1F98431c8aD98523631AE4a59f267346ea31F984',
  'goerli': '0x1F98431c8aD98523631AE4a59f267346ea31F984',
  'goerli_arbitrum': '0x4893376342d5D7b3e31d4184c08b265e5aB2A3f6'
};


const nftManagerABI = require("./nftManagerABI.json")

const UnilimitFactory = artifacts.require("UnilimitFactory");

const UniswapNFTPositionManager = new web3.eth.Contract(nftManagerABI, nftManager);

const testAddress = '0x78fe389778e5e8be04c4010Ac407b2373B987b62'

const USDCWETHPool = {
  'Ethereum':'0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8',
  'goerli': '0x614dAdD4af14781A76aD6a9a0ecb8e207C557744',
  'arbitrum':'0xE754841B77C874135caCA3386676e886459c2d61',
  'goerli_arbitrum': '0xAa1fCd6Ba878f999FDBDe38bC0F61FbeeA248415'
}

const ganacheOwner = '0xa795155c094CACbb41a867B52A8596Ac7F5D376A'

const network = 'goerli_arbitrum'

module.exports = function(deployer) {
  // Deploy Position Manager
  //deployer.deploy(PositionManager);
  //deployer.deploy(SwapExamples);
  
  //UnilimitFactory deployer
  deployer.deploy(
    UnilimitFactory,
    nftManager[network],
    _WETH9[network],
    v3FactoryAddress[network]
  );

  //Goerli deployer
  /*deployer.deploy(
    UniV3TradingPair,
    goerliUSDCWETHPool,
    nftManager,
    testAddress
  );*/

};
