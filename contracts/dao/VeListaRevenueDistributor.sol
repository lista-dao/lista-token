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
    address public veListaVault; // address of the veListaVault contract
    address public lista; // address of the lista token
    uint256 public vaultPercentage; // percentage of revenue to be sent to the veListaVault

    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant BOT = keccak256("BOT");
    uint256 public constant PRECISION = 10000;

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
     * @param _veListaVault the address of the veListaVault contract.
     * @param _lista the address of the lista contract.
     * @param _vaultPercentage the percentage of revenue to be sent to the veListaVault.
     */
    function initialize(
        address _admin,
        address _manager,
        address _bot,
        address _revenueReceiver,
        address _veListaVault,
        address _lista,
        uint256 _vaultPercentage
    ) public initializer {
        require(_admin != address(0), "admin cannot be zero address");
        require(_manager != address(0), "manager cannot be zero address");
        require(_bot != address(0), "bot cannot be zero address");
        require(_revenueReceiver != address(0), "revenueReceiver cannot be zero address");
        require(_veListaVault != address(0), "veListaVault cannot be zero address");
        require(_lista != address(0), "lista cannot be zero address");
        require(_vaultPercentage <= PRECISION, "vaultPercentage cannot be greater than PRECISION");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(BOT, _bot);

        revenueReceiver = _revenueReceiver;
        veListaVault = _veListaVault;
        lista = _lista;
        vaultPercentage = _vaultPercentage;
    }

    /**
     * @dev sets the revenue receiver. only callable by manager.
     * @param _revenueReceiver the address of the revenue receiver.
     */
    function setRevenueReceiver(address _revenueReceiver) public onlyRole(MANAGER) {
        require(_revenueReceiver != address(0), "revenueReceiver cannot be zero address");
        require(_revenueReceiver != revenueReceiver, "revenueReceiver is not different from the current address");
        revenueReceiver = _revenueReceiver;
    }

    /**
     * @dev sets the veListaVault. only callable by manager.
     * @param _veListaVault the address of the veListaVault.
     */
    function setVeListaVault(address _veListaVault) public onlyRole(MANAGER) {
        require(_veListaVault != address(0), "veListaVault cannot be zero address");
        require(_veListaVault != veListaVault, "veListaVault is not different from the current address");
        veListaVault = _veListaVault;
    }

    /**
     * @dev sets the vault percentage. only callable by manager.
     * @param _vaultPercentage the percentage of revenue to be sent to the veListaVault.
     */
    function setVaultPercentage(uint256 _vaultPercentage) public onlyRole(MANAGER) {
        require(_vaultPercentage <= PRECISION, "vaultPercentage cannot be greater than PRECISION");
        require(_vaultPercentage != vaultPercentage, "vaultPercentage is not different from the current percentage");
        vaultPercentage = _vaultPercentage;
    }

    /**
     * @dev distributes the revenue to the revenue receiver and the veListaVault. only callable by bot.
     */
    function distribute() public onlyRole(BOT) {
        uint256 balance = IERC20(lista).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        uint256 vaultAmount = Math.mulDiv(balance, vaultPercentage, PRECISION);
        uint256 revenueAmount = balance - vaultAmount;

        if (vaultAmount > 0) {
            IERC20(lista).safeTransfer(veListaVault, vaultAmount);
        }
        if (revenueAmount > 0) {
            IERC20(lista).safeTransfer(revenueReceiver, revenueAmount);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
