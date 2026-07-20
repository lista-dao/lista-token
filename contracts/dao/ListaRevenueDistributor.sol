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
 * @custom:oz-upgrades-from contracts/dao/historical/ListaRevenueDistributorOld.sol:ListaRevenueDistributorOld
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

  event EmergencyWithdrawn(address indexed token, address indexed to, uint256 amount);

  bytes32 public constant MANAGER = keccak256("MANAGER");
  bytes32 public constant EMERGENCY_WITHDRAWER = keccak256("EMERGENCY_WITHDRAWER");

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

    // Determine the effective target for amount0
    address target0 = token == listaTokenAddress ? listaDistributeToAddress : autoBuybackAddress;

    // Early return: no targets configured, nothing to distribute
    if (target0 == address(0) && revenueWalletAddress == address(0)) {
      return;
    }

    uint256 amount0 = (balance * distributeRate) / RATE_DENOMINATOR;
    uint256 amount1 = balance - amount0;

    uint256 actualAmount0;
    uint256 actualAmount1;

    if (amount0 > 0 && target0 != address(0)) {
      IERC20(token).safeTransfer(target0, amount0);
      actualAmount0 = amount0;
    }
    if (amount1 > 0 && revenueWalletAddress != address(0)) {
      IERC20(token).safeTransfer(revenueWalletAddress, amount1);
      actualAmount1 = amount1;
    }

    emit RevenueDistributed(token, actualAmount0, actualAmount1);
  }

  /**
   * @dev distribute tokens to autoBuybackAddress and revenueWalletAddress
   *      according to distributeRate and cost amount will be sent to specified costTo address
   *
   * @param costs, array of Cost struct
   * @param tokens, tokens to distribute
   */
  function distributeWithCosts(Cost[] memory costs, address[] memory tokens) external onlyRole(MANAGER) {
    require(costs.length > 0, "invalid costs length");
    require(tokens.length > 0, "invalid tokens length");

    // loop to process costs first
    for (uint256 i = 0; i < costs.length; ++i) {
      _processCost(costs[i]);
    }

    // loop to distribute tokens according to ratio
    for (uint256 i = 0; i < tokens.length; ++i) {
      _distributeToken(tokens[i]);
    }
  }

  function _processCost(Cost memory cost) private {
    address costToken = cost.token;
    uint256 costAmount = cost.amount;
    address costTo = cost.costTo;
    require(tokenWhitelist[costToken], "cost token not whitelisted");
    require(costTo == tokenCostToAddress || costToWhitelist[costTo], "costTo address not whitelisted");
    require(costAmount > 0, "cost amount should be greater than 0");

    uint256 balance = IERC20(costToken).balanceOf(address(this));
    if (balance == 0) return; // return if no balance to process

    uint256 transferAmount = Math.min(balance, costAmount);
    IERC20(costToken).safeTransfer(costTo, transferAmount);
    emit RevenueDistributedWithCost(costToken, 0, 0, balance, costAmount, costTo);
  }

  /**
   * @dev distribute tokens to autoBuybackAddress and revenueWalletAddress
   *      according to distributeRate and cost amount will be sent to tokenCostToAddress
   *
   * @param tokens, token to distribute
   * @param costs, amount directly to cost address
   */
  function distributeTokensWithCost(address[] memory tokens, uint256[] memory costs) external onlyRole(MANAGER) {
    require(tokens.length > 0 && tokens.length == costs.length, "invalid tokens and costs length");
    for (uint256 i = 0; i < tokens.length; i++) {
      _distributeTokenWithCost(tokens[i], costs[i]);
    }
  }

  function _distributeTokenWithCost(address token, uint256 cost) internal {
    require(tokenWhitelist[token], "token not whitelisted");
    require(tokenCostToAddress != address(0), "reserve address not set");

    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance == 0) {
      return;
    }

    if (balance <= cost) {
      IERC20(token).safeTransfer(tokenCostToAddress, balance);
      emit RevenueDistributedWithCost(token, 0, 0, balance, cost, tokenCostToAddress);
    } else {
      uint256 available = balance - cost;
      uint256 amount0 = (available * distributeRate) / RATE_DENOMINATOR;
      uint256 amount1 = available - amount0;

      // Determine the effective target for amount0
      address target0 = token == listaTokenAddress ? listaDistributeToAddress : autoBuybackAddress;

      uint256 actualAmount0;
      uint256 actualAmount1;

      if (amount0 > 0 && target0 != address(0)) {
        IERC20(token).safeTransfer(target0, amount0);
        actualAmount0 = amount0;
      }
      if (amount1 > 0 && revenueWalletAddress != address(0)) {
        IERC20(token).safeTransfer(revenueWalletAddress, amount1);
        actualAmount1 = amount1;
      }
      if (cost > 0) {
        IERC20(token).safeTransfer(tokenCostToAddress, cost);
      }

      emit RevenueDistributedWithCost(token, actualAmount0, actualAmount1, cost, cost, tokenCostToAddress);
    }
  }

  function changeAutoBuybackAddress(address _autoBuybackAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_autoBuybackAddress != autoBuybackAddress, "autoBuybackAddress is the same");
    autoBuybackAddress = _autoBuybackAddress;

    emit AddressChanged(1, autoBuybackAddress);
  }

  function changeRevenueWalletAddress(address _revenueWalletAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_revenueWalletAddress != revenueWalletAddress, "revenueWalletAddress is the same");
    revenueWalletAddress = _revenueWalletAddress;

    emit AddressChanged(2, revenueWalletAddress);
  }

  function changeListaDistributeToAddress(address _listaDistributeToAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
  function whitelistCostToAddress(address _costToAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_costToAddress != address(0), "costToAddress is the zero address");
    require(!costToWhitelist[_costToAddress], "costToAddress already whitelisted");

    costToWhitelist[_costToAddress] = true;
    emit CostToAddressChanged(_costToAddress, true);
  }

  /**
   * @dev remove costToAddress from whitelist
   * @param _costToAddress costToAddress to remove from whitelist
   */
  function removeCostToFromWhitelist(address _costToAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_costToAddress != address(0), "costToAddress is the zero address");
    require(costToWhitelist[_costToAddress], "costToAddress not whitelisted");

    delete costToWhitelist[_costToAddress];
    emit CostToAddressChanged(_costToAddress, false);
  }

  /**
   * @dev emergency withdraw tokens from contract
   * @param _token token address
   * @param _to receiver address
   * @param _amount token amount
   */
  function emergencyWithdraw(address _token, address _to, uint256 _amount) external onlyRole(EMERGENCY_WITHDRAWER) {
    require(_to != address(0), "to is the zero address");
    require(_amount > 0, "Invalid amount");
    IERC20(_token).safeTransfer(_to, _amount);
    emit EmergencyWithdrawn(_token, _to, _amount);
  }
}
