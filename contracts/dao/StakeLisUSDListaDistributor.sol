// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CommonListaDistributor.sol";

/**
  * @title StakeLisUSDListaDistributor
  * @dev This contract inherits from CommonListaDistributor stores user's reward data when an user stakes LisUSD
  */
contract StakeLisUSDListaDistributor is CommonListaDistributor {

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
    * @dev Initialize contract
    * @param _name lp token name
    * @param _symbol lp token symbol
    * @param _admin admin address
    * @param _manager manager address
    * @param _vault vault address
    * @param _lpToken lp token address
    */
  function initialize(
    string memory _name,
    string memory _symbol,
    address _admin,
    address _manager,
    address _vault,
    address _lpToken
  ) external initializer {
    require(_admin != address(0), "admin cannot be a zero address");
    require(_manager != address(0), "manager cannot be a zero address");
    require(_lpToken != address(0), "lp token cannot be a zero address");
    require(_vault != address(0), "vault is the zero address");
    __AccessControl_init();
    __Pausable_init();

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(MANAGER, _manager);
    _setupRole(VAULT, _vault);
    name = _name;
    symbol = _symbol;
    lpToken = _lpToken;
    vault = IVault(_vault);
  }

  /**
    * @dev take snapshot when user stakes/unstakes LisUSD
    * @param user user address
    * @param balance user's latest balance of staked LisUSD
    */
  function takeSnapshot(address user, uint256 balance) onlyRole(MANAGER) external {
    // check user's balanceOf value of that collateral
    // update user's balanceOf, _deposit() if diff > 0
    // otherwise _withdraw()
    if (balance > balanceOf[user]) {
      _deposit(user, balance - balanceOf[user]);
    } else {
      _withdraw(user, balanceOf[user] - balance);
    }
  }
}
