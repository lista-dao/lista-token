pragma solidity ^0.8.10;

import "./interfaces/OracleInterface.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// todo
/**
  * @title OracleCenter
  * @dev oracle center contract, get price from oracle
 */
contract OracleCenter is OwnableUpgradeable{

    // oracle address
    OracleInterface oracle;
    // token -> fixed price
    mapping(address => uint256) public fixedPrice;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev initialize contract
      * @param _owner owner address
      */
    function initialize(address _owner, address _oracle) public initializer {
        require(_owner != address(0), "owner cannot be zero address");
        require(_oracle != address(0), "oracle cannot be zero address");
        __Ownable_init();
        transferOwnership(_owner);
        oracle = OracleInterface(_oracle);
    }

    /**
      * @dev get price of token0/token1
      * @param token0 token0 address
      * @param token1 token1 address
      * @return price of token0/token1
     */
    function getPrice(address token0, address token1) external view returns (uint256) {
        if (address(oracle) == address(0)) {
            return 0;
        }
        uint256 price0 = fixedPrice[token0];
        uint256 price1 = fixedPrice[token1];
        if (price0 == 0) {
            price0 = oracle.peek(token0);
        }

        if (price1 == 0) {
            price1 = oracle.peek(token1);
        }

        if (price0 == 0 || price1 == 0) {
            return 0;
        }

        return price0 * 1e18 / price1;
    }

    /**
      * @dev set oracle address, only owner can call this function
      * @param _oracle oracle address
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "oracle cannot be zero address");
        oracle = OracleInterface(_oracle);
    }

    /**
      * @dev set fixed price of token, only owner can call this function
      * @param token token address
      * @param price fixed price
     */
    function setFixedPrice(address token, uint256 price) external onlyOwner {
        fixedPrice[token] = price;
    }
}