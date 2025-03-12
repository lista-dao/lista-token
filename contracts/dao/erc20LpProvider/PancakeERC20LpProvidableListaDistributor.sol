pragma solidity ^0.8.10;

import "../CommonListaDistributor.sol";
import "../interfaces/IStaking.sol";
import "../interfaces/IStakingVault.sol";
import "../interfaces/IStableSwap.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
  * @title PancakeERC20LpProvidableListaDistributor
  * @dev lista token stake and distributor for erc20 LP token
 */
contract PancakeERC20LpProvidableListaDistributor is CommonListaDistributor, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // add-on role for ProvidableListaDistributor
    bytes32 public constant TOKEN_PROVIDER = keccak256("TOKEN_PROVIDER");

    // staking address
    address public staking;
    // stake vault address
    address public stakeVault;

    // PancakeSwap StableSwap contract address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable stableSwapPool;
    // PancakeStableSwapTwoPoolInfo contract address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable stableSwapPoolInfo;

    // lp token balance of each account
    mapping(address => uint256) public lpBalanceOf;
    // total lp token supply
    uint256 public lpTotalSupply;
    // stake token period finish
    uint256 public stakePeriodFinish;
    // stake token last update operation timestamp
    uint256 public stakeLastUpdate;
    // stake token reward of per token
    uint256 public stakeRewardIntegral;
    // stake token reward of per second
    uint256 public stakeRewardRate;
    // stake token reward integral for each account on last update time
    // account -> reward integral
    mapping(address => uint256) public stakeRewardIntegralFor;
    // stake token pending reward for each account
    // account -> pending reward
    mapping(address => uint256) private stakeStoredPendingReward;
    // compatibility mode
    // @dev true : LP token can be deposited and withdrawn from user or tokenProvider
    //      false: LP token can only be deposited and withdrawn from tokenProvider
    bool public compatibilityMode;

    event StakeRewardClaimed(address indexed receiver, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    /**
     * @param _stableSwap PancakeStableSwapTwoPool address
     * @param _poolInfo PancakeStableSwapTwoPoolInfo address
     */
    constructor(address _stableSwap, address _poolInfo) {
        require(_stableSwap != address(0) && _poolInfo != address(0), "Invalid address");
        _disableInitializers();
        stableSwapPool = _stableSwap;
        stableSwapPoolInfo = _poolInfo;
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
        require(_vault != address(0), "vault is the zero address");
        __AccessControl_init();
        __Pausable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(VAULT, _vault);
        lpToken = _lpToken;
        vault = IVault(_vault);
        name = string.concat("Lista-", IERC20Metadata(_lpToken).name());
        symbol = string.concat("Lista LP ", IERC20Metadata(_lpToken).symbol(), " Distributor");
    }

    modifier onlyInCompatibilityMode() {
        require(compatibilityMode, "compatibility mode is disabled");
        _;
    }

    modifier onlyStakeVault() {
        require(msg.sender == stakeVault, "only stake vault can call this function");
        _;
    }

    /**
     * @dev deposit LP token on behalf of user
     * @param amount amount of LP token
     * @param account account address
     */
    function depositFor(uint256 amount, address account) external onlyRole(TOKEN_PROVIDER) {
        require(amount > 0, "Cannot deposit zero");
        _deposit(account, amount);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        _depositLp(account, amount);
    }

    /**
     * @dev withdraw LP token on behalf of user
     * @param amount amount of LP token
     * @param account account address
     */
    function withdrawFor(uint256 amount, address account) external onlyRole(TOKEN_PROVIDER) {
        require(amount > 0, "Cannot withdraw zero");
        _withdraw(account, amount);
        _withdrawLp(account, amount);
    }

    /**
     * @dev deposit LP token to get rewards
     * @param amount amount of LP token
     */
    function deposit(uint256 amount) external onlyInCompatibilityMode {
        require(amount > 0, "Cannot deposit zero");
        _deposit(msg.sender, amount);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        _depositLp(msg.sender, amount);
    }

    /**
     * @dev withdraw LP token
     * @param amount amount of LP token
     */
    function withdraw(uint256 amount) external onlyInCompatibilityMode {
        require(amount > 0, "Cannot withdraw zero");
        _withdraw(msg.sender, amount);
        _withdrawLp(msg.sender, amount);
    }

    // deposit lp to staking pool
    function _depositLp(address _account, uint256 amount) private {
        uint256 balance = lpBalanceOf[_account];
        uint256 supply = lpTotalSupply;

        lpBalanceOf[_account] = balance + amount;
        lpTotalSupply = supply + amount;

        _updateStakeReward(_account, balance, supply);

        // deposit to staking contract to earn reward
        IERC20(lpToken).safeApprove(staking, amount);
        IStaking(staking).deposit(lpToken, amount);

        emit LPTokenDeposited(lpToken, _account, amount);
    }

    /**
     * @dev Returns the amount of quote token that held by the LP token of the account
     * @param account account address
     * @return the amount of quote token(token1)
     */
    function getUserLpTotalValueInQuoteToken(address account) external view returns (uint256) {
        // get user lp balance
        uint256 lpBalance = lpBalanceOf[account];
        if (lpBalance == 0) return 0;

        return _getLpToQuoteToken(lpBalance);
    }

    function getLpToQuoteToken(uint256 amount) external view returns (uint256) {
        return _getLpToQuoteToken(amount);
    }

    /**
     * @dev Returns the amount of quote token that represented by an amount of Lp Token
     * @param amount amount of LP token
     * @return the amount of quote token(token1)
     */
    function _getLpToQuoteToken(uint256 amount) internal view returns (uint256) {
        // Get amount of token0 and token1 underneath of user's LP
        uint256[2] memory coinsAmount = IStableSwapPoolInfo(stableSwapPoolInfo).calc_coins_amount(
            stableSwapPool,
            amount
        );
        uint256 userLpToken0Amount = coinsAmount[0];
        uint256 userLpToken1Amount = coinsAmount[1];
        // get conversion rate of token0 to token1
        uint256 token0toToken1 = IStableSwap(stableSwapPool).get_dy(0, 1, 1e18);

        // calculate the user's lp amount of token0 in token1
        uint256 userLpToken0ToToken1 = Math.mulDiv(userLpToken0Amount, token0toToken1, 1e18);

        return userLpToken0ToToken1 + userLpToken1Amount;
    }

    // withdraw lp from staking pool
    function _withdrawLp(address _account, uint256 amount) private {
        uint256 balance = lpBalanceOf[_account];
        uint256 supply = lpTotalSupply;
        require(balance >= amount, "insufficient balance");
        lpBalanceOf[_account] = balance - amount;
        lpTotalSupply = supply - amount;

        _updateStakeReward(_account, balance, supply);

        IStaking(staking).withdraw(_account, lpToken, amount);

        emit LPTokenWithdrawn(address(lpToken), _account, amount);
    }

    // when account do write operation, update reward
    function _updateStakeReward(address _account, uint256 balance, uint256 supply) internal {
        // update reward
        uint256 updated = stakePeriodFinish;
        if (updated > block.timestamp) updated = block.timestamp;
        uint256 duration = updated - stakeLastUpdate;
        if (duration > 0) stakeLastUpdate = uint32(updated);

        if (duration > 0 && supply > 0) {
            stakeRewardIntegral += (duration * stakeRewardRate * 1e18) / supply;
        }
        if (_account != address(0)) {
            uint256 integralFor = stakeRewardIntegralFor[_account];
            if (stakeRewardIntegral > integralFor) {

                stakeStoredPendingReward[_account] += (balance * (stakeRewardIntegral - integralFor)) / 1e18;
                stakeRewardIntegralFor[_account] = stakeRewardIntegral;
            }
        }
    }

    /**
     * @dev notify staking reward, only staking vault can call this function
     * @param amount reward amount
     */
    function notifyStakingReward(uint256 amount) external onlyStakeVault {
        _updateStakeReward(address(0), 0, lpTotalSupply);
        uint256 _periodFinish = stakePeriodFinish;
        if (block.timestamp < _periodFinish) {
            uint256 remaining = _periodFinish - block.timestamp;
            amount += remaining * stakeRewardRate;
        }

        stakeRewardRate = amount / REWARD_DURATION;

        stakeLastUpdate = block.timestamp;
        stakePeriodFinish = block.timestamp + REWARD_DURATION;
    }

    /**
    * @dev claim reward, only staking vault can call this function
      * @param _account account address
      * @return reward amount
      */
    function vaultClaimStakingReward(address _account) onlyStakeVault external returns (uint256) {
        return _claimStakingReward(_account);
    }

    function _claimStakingReward(address _account) internal returns (uint256) {
        _updateStakeReward(_account, lpBalanceOf[_account], lpTotalSupply);
        uint256 amount = stakeStoredPendingReward[_account];
        delete stakeStoredPendingReward[_account];

        emit StakeRewardClaimed(_account, amount);
        return amount;
    }

    /**
     * @dev set staking contract address
     * @param _staking staking contract address
     */
    function setStaking(address _staking) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_staking != address(0), "staking cannot be zero address");
        staking = _staking;
    }

    /**
     * @dev claim stake reward
     * @return reward amount
     */
    function claimStakeReward() external returns (uint256) {
        address _account = msg.sender;
        uint256 amount = _claimStakingReward(_account);
        IStakingVault(stakeVault).transferAllocatedTokens(_account, amount);
        return amount;
    }

    /**
     * @dev get stake claimable reward amount
     * @param account account address
     * @return reward amount
     */
    function getStakeClaimableReward(address account) external view returns (uint256) {
        uint256 balance = lpBalanceOf[account];
        uint256 supply = lpTotalSupply;
        uint256 updated = stakePeriodFinish;
        if (updated > block.timestamp) updated = block.timestamp;
        uint256 duration = updated - stakeLastUpdate;
        uint256 integral = stakeRewardIntegral;
        if (supply > 0) {
            integral += (duration * stakeRewardRate * 1e18) / supply;
        }
        uint256 integralFor = stakeRewardIntegralFor[account];
        return stakeStoredPendingReward[account] + (balance * (integral - integralFor)) / 1e18;
    }

    /**
     * @dev set stake vault address
     * @param _stakeVault stake vault address
     */
    function setStakeVault(address _stakeVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_stakeVault != address(0), "stake vault is the zero address");
        stakeVault = _stakeVault;
    }

    /**
     * @dev set compatibility mode
     * @param _compatibilityMode compatibility mode
     */
    function setCompatibilityMode(bool _compatibilityMode) external onlyRole(MANAGER) {
        require(compatibilityMode != _compatibilityMode, "compatibility mode is already set");
        compatibilityMode = _compatibilityMode;
    }

    /**
     * @dev harvest stake reward from third-party staking pool
     */
    function harvest() external {
        IStaking(staking).harvest(lpToken);
    }
}
