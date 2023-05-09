// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2; 

import './interfaces/IUniV3TradingPair.sol';
import './interfaces/IUnilimitFactory.sol';
import './UniV3TradingPair.sol';

import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SettlerV1 is ERC721, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUnilimitFactory public immutable PairFactory;

    uint256 public constant MAX_TOKENS = 10;
    uint256 private _numTokens = 0;

    mapping(address => bool) public supportedPairs;

    mapping(uint256 => mapping(address => uint256)) public accruedFees;

    constructor (
        address factoryAddress
    ) ERC721("UniLimit Settler", "ULS") {
        PairFactory = IUnilimitFactory(factoryAddress);
        
        for (uint256 i = 0; i < MAX_TOKENS; i++) {
            mintSettlingRights(msg.sender);
        }
    }
    
    function deployNewPair(
        address _tokenA,
        address _tokenB,
        uint24 _fee
    ) public {
        require(balanceOf(msg.sender) >= 1, "Not a NFT Holder");
        
        //create new pair
        UniV3TradingPair pair = PairFactory.deployPair(_tokenA, _tokenB, _fee, address(this));

        //add new pair to active pair mapping
        supportedPairs[address(pair)] = true;
    }

    function settle(
        address payable pairAddress,
        uint256 positionId,
        uint256 tokenId
    )
    public
    nonReentrant
    {
        require(supportedPairs[pairAddress], "pool not initiated by settler");
        require(IUniV3TradingPair(pairAddress).getActivityStatus(positionId), "position is already closed or settled");
        require(ownerOf(tokenId) == msg.sender, "Not the NFT holder");

        //uint256 settlerFees0;
        //uint256 settlerFees1;

        (uint256 settlerFees0, uint256 settlerFees1) = IUniV3TradingPair(pairAddress).settleOrder(positionId);
        
        address token0 = IUniV3TradingPair(pairAddress).poolToken0();
        address token1 = IUniV3TradingPair(pairAddress).poolToken1();

        // accrue the fees towards the token holder's token ID
        accruedFees[tokenId][token0] = accruedFees[tokenId][token0].add(settlerFees0);
        accruedFees[tokenId][token1] = accruedFees[tokenId][token1].add(settlerFees1);
    }

    function withdrawAllFees(
        address assetAddress,
        uint256 tokenId
    )
    public
    {
        uint256 amount = accruedFees[tokenId][assetAddress];
        withdrawFees(assetAddress, tokenId, amount);
    }

    function withdrawFees(
        address assetAddress,
        uint256 tokenId,
        uint256 amount
    ) public nonReentrant
    {
        require(ownerOf(tokenId) == msg.sender, "Not an NFT holder");
        require(accruedFees[tokenId][assetAddress] >= amount, "No fees available");

        accruedFees[tokenId][assetAddress] = accruedFees[tokenId][assetAddress].sub(amount);

        IERC20(assetAddress).safeTransferFrom(
            address(this),
            msg.sender,
            amount
        );
    }

    function mintSettlingRights(address minter) private {
        require(_numTokens < MAX_TOKENS, "Max supply reached");
        _safeMint(minter, _numTokens);
        _numTokens++;
    }
}