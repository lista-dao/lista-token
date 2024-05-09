pragma solidity ^0.8.10;

import "./CommonListaDistributor.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
  * @title ERC20LpListaDistributor
  * @dev lista token stake and distributor for erc20 LP token
 */
contract ERC20LpListaDistributor is CommonListaDistributor, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev initialize contract
      * @param _admin admin address
      * @param _manager manager address
      * @param _lpToken lp token address
      */
    function initialize(
        address _admin,
        address _manager,
        address _vault,
        address _lpToken
    ) external initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_lpToken != address(0), "lp token is the zero address");
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(VAULT, _vault);
        lpToken = _lpToken;
        vault = IVault(_vault);
        name = string.concat("Lista-", IERC20Metadata(_lpToken).name());
        symbol = string.concat("Lista LP ", IERC20Metadata(_lpToken).symbol(), " Distributor");
    }

    /**
     * @dev deposit LP token to get rewards
     * @param amount amount of LP token
     */
    function deposit(uint256 amount) nonReentrant external {
        require(amount > 0, "Cannot deposit zero");
        _deposit(msg.sender, amount);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev withdraw LP token
     * @param amount amount of LP token
     */
    function withdraw(uint256 amount) nonReentrant external {
        require(amount > 0, "Cannot withdraw zero");
        _withdraw(msg.sender, amount);
        IERC20(lpToken).safeTransfer(msg.sender, amount);
    }
}