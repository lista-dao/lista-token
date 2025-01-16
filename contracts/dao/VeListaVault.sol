// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IVeLista.sol";

contract VeListaVault is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    address public veLista;
    address public lista;

    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant BOT = keccak256("BOT");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        address _manager,
        address _bot,
        address _veLista,
        address _lista
    ) public initializer {
        require(_admin != address(0), "admin cannot be zero address");
        require(_manager != address(0), "manager cannot be zero address");
        require(_bot != address(0), "bot cannot be zero address");
        require(_veLista != address(0), "veLista cannot be zero address");
        require(_lista != address(0), "lista cannot be zero address");

        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(BOT, _bot);

        veLista = _veLista;
        lista = _lista;
    }

    function lock() public onlyRole(BOT) {
        uint256 balance = IERC20(lista).balanceOf(address(this));
        require(balance > 0, "balance is zero");
        IERC20(lista).safeApprove(veLista, balance);
        IVeLista(veLista).lock(balance, 52, true);
    }

    function increaseLock() public onlyRole(BOT) {
        uint256 balance = IERC20(lista).balanceOf(address(this));
        require(balance > 0, "balance is zero");
        IERC20(lista).safeApprove(veLista, balance);
        IVeLista(veLista).increaseAmount(balance);
    }

    function enableAutoLock() public onlyRole(MANAGER) {
        IVeLista(veLista).enableAutoLock();
    }

    function disableAutoLock() public onlyRole(MANAGER) {
        IVeLista(veLista).disableAutoLock();
    }

    function unlock() public onlyRole(MANAGER) {
        IVeLista(veLista).claim();
    }

    function withdraw(address _to, uint256 _amount) public onlyRole(MANAGER) {
        IERC20(lista).safeTransfer(_to, _amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
