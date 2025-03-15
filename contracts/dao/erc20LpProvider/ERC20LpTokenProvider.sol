// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IVault } from "../interfaces/IVault.sol";
import { ILpToken } from "../interfaces/ILpToken.sol";
import { IERC20TokenProvider } from "../interfaces/IERC20TokenProvider.sol";
import { IERC20LpProvidableDistributor } from "../interfaces/IERC20LpProvidableDistributor.sol";

/**
 * @title ERC20LpTokenProvider
 * @dev User gets ERC20-LP token from PancakeSwap or Thena by providing liquidity to the pool (mainly stableSwap or V2),
 *      then user can stake those ERC20-LP to ListaDistributor through TokenProvider.
 *
 *      1. ERC20-LP = X amount of token0 + Y amount of token1
 *      2. user stakes ERC20-LP
 *      3. say token1:clisXXX = 1:exchangeRate
 *      4. We can calculate how mush token1 worth of token0,
 *         so we can get the total amount of token1 in ERC20-LP
 *      5. user gets clisXXX as proof of staking ERC20-LP
 *
 *      In short: Staked ERC20-LP
 *                   > x token0 + y token1
 *                      > z token1
 *                          > clisXXX (token1:clisXXX = 1:exchangeRate)
 */
contract ERC20LpTokenProvider is IERC20TokenProvider,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    uint128 public constant RATE_DENOMINATOR = 1e18;
    // manager role
    bytes32 public constant MANAGER = keccak256("MANAGER");
    // pause role
    bytes32 public constant PAUSER = keccak256("PAUSER");

    /* ------------------ Variables ------------------ */
    // the ERC20-LP Token such as PancakeSwap StablePool LP Token
    address public token;
    // User will get this LP token as proof of staking ERC20-LP, e.g clisXXX
    ILpToken public lpToken;
    // the ERC20-LP Lista distributor that binds with this provider
    IERC20LpProvidableDistributor public lpProvidableDistributor;
    // @dev delegatee fully holds user's lpToken, NO PARTIAL delegation
    // account > delegatee
    mapping(address => address) public delegation;
    // user account > total amount of lpToken minted to user
    mapping(address => uint256) public userLp;
    // token to lpToken exchange rate
    uint128 public exchangeRate;
    // rate of lpToken to user when deposit
    uint128 public userLpRate;
    // should be a mpc wallet address
    address public lpReserveAddress;
    // user account > sum reserved lpToken
    mapping(address => uint256) public userReservedLp;
    // total reserved lpToken
    uint256 public totalReservedLp;

    /* ------------------ Events ------------------ */
    event UserLpRebalanced(address account, uint256 userLp, uint256 reservedLp);
    event ExchangeRateChanged(uint128 rate);
    event UserLpRateChanged(uint128 rate);
    event LpReserveAddressChanged(address newAddress);
    event Deposit(address indexed account, uint256 amount, uint256 lPAmount);
    event Withdrawal(address indexed owner, uint256 amount);
    event ChangeDelegateTo(address account, address oldDelegatee, address newDelegatee);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @dev initialize function
    * @param _admin admin role address
    * @param _manager manager role address
    * @param _pauser pauser role address
    * @param _lpToken LP token address
    * @param _token ERC20-LP token address
    * @param _lpProvidableDistributor LP token distributor address
    * @param _lpReserveAddress LP token reserve address
    * @param _exchangeRate token to lpToken exchange rate
    * @param _userLpRate user lpToken rate
    */
    function initialize(
        address _admin,
        address _manager,
        address _pauser,
        address _lpToken,
        address _token,
        address _lpProvidableDistributor,
        address _lpReserveAddress,
        uint128 _exchangeRate,
        uint128 _userLpRate
    ) public initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_pauser != address(0), "pauser is the zero address");
        require(_lpToken != address(0), "lpToken is the zero address");
        require(_token != address(0), "token is the zero address");
        require(_lpProvidableDistributor != address(0), "_lpProvidableDistributor is the zero address");
        require(_lpReserveAddress != address(0), "lpReserveAddress is the zero address");
        require(_exchangeRate > 0, "exchangeRate invalid");
        require(_userLpRate <= 1e18, "too big rate number");

        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();

        // grant essential roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER, _manager);
        _grantRole(PAUSER, _pauser);

        token = _token;
        lpToken = ILpToken(_lpToken);
        lpProvidableDistributor = IERC20LpProvidableDistributor(_lpProvidableDistributor);
        lpReserveAddress = _lpReserveAddress;
        exchangeRate = _exchangeRate;
        userLpRate = _userLpRate;

        // approve max allowance in advance to save gas
        IERC20(token).approve(_lpProvidableDistributor, type(uint256).max);
    }


    /* ------------------ User deposit and withdrawal ------------------ */
    /**
    * @dev deposit given amount of token to provider
    *      an amount of lp token with respect to a ratio will be mint to caller's address
    * @param _amount amount to deposit
    */
    function deposit(uint256 _amount)
    external
    whenNotPaused
    nonReentrant
    returns (uint256)
    {
        // force delegatee to be msg.sender
        return _deposit(_amount, msg.sender, msg.sender);
    }

    /**
    * deposit given amount of token to provider
    * given amount lp token will be mint to delegateTo
    * @param _amount amount to deposit
    * @param _delegateTo target address of lp tokens
    */
    function deposit(uint256 _amount, address _delegateTo)
    external
    whenNotPaused
    nonReentrant
    returns (uint256)
    {
        require(_delegateTo != address(0), "delegateTo cannot be zero address");
        return _deposit(_amount, msg.sender, _delegateTo);
    }

    /**
     * @dev withdraw given amount of token
     *      lp token will be burned from caller's address
     * @param _amount amount to release
     */
    function withdraw(uint256 _amount)
    external
    whenNotPaused
    nonReentrant
    returns (uint256)
    {
        require(_amount > 0, "zero withdrawal amount");
        // withdraw from distributor
        lpProvidableDistributor.withdrawFor(_amount, msg.sender);
        // rebalance user's lpToken
        (,uint256 latestLpBalance) = _rebalanceUserLp(msg.sender);

        emit Withdrawal(msg.sender, _amount);
        return latestLpBalance;
    }

    /**
    * delegate all collateral tokens to given address
    * @param newDelegatee new target address of collateral tokens
    */
    function delegateAllTo(address newDelegatee)
    external
    whenNotPaused
    nonReentrant
    {
        require(
            newDelegatee != address(0) &&
            newDelegatee != delegation[msg.sender],
            "newDelegatee cannot be zero address or same as current delegatee"
        );
        // current delegatee
        address oldDelegatee = delegation[msg.sender];
        // current lp amount
        uint256 lpAmount = userLp[msg.sender];
        // burn all lpToken from account or delegatee
        _safeBurnLp(oldDelegatee, lpAmount);
        // mint all lpToken to new delegatee
        lpToken.mint(newDelegatee, lpAmount);
        // update delegatee record
        delegation[msg.sender] = newDelegatee;

        emit ChangeDelegateTo(msg.sender, oldDelegatee, newDelegatee);
    }


    /* ----------------------- Lp Token Re-balancing ----------------------- */
    /**
    * @dev sync user's lpToken balance to retain a consistent ratio with token balance
    * @param _account user address to sync
    */
    function syncUserLp(address _account) external {
        (bool rebalanced,) = _rebalanceUserLp(_account);
        require(rebalanced, "already synced");
    }

    /**
    * @dev sync multiple user's lpToken balance to retain a consistent ratio with token balance
    * @param _accounts user address to sync
    */
    function bulkSyncUserLp(address[] calldata _accounts) external {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _rebalanceUserLp(_accounts[i]);
        }
    }

    /**
     * check if user lp token is synced with token balance
     * @param account lp token owner
     */
    function isUserLpSynced(address account) external view returns (bool) {
        uint256 userStakedTokenAmount = lpProvidableDistributor.getUserLpTotalValueInQuoteToken(account);
        uint256 newTotalLp = userStakedTokenAmount * exchangeRate / RATE_DENOMINATOR;
        uint256 newUserLp = userStakedTokenAmount * userLpRate / RATE_DENOMINATOR;
        uint256 newReservedLp = newTotalLp - newUserLp;

        return userLp[account] == newUserLp && userReservedLp[account] == newReservedLp;
    }


    /* ----------------------- Internal/Private functions  ----------------------- */

    /**
    * @dev deposit given amount of token to provider
    * @param amount amount to deposit
    * @param account user address
    * @param holder holder address a.k.a the delegatee
    */
    function _deposit(uint256 amount, address account, address holder) private returns (uint256) {
        require(amount > 0, "zero deposit amount");
        // transfer token from user to this contract
        IERC20(token).safeTransferFrom(account, address(this), amount);
        // get current delegatee
        address oldDelegatee = delegation[account];
        // burn all lpToken from old delegatee
        if (oldDelegatee != holder && oldDelegatee != address(0)) {
            _safeBurnLp(oldDelegatee, userLp[account]);
        }
        // update delegatee
        delegation[account] = holder;
        // deposit to distributor
        lpProvidableDistributor.depositFor(amount, account);
        // rebalance user's lpToken
        (,uint256 latestLpBalance) = _rebalanceUserLp(account);

        emit Deposit(account, amount, latestLpBalance);
        return latestLpBalance;
    }

    /**
     * @dev mint/burn lpToken to sync user's lpToken with token balance
     * @param account user address to sync
     */
    function _rebalanceUserLp(address account) internal returns (bool, uint256) {

        // @dev this variable represent the latest amount of lpToken that user should have
        //      user stakes LP(e.g. PCS stableSwap, Thena LP) which the LP binds with a certain amount of token0 and token1
        uint256 userStakedTokenAmount = lpProvidableDistributor.getUserLpTotalValueInQuoteToken(account);

        // ---- [1] Estimated LP value
        // Total LP(Lista + User + Reserve)
        uint256 newTotalLp = userStakedTokenAmount * exchangeRate / RATE_DENOMINATOR;
        // User's LP
        uint256 newUserLp = userStakedTokenAmount * userLpRate / RATE_DENOMINATOR;
        // Reserve's LP
        uint256 newReservedLp = newTotalLp - newUserLp;

        // ---- [2] Current user LP and reserved LP
        uint256 oldUserLp = userLp[account];
        uint256 oldReservedLp = userReservedLp[account];

        // LP balance unchanged
        if (oldUserLp == newUserLp && oldReservedLp == newReservedLp) {
            return (false, oldUserLp);
        }

        // ---- [3] handle user reserved LP
        // +/- reserved LP
        if (oldReservedLp > newReservedLp) {
            _safeBurnLp(lpReserveAddress, oldReservedLp - newReservedLp);
            totalReservedLp -= (oldReservedLp - newReservedLp);
        } else if (oldReservedLp < newReservedLp) {
            lpToken.mint(lpReserveAddress, newReservedLp - oldReservedLp);
            totalReservedLp += (newReservedLp - oldReservedLp);
        }
        userReservedLp[account] = newReservedLp;

        // ---- [4] handle user LP and delegation
        address holder = delegation[account];
        // burn old lpToken amount from holder
        _safeBurnLp(holder, oldUserLp);
        // mint new lpToken amount to holder
        lpToken.mint(holder, newUserLp);
        // update user LP balance as new LP
        userLp[account] = newUserLp;

        emit UserLpRebalanced(account, newUserLp, newReservedLp);

        return (true, newUserLp);
    }

    /**
     * @notice User's available lpToken might lower than the burn amount
     *         due to the change of exchangeRate, ReservedLpRate or the value of the LP token fluctuates from time to time
     *         i.e. userLp[account] might < lpToken.balanceOf(holder)
     * @param holder lp token holder
     * @param amount amount to burn
     */
    function _safeBurnLp(address holder, uint256 amount) internal {
        uint256 availableBalance = lpToken.balanceOf(holder);
        if (amount <= availableBalance) {
            lpToken.burn(holder, amount);
        } else if (availableBalance > 0) {
            // existing users do not have enough lpToken
            lpToken.burn(holder, availableBalance);
        }
    }

    /* ----------------------------------- Admin functions ----------------------------------- */
    /**
     * change exchange rate
     * @param _exchangeRate new exchange rate
     */
    function setExchangeRate(uint128 _exchangeRate) external onlyRole(MANAGER) {
        require(_exchangeRate > 0 && _exchangeRate >= userLpRate, "exchangeRate invalid");

        exchangeRate = _exchangeRate;
        emit ExchangeRateChanged(exchangeRate);
    }

    function setUserLpRate(uint128 _userLpRate) external onlyRole(MANAGER) {
        require(_userLpRate <= 1e18 && _userLpRate < exchangeRate, "userLpRate invalid");

        userLpRate = _userLpRate;
        emit UserLpRateChanged(userLpRate);
    }

    /**
     * change lpReserveAddress, all reserved lpToken will be burned from original address and be minted to new address
     * @param _lpTokenReserveAddress new lpTokenReserveAddress
     */
    function setLpReserveAddress(address _lpTokenReserveAddress) external onlyRole(MANAGER) {
        require(_lpTokenReserveAddress != address(0) && _lpTokenReserveAddress != lpReserveAddress, "lpTokenReserveAddress invalid");
        if (totalReservedLp > 0) {
            lpToken.burn(lpReserveAddress, totalReservedLp);
            lpToken.mint(_lpTokenReserveAddress, totalReservedLp);
        }
        lpReserveAddress = _lpTokenReserveAddress;
        emit LpReserveAddressChanged(lpReserveAddress);
    }

    /**
     * @dev pause the contract
     */
    function pause() external onlyRole(PAUSER) {
        _pause();
    }

    /**
    * @dev toggle pause status of the contract
    */
    function togglePause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused() ? _unpause() : _pause();
    }

    /**
     * @dev only admin can upgrade the contract
     * @param _newImplementation new implementation address
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
    }
}
