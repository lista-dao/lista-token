pragma solidity ^0.8.10;

import "./CommonListaDistributor.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./OracleCenter.sol";
import "../library/TickMath.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
  * @title ERC721LpListaDistributor
  * @dev lista token stake and distributor for erc721 LP token
 */
contract ERC721LpListaDistributor is CommonListaDistributor, ReentrancyGuardUpgradeable, IERC721Receiver {
    struct NFT {
        uint256 liquidity;
        uint256 tokenId;
    }
    /// account -> tokenId -> NFT
    mapping(address => mapping(uint256 => NFT)) public userNFTs;
    // account -> tokenIds
    mapping(address => uint256[]) public userNFTIds;
    // oracle center address
    OracleCenter public oracleCenter;
    // price rate
    uint256 public priceRate;
    // token0 address
    address public token0;
    // token1 address
    address public token1;
    // fee
    uint24 public fee;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev initialize contract
      * @param _admin admin address
      * @param _manager manager address
      * @param _vault lista vault address
      * @param _lpToken lp token address
      * @param _oracleCenter oracle center address
      */
    function initialize(
        address _admin,
        address _manager,
        address _vault,
        address _lpToken,
        address _oracleCenter,
        address _token0,
        address _token1,
        uint24 _fee,
        uint256 _percentRate
    ) external initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_vault != address(0), "vault is the zero address");
        require(_lpToken != address(0), "lp token is the zero address");
        require(_oracleCenter != address(0), "oracleCenter is the zero address");
        require(_token0 != address(0), "token0 is the zero address");
        require(_token1 != address(0), "token1 is the zero address");
        __AccessControl_init();
        __Pausable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(VAULT, _vault);
        lpToken = _lpToken;
        vault = IVault(_vault);
        string memory token0Name = IERC20Metadata(_token0).symbol();
        string memory token1Name = IERC20Metadata(_token1).symbol();
        name = string.concat("Lista-", token0Name, "-", token1Name);
        symbol = string.concat("Lista LP ", token0Name, "-", token1Name, " Distributor");
        oracleCenter = OracleCenter(_oracleCenter);
        priceRate = _percentRate;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }

    /**
     * @dev deposit LP token to get rewards
     * @param tokenId tokenId of LP token
     */
    function deposit(uint256 tokenId) whenNotPaused external {
        require(IERC721(lpToken).ownerOf(tokenId) == msg.sender, "Not owner of token");
        IERC721(lpToken).safeTransferFrom(msg.sender, address(this), tokenId);
    }

    /**
     * @dev withdraw LP token
     * @param tokenId tokenId of LP token
     */
    function withdraw(uint256 tokenId) whenNotPaused external {
        uint256 amount = userNFTs[msg.sender][tokenId].liquidity;
        _removeNFT(msg.sender, tokenId);
        _withdraw(msg.sender, amount);
        IERC721(lpToken).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @dev checkNFT whether NFT is valid
     * @param tokenId tokenId of LP token
     * @return isValid whether NFT is valid
     * @return liquidity liquidity of NFT
     */
    function checkNFT(uint256 tokenId) public view returns (bool, uint256) {
        (
            ,
            ,
            address _token0,
            address _token1,
            uint24 _fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 _liquidity,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(lpToken).positions(tokenId);

        if (_token0 != token0 || _token1 != token1 || _fee != fee) {
            return (false, 0);
        }

        uint256 liquidity = uint256(_liquidity);

        uint256 price = oracleCenter.getPrice(_token0, _token1);
        if (price == 0) {
            return (false, liquidity);
        }

        uint256 priceLower = tickToPrice(
            tickLower,
            IERC20Metadata(_token0).decimals(),
            IERC20Metadata(_token1).decimals(),
            _token0,
            _token1
        );
        uint256 priceUpper = tickToPrice(
            tickUpper,
            IERC20Metadata(_token0).decimals(),
            IERC20Metadata(_token1).decimals(),
            _token0,
            _token1
        );

        (uint256 priceLowerLimit, uint256 priceUpperLimit) = getPriceLimit(price);

        if(priceLower <= priceLowerLimit && priceUpper >= priceUpperLimit) {
            return (true, liquidity);
        }
        return (false, liquidity);
    }

    // save nft
    function _addNFT(address _account, uint256 tokenId, uint256 liquidity) internal {
        require(liquidity > 0, "invalid nft liquidity");
        require(userNFTs[_account][tokenId].liquidity == 0, "NFT already added");
        userNFTs[_account][tokenId] = NFT({
            liquidity: liquidity,
            tokenId: tokenId
        });
        userNFTIds[_account].push(tokenId);
    }

    // remove nft
    function _removeNFT(address _account, uint256 tokenId) internal {
        require(userNFTs[_account][tokenId].liquidity > 0, "NFT not added");
        delete userNFTs[_account][tokenId];
        uint256[] storage nftIds = userNFTIds[_account];
        for (uint256 i = 0; i < nftIds.length; i++) {
            if (nftIds[i] == tokenId) {
                nftIds[i] = nftIds[nftIds.length - 1];
                nftIds.pop();
                break;
            }
        }
    }

    /**
     * @dev on nft received
     * @param operator operator address
     * @param from from address
     * @param tokenId tokenId of LP token
     * @param data call data
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) override external returns (bytes4) {
        require(msg.sender == lpToken, "invalid NFT contract");

        (bool isValid, uint256 liquidity) = checkNFT(tokenId);
        require(isValid, "invalid NFT");

        _addNFT(from, tokenId, liquidity);
        _deposit(from, liquidity);
        return IERC721Receiver.onERC721Received.selector;
    }

    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) private pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? Math.mulDiv(ratioX192, baseAmount, 1 << 192)
                : Math.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = Math.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? Math.mulDiv(ratioX128, baseAmount, 1 << 128)
                : Math.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    // get price by tick
    function tickToPrice(
        int24 tick,
        uint8 token0Decimals,
        uint8 token1Decimals,
        address token0,
        address token1
    ) private pure returns (uint256) {
        uint128 baseAmount = uint128(10 ** token0Decimals);
        uint256 quoteAmount = getQuoteAtTick(tick, baseAmount, token0, token1);
        return quoteAmount * 1e18 / 10 ** token1Decimals;
    }

    /**
     * @dev set price rate, only manager can call this function
     * @param _priceRate price rate
     */
    function setPriceRate(uint256 _priceRate) external onlyRole(MANAGER) {
        require(_priceRate <= 1e18, "invalid price rate");
        priceRate = _priceRate;
    }

    /**
     * @dev get price limit
     * @param price price
     * @return priceLowerLimit price lower limit
     * @return priceUpperLimit price upper limit
     */
    function getPriceLimit(uint256 price) public view returns (uint256, uint256) {
        uint256 priceRange = price * priceRate / 1e18;
        return (price - priceRange, price + priceRange);
    }

    /**
     * @dev get NFT ids
     * @param _account account address
     * @return NFT ids
     */
    function getNFTIds(address _account) external view returns (uint256[] memory) {
        return userNFTIds[_account];
    }
}
