// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
  * @title ListaRevenueDistributor
  * @dev lista revenue tokens distributor
  * @dev all tokens revenue (including Lista Token) from Lista project contracts will be sent to ListaRevenueDistributor
  * @dev in ListaRevenueDistributor, non-ListaToken revenue will be distributed to autoBuybackAddress and revenueWalletAddress according to distributeRate
  * @dev the distributeRate part of ListaToken revenue will be sent to listaDistributeToAddress instead of autoBuybackAddress
  */
contract ListaRevenueDistributor is Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;

    struct Cost {
        address token;
        address costTo; // cost will be sent to costTo address
        uint256 amount; // cost amount
    }

    event RevenueDistributed(address indexed token, uint256 amount0, uint256 amount1);
    event RevenueDistributedWithCost(
        address indexed token,
        uint256 amount0,
        uint256 amount1,
        uint256 cost,
        uint256 targetCost,
        address costTo
    );

    event AddressChanged(uint128 addressType, address newAddress);

    event RateChanged(uint128 rate);

    event TokenChanged(address token, bool isAdd);

    event CostToAddressChanged(address costToAddress, bool isAdd);

    bytes32 public constant MANAGER = keccak256("MANAGER");

    uint128 public constant RATE_DENOMINATOR = 1e18;

    mapping(address => bool) public tokenWhitelist;

    // distribute rate of revenue to autoBuybackAddress/listaDistributeToAddress
    uint128 public distributeRate;

    address public listaTokenAddress;

    address public autoBuybackAddress;

    address public revenueWalletAddress;

    // distributeRate part of lista token revenue will be sent to this address instead of autoBuybackAddress
    address public listaDistributeToAddress;

    // added on 2024-10-21
    address public tokenCostToAddress;

    // cost can only be sent to whitelisted address
    mapping(address => bool) public costToWhitelist;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        address _manager,
        address _listaTokenAddress,
        address _autoBuybackAddress,
        address _revenueWalletAddress,
        address _listaDistributeToAddress,
        uint128 _distributeRate
    ) public initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_listaTokenAddress != address(0), "listaTokenAddress is the zero address");
        require(_autoBuybackAddress != address(0), "autoBuybackAddress is the zero address");
        require(_revenueWalletAddress != address(0), "revenueWalletAddress is the zero address");
        require(_listaDistributeToAddress != address(0), "listaDistributeToAddress is the zero address");
        require(_distributeRate <= 1e18, "too big rate number");

        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);

        listaTokenAddress = _listaTokenAddress;
        autoBuybackAddress = _autoBuybackAddress;
        revenueWalletAddress = _revenueWalletAddress;
        listaDistributeToAddress = _listaDistributeToAddress;
        distributeRate = _distributeRate;
    }

    /**
     * @dev distribute tokens to autoBuybackAddress and revenueWalletAddress according to distributeRate
     * @param tokens, tokens to distribute
     */
    function distributeTokens(address[] memory tokens) external onlyRole(MANAGER) {
        for (uint256 i = 0; i < tokens.length; i++) {
            _distributeToken(tokens[i]);
        }
    }

    function _distributeToken(address token) private {
        require(tokenWhitelist[token], "token not whitelisted");

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        uint256 amount0 = balance * distributeRate / RATE_DENOMINATOR;
        uint256 amount1 = balance - amount0;
        if (amount0 > 0) {
            if (token == listaTokenAddress) {
                // lista should skip autoBuyback process
                IERC20(token).safeTransfer(listaDistributeToAddress, amount0);
            } else {
                IERC20(token).safeTransfer(autoBuybackAddress, amount0);
            }
        }
        if (amount1 > 0) {
            IERC20(token).safeTransfer(revenueWalletAddress, amount1);
        }

        emit RevenueDistributed(token, amount0, amount1);
    }

    /**
     * @dev distribute tokens to autoBuybackAddress and revenueWalletAddress
     *      according to distributeRate and cost amount will be sent to specified costTo address
     *
     * @param costs, array of Cost struct
     */
    function distributeWithCosts(Cost[] memory costs) external onlyRole(MANAGER) {
        require(costs.length > 0, "invalid costs length");
        for (uint256 i = 0; i < costs.length; i++) {
            _distributeTokenWithCost(costs[i].token, costs[i].amount, costs[i].costTo);
        }
    }

    /**
     * @dev distribute tokens to autoBuybackAddress and revenueWalletAddress
     *      according to distributeRate and cost amount will be sent to tokenCostToAddress
     *
     * @param tokens, token to distribute
     * @param costs, amount directly to cost address
     */
    function distributeTokensWithCost(address[] memory tokens, uint256[] memory costs)
        external
        onlyRole(MANAGER)
    {
        require(tokens.length > 0 && tokens.length == costs.length, "invalid tokens and costs length");
        for (uint256 i = 0; i < tokens.length; i++) {
            _distributeTokenWithCost(tokens[i], costs[i], tokenCostToAddress);
        }
    }

    function _distributeTokenWithCost(address token, uint256 cost, address costTo) internal {
        require(tokenWhitelist[token], "token not whitelisted");
        require(costTo == tokenCostToAddress || costToWhitelist[costTo], "costTo address not whitelisted");

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        if (balance <= cost) {
            IERC20(token).safeTransfer(costTo, balance);
            emit RevenueDistributedWithCost(token, 0, 0, balance, cost, costTo);
        } else {
            uint256 available = balance - cost;
            uint256 amount0 = available * distributeRate / RATE_DENOMINATOR;
            uint256 amount1 = available - amount0;
            if (amount0 > 0) {
                if (token == listaTokenAddress) {
                    // lista should skip autoBuyback process
                    IERC20(token).safeTransfer(listaDistributeToAddress, amount0);
                } else {
                    IERC20(token).safeTransfer(autoBuybackAddress, amount0);
                }

            }
            if (amount1 > 0) {
                IERC20(token).safeTransfer(revenueWalletAddress, amount1);
            }
            if (cost > 0) {
                IERC20(token).safeTransfer(costTo, cost);
            }

            emit RevenueDistributedWithCost(token, amount0, amount1, cost, cost, costTo);
        }
    }

    function changeAutoBuybackAddress(address _autoBuybackAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_autoBuybackAddress != address(0), "autoBuybackAddress is the zero address");
        require(_autoBuybackAddress != autoBuybackAddress, "autoBuybackAddress is the same");
        autoBuybackAddress = _autoBuybackAddress;

        emit AddressChanged(1, autoBuybackAddress);
    }

    function changeRevenueWalletAddress(address _revenueWalletAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_revenueWalletAddress != address(0), "revenueWalletAddress is the zero address");
        require(_revenueWalletAddress != revenueWalletAddress, "revenueWalletAddress is the same");
        revenueWalletAddress = _revenueWalletAddress;

        emit AddressChanged(2, revenueWalletAddress);
    }

    function changeListaDistributeToAddress(address _listaDistributeToAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_listaDistributeToAddress != address(0), "listaDistributeToAddress is the zero address");
        require(_listaDistributeToAddress != listaDistributeToAddress, "listaDistributeToAddress is the same");
        listaDistributeToAddress = _listaDistributeToAddress;

        emit AddressChanged(3, listaDistributeToAddress);
    }

    function changeDistributeRate(uint128 _distributeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_distributeRate <= 1e18, "too big rate number");
        distributeRate = _distributeRate;

        emit RateChanged(distributeRate);
    }

    function addTokensToWhitelist(address[] memory _tokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_tokens.length > 0, "invalid tokens length");

        for (uint idx = 0; idx < _tokens.length; idx++) {
            address _token = _tokens[idx];
            tokenWhitelist[_token] = true;

            emit TokenChanged(_token, true);
        }
    }

    function removeTokensFromWhitelist(address[] memory _tokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_tokens.length > 0, "invalid tokens length");

        for (uint idx = 0; idx < _tokens.length; idx++) {
            address _token = _tokens[idx];
            delete tokenWhitelist[_token];

            emit TokenChanged(_token, false);
        }
    }

    function changeCostToAddress(address _costToAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_costToAddress != address(0), "costToAddress is the zero address");
        require(_costToAddress != tokenCostToAddress, "costToAddress is the same");

        tokenCostToAddress = _costToAddress;
        emit CostToAddressChanged(_costToAddress, true);
    }

    /**
     * @dev whitelist costToAddress
     * @param _costToAddress costToAddress to whitelist
     */
    function whitelistCostToAddress(address _costToAddress) external onlyRole(MANAGER) {
        require(_costToAddress != address(0), "costToAddress is the zero address");
        require(!costToWhitelist[_costToAddress], "costToAddress already whitelisted");

        costToWhitelist[_costToAddress] = true;
        emit CostToAddressChanged(_costToAddress, true);
    }

    /**
     * @dev remove costToAddress from whitelist
     * @param _costToAddress costToAddress to remove from whitelist
     */
    function removeCostToFromWhitelist(address _costToAddress) external onlyRole(MANAGER) {
        require(_costToAddress != address(0), "costToAddress is the zero address");
        require(costToWhitelist[_costToAddress], "costToAddress not whitelisted");

        delete costToWhitelist[_costToAddress];
        emit CostToAddressChanged(_costToAddress, false);
    }
}
