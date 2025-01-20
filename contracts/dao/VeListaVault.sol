// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IVeLista.sol";
import "../interfaces/IVeListaAutoCompunder.sol";

contract VeListaVault is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    address public veLista;
    address public lista;
    address public autoCompounder;

    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant BOT = keccak256("BOT");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev onitializes the contract.
     * @param _admin the address of the admin.
     * @param _manager the address of the manager.
     * @param _bot the address of the bot.
     * @param _veLista the address of the veLista contract.
     * @param _lista the address of the lista contract.
     * @param _autoCompounder the address of the autoCompounder contract.
     */
    function initialize(
        address _admin,
        address _manager,
        address _bot,
        address _veLista,
        address _lista,
        address _autoCompounder
    ) public initializer {
        require(_admin != address(0), "admin cannot be zero address");
        require(_manager != address(0), "manager cannot be zero address");
        require(_bot != address(0), "bot cannot be zero address");
        require(_veLista != address(0), "veLista cannot be zero address");
        require(_lista != address(0), "lista cannot be zero address");
        require(_autoCompounder != address(0), "autoCompounder cannot be zero address");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(BOT, _bot);

        veLista = _veLista;
        lista = _lista;
        autoCompounder = _autoCompounder;
    }

    /**
     * @dev locks the entire balance of the lista token. only callable by bot.
     */
    function lock() external onlyRole(BOT) {
        uint256 balance = IERC20(lista).balanceOf(address(this));
        require(balance > 0, "balance is zero");
        IERC20(lista).safeIncreaseAllowance(veLista, balance);
        IVeLista(veLista).lock(balance, 52, true);
    }

    /**
     * @dev increases the lock amount. only callable by bot.
     */
    function increaseLock() external onlyRole(BOT) {
        uint256 balance = IERC20(lista).balanceOf(address(this));
        require(balance > 0, "balance is zero");
        IERC20(lista).safeIncreaseAllowance(veLista, balance);
        IVeLista(veLista).increaseAmount(balance);
    }

    /**
     * @dev enable auto lock. only callable by manager.
     */
    function enableAutoLock() external onlyRole(MANAGER) {
        IVeLista(veLista).enableAutoLock();
    }

    /**
     * @dev disable auto lock. only callable by manager.
     */
    function disableAutoLock() external onlyRole(MANAGER) {
        IVeLista(veLista).disableAutoLock();
    }

    /**
     * @dev claim expired lista token. only callable by manager.
     */
    function unlock() external onlyRole(MANAGER) {
        IVeLista(veLista).claim();
    }

    /**
     * @dev claim unexpired lista token with penalty. only callable by manager.
     */
    function unlockWithPenalty() external onlyRole(MANAGER) {
        IVeLista(veLista).earlyClaim();
    }

    /**
     * @dev withdraws the entire balance of the lista token to the given address. only callable by manager.
     * @param _to the address to withdraw to.
     */
    function withdraw(address _to, uint256 _amount) external onlyRole(MANAGER) {
        IERC20(lista).safeTransfer(_to, _amount);
    }

    /**
     * @dev enable auto compound. only callable by manager.
     */
    function enableAutoCompound() external onlyRole(MANAGER) {
        require(!IVeListaAutoCompounder(autoCompounder).isAutoCompoundEnabled(address(this)), "auto compound is enabled");
        IVeListaAutoCompounder(autoCompounder).enableAutoCompound();
    }

    /**
     * @dev disable auto compound. only callable by manager.
     */
    function disableAutoCompound() external onlyRole(MANAGER) {
        require(IVeListaAutoCompounder(autoCompounder).isAutoCompoundEnabled(address(this)), "auto compound is disabled");
        IVeListaAutoCompounder(autoCompounder).disableAutoCompound();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
