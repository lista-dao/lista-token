pragma solidity ^0.8.10;

import "../CommonListaDistributor.sol";
import "../interfaces/IStaking.sol";
import "../interfaces/IStakingVault.sol";
import "../interfaces/IThenaErc20LpToken.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../../library/TickMath.sol";

/**
  * @title ThenaERC20LpProvidableListaDistributor
  * @dev lista token stake and distributor for erc20 LP token
 */
contract ThenaERC20LpProvidableListaDistributor is CommonListaDistributor, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // add-on role for ProvidableListaDistributor
    bytes32 public constant TOKEN_PROVIDER = keccak256("TOKEN_PROVIDER");

    // staking address
    address public staking;
    // stake vault address
    address public stakeVault;

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
    // tokenProvider mode
    // @dev true : Only TokenProvider can deposit and withdraw LP token
    //      false: Both user and TokenProvider can deposit and withdraw LP token
    bool public tokenProviderMode;

    event StakeRewardClaimed(address indexed receiver, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
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

    modifier whenNotInTokenProviderMode() {
        require(!tokenProviderMode, "tokenProvider mode is enabled");
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
    function deposit(uint256 amount) external whenNotInTokenProviderMode {
        require(amount > 0, "Cannot deposit zero");
        _deposit(msg.sender, amount);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        _depositLp(msg.sender, amount);
    }

    /**
     * @dev withdraw LP token
     * @param amount amount of LP token
     */
    function withdraw(uint256 amount) external whenNotInTokenProviderMode {
        require(amount > 0, "Cannot withdraw zero");
        _withdraw(msg.sender, amount);
        _withdrawLp(msg.sender, amount);
    }

    /**
     * @dev Returns the amount of base token that held by the LP token of the account
     * @param account account address
     * @return the amount of quote token(token1)
     */
    function getUserLpTotalValueInQuoteToken(address account) external view returns (uint256) {
        IThenaErc20LpToken _lpToken = IThenaErc20LpToken(lpToken);
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
        IThenaErc20LpToken _lpToken = IThenaErc20LpToken(lpToken);
        // calculate amount of token0 and token1 underneath of user's LP
        // get total amounts of token0 and token1
        (uint256 total0, uint256 total1) = _lpToken.getTotalAmounts();
        // get LP total supply
        uint256 totalSupply = _lpToken.totalSupply();
        // calculate user's LP proportion
        uint256 userLpProportion = (amount * 1e18) / totalSupply;
        // calculate user's LP value in token0
        uint256 userLpToken0Amount = (total0 * userLpProportion) / 1e18;
        uint256 userLpToken1Amount = (total1 * userLpProportion) / 1e18;

        // Get conversion rate of token0 to token1
        uint256 token0ToToken1 = tickToPrice(
            _lpToken.currentTick(),
            IERC20Metadata(_lpToken.token0()).decimals(),
            IERC20Metadata(_lpToken.token1()).decimals(),
            _lpToken.token0(),
            _lpToken.token1()
        );
        // convert user's token0 to token1
        uint256 userLpToken0ToToken1 = Math.mulDiv(userLpToken0Amount, token0ToToken1, 1e18);

        return userLpToken0ToToken1 + userLpToken1Amount;
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
     * @dev harvest stake reward from third-party staking pool
     */
    function harvest() external {
        IStaking(staking).harvest(lpToken);
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
     * @dev set stake vault address
     * @param _stakeVault stake vault address
     */
    function setStakeVault(address _stakeVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_stakeVault != address(0), "stake vault is the zero address");
        stakeVault = _stakeVault;
    }

    /**
     * @dev set tokenProvider mode
     * @param _tokenProviderMode tokenProvider mode
     */
    function setTokenProviderMode(bool _tokenProviderMode) external onlyRole(MANAGER) {
        require(tokenProviderMode != _tokenProviderMode, "tokenProvider mode is already set");
        tokenProviderMode = _tokenProviderMode;
    }

    /* ------------------------ Helper functions ------------------------ */
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) private pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? Math.mulDiv(ratioX192, baseAmount, 1 << 192)
                : Math.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = Math.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? Math.mulDiv(ratioX128, baseAmount, 1 << 128)
                : Math.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    // get price by tick
    function tickToPrice(
        int24 tick,
        uint8 token0Decimals,
        uint8 token1Decimals,
        address token0,
        address token1
    ) private pure returns (uint256) {
        uint128 baseAmount = uint128(10 ** token0Decimals);
        uint256 quoteAmount = getQuoteAtTick(tick, baseAmount, token0, token1);
        return quoteAmount * 1e18 / 10 ** token1Decimals;
    }
}
