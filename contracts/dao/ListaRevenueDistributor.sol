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
  * @dev all tokens revenue (except Lista Token) from Lista project contracts will be sent to ListaRevenueDistributor
  * @dev in ListaRevenueDistributor, revenue will be distributed to autoBuybackAddress and revenueWalletAddress according to distributeRate
  */
contract ListaRevenueDistributor is Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;

    event RevenueDistributed(address indexed token, uint256 amount0, uint256 amount1);

    bytes32 public constant MANAGER = keccak256("MANAGER");

    uint128 public constant RATE_DENOMINATOR = 1e18;

    // distribute rate of revenue to autoBuybackAddress
    uint128 public distributeRate;

    address public autoBuybackAddress;

    address public revenueWalletAddress;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        address _manager,
        address _autoBuybackAddress,
        address _revenueWalletAddress,
        uint128 _distributeRate
    ) public initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_autoBuybackAddress != address(0), "autoBuybackAddress is the zero address");
        require(_revenueWalletAddress != address(0), "revenueWalletAddress is the zero address");
        require(_distributeRate <= 1e18, "too big rate number");

        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);

        autoBuybackAddress = _autoBuybackAddress;
        revenueWalletAddress = _revenueWalletAddress;
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
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        uint256 amount0 = balance * distributeRate / RATE_DENOMINATOR;
        uint256 amount1 = balance - amount0;
        if (amount0 > 0) {
            IERC20(token).safeTransfer(autoBuybackAddress, amount0);
        }
        if (amount1 > 0) {
            IERC20(token).safeTransfer(revenueWalletAddress, amount1);
        }

        emit RevenueDistributed(token, amount0, amount1);
    }

    function changeAutoBuybackAddress(address _autoBuybackAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_autoBuybackAddress != address(0), "autoBuybackAddress is the zero address");
        require(_autoBuybackAddress != autoBuybackAddress, "autoBuybackAddress is the same");
        autoBuybackAddress = _autoBuybackAddress;
    }

    function changeRevenueWalletAddress(address _revenueWalletAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_revenueWalletAddress != address(0), "revenueWalletAddress is the zero address");
        require(_revenueWalletAddress != revenueWalletAddress, "revenueWalletAddress is the same");
        revenueWalletAddress = _revenueWalletAddress;
    }

    function changeDistributeRate(uint128 _distributeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_distributeRate <= 1e18, "too big rate number");
        distributeRate = _distributeRate;
    }
}
