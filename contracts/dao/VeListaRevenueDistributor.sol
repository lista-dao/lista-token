// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract VeListaRevenueDistributor is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    address public revenueReceiver; // address to receive the revenue
    address public lista; // address of the lista token
    uint256 public burnPercentage; // percentage of revenue to be sent to the dead address

    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant BOT = keccak256("BOT");
    uint256 public constant PRECISION = 10000;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev initializes the contract.
     * @param _admin the address of the admin.
     * @param _manager the address of the manager.
     * @param _bot the address of the bot.
     * @param _revenueReceiver the address of the revenue receiver.
     * @param _lista the address of the lista contract.
     * @param _burnPercentage the percentage of revenue to be sent to the dead address.
     */
    function initialize(
        address _admin,
        address _manager,
        address _bot,
        address _revenueReceiver,
        address _lista,
        uint256 _burnPercentage
    ) public initializer {
        require(_admin != address(0), "admin cannot be zero address");
        require(_manager != address(0), "manager cannot be zero address");
        require(_bot != address(0), "bot cannot be zero address");
        require(_revenueReceiver != address(0), "revenueReceiver cannot be zero address");
        require(_lista != address(0), "lista cannot be zero address");
        require(_burnPercentage <= PRECISION, "burnPercentage cannot be greater than PRECISION");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(BOT, _bot);

        revenueReceiver = _revenueReceiver;
        lista = _lista;
        burnPercentage = _burnPercentage;
    }

    /**
     * @dev sets the revenue receiver. only callable by admin.
     * @param _revenueReceiver the address of the revenue receiver.
     */
    function setRevenueReceiver(address _revenueReceiver) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_revenueReceiver != address(0), "revenueReceiver cannot be zero address");
        require(_revenueReceiver != revenueReceiver, "revenueReceiver is not different from the current address");
        revenueReceiver = _revenueReceiver;
    }

    /**
     * @dev sets the burn percentage. only callable by admin.
     * @param _burnPercentage the percentage of revenue to be sent to the dead address.
     */
    function setBurnPercentage(uint256 _burnPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_burnPercentage <= PRECISION, "burnPercentage cannot be greater than PRECISION");
        require(_burnPercentage != burnPercentage, "burnPercentage is not different from the current value");
        burnPercentage = _burnPercentage;
    }

    /**
     * @dev distributes the revenue to the revenue receiver and the dead address. only callable by bot.
     */
    function distribute() public onlyRole(BOT) {
        uint256 balance = IERC20(lista).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        uint256 burnAmount = Math.mulDiv(balance, burnPercentage, PRECISION);
        uint256 revenueAmount = balance - burnAmount;

        if (burnAmount > 0) {
            IERC20(lista).safeTransfer(DEAD_ADDRESS, burnAmount);
        }
        if (revenueAmount > 0) {
            IERC20(lista).safeTransfer(revenueReceiver, revenueAmount);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
