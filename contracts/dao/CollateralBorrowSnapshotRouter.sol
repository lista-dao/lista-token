// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IBorrowLisUSDListaDistributor.sol";
import "./interfaces/ICollateralDistributor.sol";

/**
 */
contract CollateralBorrowSnapshotRouter is Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;

    event CollateralDistributorChanged(address indexed distributor, address indexed token, bool isAdd);
    event BorrowDistributorChanged(address indexed distributor, address indexed token, bool isAdd);

    bytes32 public constant MANAGER = keccak256("MANAGER");

    mapping(address => ICollateralDistributor) public collateralDistributors;

    // To Be Deprecated
    IBorrowLisUSDListaDistributor public borrowLisUSDListaDistributor;

    mapping(address => IBorrowDistributor) public borrowDistributors;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @dev Initialize contract
    * @param _admin admin address
    * @param _manager manager address
    * @param _borrowLisUSDListaDistributor address of BorrowLisUSDListaDistributor
    * @param _collateralTokens address of collateral tokens
    * @param _collateralDistributors address of collateral distributors
    */
    function initialize(
        address _admin,
        address _manager,
        address _borrowLisUSDListaDistributor,
        address[] memory _collateralTokens,
        address[] memory _collateralDistributors
    ) external initializer {
        require(_admin != address(0), "admin cannot be a zero address");
        require(_manager != address(0), "manager cannot be a zero address");
        require(_borrowLisUSDListaDistributor != address(0), "borrowLisUSDListaDistributor cannot be a zero address");
        require(_collateralTokens.length == _collateralDistributors.length, "collateralTokens and collateralDistributors length mismatch");

        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);

        borrowLisUSDListaDistributor = IBorrowLisUSDListaDistributor(_borrowLisUSDListaDistributor);

        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            require(_collateralDistributors[i] != address(0), "collateralDistributor cannot be a zero address");
            collateralDistributors[_collateralTokens[i]] = ICollateralDistributor(_collateralDistributors[i]);
        }
    }

    /**
     * @dev take snapshot of user's activity
     * only the Interaction contract(Manager Role) can call this function
     * @param _collateralToken token address
     * @param _user user address
     * @param _ink user's collateral amount
     * @param _art user's borrow amount
     * @param _inkUpdated whether user's collateral amount is updated
     * @param _artUpdated whether user's borrow amount is updated
     */
    function takeSnapshot(
        address _collateralToken, address _user,
        uint256 _ink, uint256 _art,
        bool _inkUpdated, bool _artUpdated
    ) onlyRole(MANAGER) external {
        if (_inkUpdated && address(collateralDistributors[_collateralToken]) != address(0)) {
            collateralDistributors[_collateralToken].takeSnapshot(_collateralToken, _user, _ink);
        }

        if (_artUpdated && address(borrowDistributors[_collateralToken]) != address(0)) {
            borrowDistributors[_collateralToken].takeSnapshot(_collateralToken, _user, _art);
            // remove old snapshottor
            // borrowLisUSDListaDistributor.takeSnapshot(_collateralToken, _user, _art);
        }
    }

    /**
     * @dev take snapshot of user's activity, to make router compatible with existing borrowLisUSDListaDistributor
     * only the Interaction contract(Manager Role) can call this function
     * @param _collateralToken token address
     * @param _user user address
     * @param _art user's borrow amount
     */
    function takeSnapshot(
        address _collateralToken, address _user, uint256 _art
    ) onlyRole(MANAGER) external {
        borrowDistributors[_collateralToken].takeSnapshot(_collateralToken, _user, _art);
        // remove old snapshottor
        // borrowLisUSDListaDistributor.takeSnapshot(_collateralToken, _user, _art);
    }

    /**
     * @dev set new collateral distributor
     */
    function setCollateralDistributor(address _collateralToken, address _collateralDistributor) onlyRole(DEFAULT_ADMIN_ROLE) external {
        require(_collateralDistributor != address(0), "collateralDistributor cannot be a zero address");
        require(_collateralDistributor != address(collateralDistributors[_collateralToken]), "collateralDistributor already set");

        collateralDistributors[_collateralToken] = ICollateralDistributor(_collateralDistributor);
        emit CollateralDistributorChanged(_collateralDistributor, _collateralToken, true);
    }

    /**
     * @dev set new borrow distributor
     */
    function setBorrowDistributor(address _collateralToken, address _borrowDistributor) onlyRole(DEFAULT_ADMIN_ROLE) external {
        require(_borrowDistributor != address(0), "borrowDistributor cannot be a zero address");
        require(_borrowDistributor != address(borrowDistributors[_collateralToken]), "borrowDistributor already set");

        borrowDistributors[_collateralToken] = IBorrowDistributor(_borrowDistributor);
        emit BorrowDistributorChanged(_borrowDistributor, _collateralToken, true);
    }

    /**
     * @dev remove collateral distributor
     */
    function unsetCollateralDistributor(address _collateralToken) onlyRole(DEFAULT_ADMIN_ROLE) external {
        address existingDistributor = address(collateralDistributors[_collateralToken]);
        require(existingDistributor != address(0), "collateralDistributor not set");

        delete collateralDistributors[_collateralToken];
        emit CollateralDistributorChanged(existingDistributor, _collateralToken, false);
    }

    /*
     * @dev remove borrow distributor
     */
    function unsetBorrowDistributor(address _collateralToken) onlyRole(DEFAULT_ADMIN_ROLE) external {
        address existingDistributor = address(borrowDistributors[_collateralToken]);
        require(existingDistributor != address(0), "borrowDistributor not set");

        delete borrowDistributors[_collateralToken];
        emit BorrowDistributorChanged(existingDistributor, _collateralToken, false);
    }
}
