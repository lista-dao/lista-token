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
 * 1. token to lpToken rate is not 1:1 and modifiable
 * 2. user's lpToken will be minted to itself(delegatee) and lpReserveAddress according to userLpRate
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
    // proxy role
    bytes32 public constant PROXY = keccak256("PROXY");

    /* ------------------ Variables ------------------ */
    // the original LP token such as PancakeSwap StablePool LP Token
    address public token;
    // User will get this LP token as proof of e.g clisXXX
    ILpToken public lpToken;
    // the ERC20-LP Lista distributor that connects to this provider
    IERC20LpProvidableDistributor public lpProvidableDistributor;
    // account > delegation { delegateTo, amount }
    mapping(address => Delegation) public delegation;
    // user account > sum lpTokens of user including delegated part
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
    event SyncUserLpWithReserve(address account, uint256 userLp, uint256 reservedLp);
    event ChangeExchangeRate(uint128 rate);
    event ChangeUserLpRate(uint128 rate);
    event ChangeLpReserveAddress(address newAddress);
    event Deposit(address indexed account, uint256 amount, uint256 lPAmount);
    event Withdrawal(address indexed owner, uint256 amount);
    event ChangeDelegateTo(address account, address oldDelegatee, address newDelegatee);
    event SyncUserLp(address account, uint256 userLp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @dev initialize function
    * @param _admin admin role address
    * @param _manager manager role address
    * @param _proxy proxy role address
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
        address _proxy,
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
        require(_proxy != address(0), "proxy is the zero address");
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
        _grantRole(PROXY, _proxy);
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
        require(_amount > 0, "zero deposit amount");
        // transfer token from user to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        // deposit to distributor
        uint256 userPartLp = _processBalanceChange(msg.sender, msg.sender, _amount, true);
        // deposit to distributor
        lpProvidableDistributor.depositFor(_amount, msg.sender);

        emit Deposit(msg.sender, _amount, userPartLp);
        return userPartLp;
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
        require(_amount > 0, "zero deposit amount");
        require(_delegateTo != address(0), "delegateTo cannot be zero address");
        require(_delegateTo != msg.sender, "delegateTo cannot be self");
        require(
            delegation[msg.sender].delegateTo == _delegateTo ||
            delegation[msg.sender].amount == 0, // first time, clear old delegatee
            "delegateTo is differ from the current one"
        );
        // transfer token from user to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        // deposit to distributor
        lpProvidableDistributor.depositFor(_amount, msg.sender);
        // update balance
        uint256 userPartLp = _processBalanceChange(msg.sender, _delegateTo, _amount, true);

        emit Deposit(msg.sender, _amount, userPartLp);
        return userPartLp;
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
        // update balance
        uint256 userPartLp = _processBalanceChange(msg.sender, msg.sender, _amount, false);

        emit Withdrawal(msg.sender, _amount);
        return _amount;
    }

    /**
    * delegate all collateral tokens to given address
    * @param _newDelegateTo new target address of collateral tokens
    */
    function delegateAllTo(address _newDelegateTo)
    external
    whenNotPaused
    nonReentrant
    {
        require(_newDelegateTo != address(0), "delegateTo cannot be zero address");

        // get user total deposit
        uint256 userTotalLp = userLp[msg.sender];
        require(userTotalLp > 0, "zero lp to delegate");

        Delegation storage currentDelegation = delegation[msg.sender];
        address currentDelegateTo = currentDelegation.delegateTo;

        // Step 1. burn all tokens
        if (currentDelegation.amount > 0) {
            // burn delegatee's token
            lpToken.burn(currentDelegateTo, currentDelegation.amount);
            // burn self's token
            if (userTotalLp > currentDelegation.amount) {
                _safeBurnLp(msg.sender, userTotalLp - currentDelegation.amount);
            }
        } else {
            _safeBurnLp(msg.sender, userTotalLp);
        }

        // Step 2. save new delegatee and mint all tokens to delegatee
        if (_newDelegateTo == msg.sender) {
            // mint all to self
            lpToken.mint(msg.sender, userTotalLp);
            // remove delegatee
            delete delegation[msg.sender];
        } else {
            // mint all to new delegatee
            lpToken.mint(_newDelegateTo, userTotalLp);
            // save delegatee's info
            currentDelegation.delegateTo = _newDelegateTo;
            currentDelegation.amount = userTotalLp;
        }

        emit ChangeDelegateTo(msg.sender, currentDelegateTo, _newDelegateTo);
    }

    /* ----------------------------------- Internal functions ----------------------------------- */
    function _processBalanceChange(address account, address holder, uint256 amount, bool isDeposit) internal returns(uint256) {
        // lpToken value holding by `amount` of token
        uint256 netLp = lpProvidableDistributor.getLpToQuoteToken(amount);
        // the actual LP converts to
        uint256 deltaLpAmount = netLp * exchangeRate / RATE_DENOMINATOR;
        // net change of user's lpToken
        uint256 deltaHolderLpAmount = deltaLpAmount * userLpRate / RATE_DENOMINATOR;
        // net change of reserve address's lpToken
        uint256 deltaReserveLpAmount = deltaLpAmount - deltaHolderLpAmount;

        // -------------- deposit --------------
        if (isDeposit) {
            // mint to account/holder
            if (deltaHolderLpAmount > 0) {
                // deposit to delegatee
                if (account != holder) {
                    // assign to the delegatee
                    Delegation storage userDelegation = delegation[msg.sender];
                    userDelegation.delegateTo = holder;
                    userDelegation.amount += deltaHolderLpAmount;
                }
                // update balance and mint to holder
                lpToken.mint(holder, deltaHolderLpAmount);
                userLp[account] += deltaHolderLpAmount;
            }
            // mint to reserve address
            if (deltaReserveLpAmount > 0) {
                // mint to reserve address
                lpToken.mint(lpReserveAddress, deltaReserveLpAmount);
                userReservedLp[account] += deltaReserveLpAmount;
                totalReservedLp += deltaReserveLpAmount;
            }
        }
        // -------------- Withdrawal --------------
        else {
            // burn from account/delegatee
            if (deltaHolderLpAmount > 0) {
                Delegation storage userDelegation = delegation[msg.sender];
                // burn delegatee's first
                if (delegation[account].amount > 0) {
                    uint256 delegatedAmount = delegation[account].amount;
                    uint256 delegateeBurn = deltaHolderLpAmount > delegatedAmount ? delegatedAmount : deltaHolderLpAmount;
                    // burn delegatee's token, update delegated amount
                    lpToken.burn(delegation[account].delegateTo, delegateeBurn);
                    delegation[account].amount -= delegateeBurn;
                    // in case delegatee's holding is not enough
                    // burn delegator's token
                    if (deltaHolderLpAmount > delegateeBurn) {
                        _safeBurnLp(account, deltaHolderLpAmount - delegateeBurn);
                    }
                } else {
                    // no delegation, only burn from account
                    _safeBurnLp(account, deltaHolderLpAmount);
                }
                // update balance
                userLp[account] -= deltaHolderLpAmount;
            }
            // burn from reserve address
            if (deltaReserveLpAmount > 0) {
                // burn from reserve address
                lpToken.burn(lpReserveAddress, deltaReserveLpAmount);
                userReservedLp[account] -= deltaReserveLpAmount;
                totalReservedLp -= deltaReserveLpAmount;
            }
        }
        return deltaHolderLpAmount;
    }

    /**
     * @notice note that the conversion between token and quoteToken is dynamic, and quoteToken is 1:1 to LP token
     *         if the conversion rate changes, the LP token amount will be changed accordingly by rebalancing(),
     *         then, user might not have enough LP token to burn
     * @dev to make sure existing users who do not have enough lpToken can still burn
     *      only the available amount excluding delegated part will be burned
     * @param _account lp token holder
     * @param _amount amount to burn
     */
    function _safeBurnLp(address _account, uint256 _amount) internal {
        uint256 availableBalance = userLp[_account] - delegation[_account].amount;
        if (_amount <= availableBalance) {
            lpToken.burn(_account, _amount);
        } else if (availableBalance > 0) {
            // existing users do not have enough lpToken
            lpToken.burn(_account, availableBalance);
        }
    }

    /* ----------------------------------- LP re-balancing ----------------------------------- */
    function syncUserLp(address _account) external {
        bool rebalanced = _rebalanceUserLp(_account);
        require(rebalanced, "already synced");
    }

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
        uint256 expectedTotalLp = userStakedTokenAmount * exchangeRate / RATE_DENOMINATOR;
        uint256 expectUserLp = expectedTotalLp * userLpRate / RATE_DENOMINATOR;
        uint256 expectReservedLp = expectedTotalLp - expectUserLp;

        return userLp[account] == expectUserLp && userReservedLp[account] == expectReservedLp;
    }


    /**
     * @dev mint/burn lpToken to sync user's lpToken with token balance
     * @param account user address to sync
     */
    function _rebalanceUserLp(address account) internal returns (bool) {

        // The token amount of user staked at distributor
        uint256 userStakedTokenAmount = lpProvidableDistributor.getUserLpTotalValueInQuoteToken(account);

        // ---- [1] Estimated LP value
        // Total LP(Lista + User + Reserve)
        uint256 expectedTotalLp = userStakedTokenAmount * exchangeRate / RATE_DENOMINATOR;
        // User's LP
        uint256 expectUserLp = expectedTotalLp * userLpRate / RATE_DENOMINATOR;
        // Reserve's LP
        uint256 expectReservedLp = expectedTotalLp - expectUserLp;

        // ---- [2] Current user LP and reserved LP
        uint256 currentUserLp = userLp[account];
        uint256 currentReservedLp = userReservedLp[account];

        // LP balance unchanged
        if (currentUserLp == expectUserLp && currentReservedLp == expectReservedLp) {
            return false;
        }

        // ---- [3] handle user reserved LP
        // +/- reserved LP
        if (currentReservedLp > expectReservedLp) {
            lpToken.burn(lpReserveAddress, currentReservedLp - expectReservedLp);
            userReservedLp[account] = expectReservedLp;
            totalReservedLp -= (currentReservedLp - expectReservedLp);
        } else if (currentReservedLp < expectReservedLp) {
            lpToken.mint(lpReserveAddress, expectReservedLp - currentReservedLp);
            userReservedLp[account] = expectReservedLp;
            totalReservedLp += (expectReservedLp - currentReservedLp);
        }

        // ---- [4] handle user LP and delegation
        Delegation storage userDelegation = delegation[account];
        // current delegation
        uint256 currentDelegatedLp = userDelegation.amount;
        uint256 currentSelfLp = currentUserLp - currentDelegatedLp;
        // expected delegation
        uint256 expectedLpToDelegate = currentUserLp > 0 ? expectUserLp * currentDelegatedLp / currentUserLp : 0;
        uint256 expectedSelfLp = expectUserLp - expectedLpToDelegate;

        // -/+ delegated LP
        if (currentDelegatedLp > expectedLpToDelegate) {
            lpToken.burn(userDelegation.delegateTo, currentDelegatedLp - expectedLpToDelegate);
        } else if (currentDelegatedLp < expectedLpToDelegate) {
            lpToken.mint(userDelegation.delegateTo, expectedLpToDelegate - currentDelegatedLp);
        }
        // update delegation LP balance
        userDelegation.amount = expectedLpToDelegate;

        // -/+ self LP
        if (currentSelfLp > expectedSelfLp) {
            lpToken.burn(account, currentSelfLp - expectedSelfLp);
        } else if (currentSelfLp < expectedSelfLp) {
            lpToken.mint(account, expectedSelfLp - currentSelfLp);
        }
        // update user LP balance
        userLp[account] = expectUserLp;

        emit SyncUserLpWithReserve(account, expectUserLp, expectReservedLp);

        return true;
    }

    /* ----------------------------------- Admin functions ----------------------------------- */
    /**
     * change exchange rate
     * @param _exchangeRate new exchange rate
     */
    function changeExchangeRate(uint128 _exchangeRate) external onlyRole(MANAGER) {
        require(_exchangeRate > 0, "exchangeRate invalid");

        exchangeRate = _exchangeRate;
        emit ChangeExchangeRate(exchangeRate);
    }

    function changeUserLpRate(uint128 _userLpRate) external onlyRole(MANAGER) {
        require(_userLpRate <= 1e18, "userLpRate invalid");

        userLpRate = _userLpRate;
        emit ChangeUserLpRate(userLpRate);
    }

    /**
     * change lpReserveAddress, all reserved lpToken will be burned from original address and be minted to new address
     * @param _lpTokenReserveAddress new lpTokenReserveAddress
     */
    function changeLpReserveAddress(address _lpTokenReserveAddress) external onlyRole(MANAGER) {
        require(_lpTokenReserveAddress != address(0) && _lpTokenReserveAddress != lpReserveAddress, "lpTokenReserveAddress invalid");
        if (totalReservedLp > 0) {
            lpToken.burn(lpReserveAddress, totalReservedLp);
            lpToken.mint(_lpTokenReserveAddress, totalReservedLp);
        }
        lpReserveAddress = _lpTokenReserveAddress;
        emit ChangeLpReserveAddress(lpReserveAddress);
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

    // storage gap, declared fields: 5/50
    uint256[45] __gap;
}
