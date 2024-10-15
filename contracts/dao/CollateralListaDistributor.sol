// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CommonListaDistributor.sol";


contract CollateralListaDistributor is CommonListaDistributor {

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
        vault = IVault(_vault);
        lpToken = _lpToken;
    }

    /**
    * @notice take snapshot of user's activity
    * @dev only the Interaction contract(Manager Role) can call this function,
    *      it will do the checking in the Interaction Contract,
    *      so there is no need to add checking here
    * @param _token collateral token address
    * @param _user user address
    * @param _ink user's latest collateral amount
    */
    function takeSnapshot(address _token, address _user, uint256 _ink) onlyRole(MANAGER) external {
        // For this collateral, if the latest _ink is larger than the previous one
        // call _deposit(_user, ink diff.), otherwise call _withdraw(_user, ink diff.)
        uint256 balance = balanceOf[_user];
        if (_ink > balance) {
            _deposit(_user, _ink - balance);
        } else {
            _withdraw(_user, balance - _ink);
        }
    }
}
