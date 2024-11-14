// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { CommonListaDistributor, SafeERC20 } from "./CommonListaDistributor.sol";

//import { IStaking } from "./interfaces/IStaking.sol";
import { IStakingVault } from "./interfaces/IStakingVault.sol";
import { IStableSwap, IStableSwapPoolInfo } from "./interfaces/IStableSwap.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IV2Wrapper } from "./interfaces/IV2Wrapper.sol";

/**
 * @title USDTLpListaDistributor
 * @dev This contract is used to stake USDT and earn token emission rewards.
 */
contract USDTLpListaDistributor is CommonListaDistributor, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  /* ============ PancakeSwap Addresses ============ */
  // PancakeSwap lisUSD/USDT StableSwap contract address
  address public stableSwapPool;
  // PancakeStableSwapTwoPoolInfo contract address
  address private stableSwapPoolInfo;
  // PancakeSwap lisUSD/USDT StableSwap coins[0]
  IERC20 public lisUSD;
  // PancakeSwap lisUSD/USDT StableSwap coins[1]
  IERC20 public usdt;
  // PancakeSwap Stable-LP Farming contract address
  IV2Wrapper public v2wrapper;
  // CAKE is the LP Farming reward token
  address public cake;

  /* ============ StakingVault Address ============ */
  // StakingVault address
  address public stakeVault;

  /* ============ State Variables ============ */
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

  // harvest time gap, 1h
  uint256 public harvestTimeGap;
  // last harvest time
  uint256 public lastHarvestTime;

  /* ============ Events ============ */
  event USDTStaked(address indexed lpToken, uint256 usdtAmount, uint256 lpAmount);
  event LpUnstaked(address indexed lpToken, uint256 usdtAmount, uint256 lisUSDAmount, uint256 lpAmount);
  event StakeRewardClaimed(address indexed receiver, uint256 amount);
  event Harvest(address usdt, address distributor, uint256 amount);
  event WithdrawLp(address usdt, address distributor, address account, uint256 amount);
  event DepositLp(address usdt, address distributor, uint256 amount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize contract
   * @param _admin admin address
   * @param _manager manager address
   * @param _vault ListaVault address
   * @param _v2wrapper V2wWapper address
   * @param _stakeVault StakingVault address
   * @param _stableswap lisUSD/USDT PancakeStableSwapTwoPool address
   * @param _poolInfo PancakeStableSwapTwoPoolInfo address
   */
  function initialize(
    address _admin,
    address _manager,
    address _vault,
    address _v2wrapper,
    address _stakeVault,
    address _stableswap,
    address _poolInfo
  ) external initializer {
    require(_admin != address(0), "admin is the zero address");
    require(_manager != address(0), "manager is the zero address");
    require(_vault != address(0), "vault is the zero address");
    require(_v2wrapper != address(0), "pancake staking is the zero address");
    require(_stakeVault != address(0), "stake vault is the zero address");
    require(_stableswap != address(0), "stableswap is the zero address");
    require(_poolInfo != address(0), "pool info is the zero address");

    __AccessControl_init();
    __Pausable_init();

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(MANAGER, _manager);
    _setupRole(VAULT, _vault);

    stableSwapPool = _stableswap;
    stableSwapPoolInfo = _poolInfo;

    lisUSD = IERC20(IStableSwap(stableSwapPool).coins(0));
    usdt = IERC20(IStableSwap(stableSwapPool).coins(1));
    lpToken = IStableSwap(stableSwapPool).token();
    vault = IVault(_vault);
    v2wrapper = IV2Wrapper(_v2wrapper);
    stakeVault = _stakeVault;
    cake = IStakingVault(stakeVault).rewardToken();

    harvestTimeGap = 1 hours;
    lastHarvestTime = 0;

    name = string.concat("Lista-USDT-Staking", IERC20Metadata(lpToken).name());
    symbol = string.concat("Lista USDT Staking ", IERC20Metadata(lpToken).symbol(), " Distributor");
  }

  modifier onlyStakeVault() {
    require(msg.sender == stakeVault, "only stake vault can call this function");
    _;
  }

  /* ================ External Functions ================ */

  /**
   * @dev Deposit USDT to PancakeStableSwapTwoPool and stake LP token to farming contract
   * @param usdtAmount amount of USDT to deposit
   * @param minLpAmount minimum amount of LP token required to mint
   */
  function deposit(uint256 usdtAmount, uint256 minLpAmount) external {
    require(usdtAmount > 0, "Invalid usdt amount");
    uint256 expectLpAmount = getLpAmount(usdtAmount);
    require(expectLpAmount >= minLpAmount, "Invalid min lp amount");

    // Transfer USDT to this contract
    usdt.safeIncreaseAllowance(stableSwapPool, usdtAmount);
    usdt.safeTransferFrom(msg.sender, address(this), usdtAmount);

    // Add USDT to PancakeStableSwapTwoPool
    uint256 actualLpAmount = IERC20(lpToken).balanceOf(address(this));
    IStableSwap(stableSwapPool).add_liquidity([0, usdtAmount], minLpAmount);
    actualLpAmount = IERC20(lpToken).balanceOf(address(this)) - actualLpAmount;

    require(actualLpAmount >= minLpAmount, "Invalid lp amount minted");

    // Update user's LP balance and LISTA reward, and distributor's LP total supply
    _deposit(msg.sender, actualLpAmount);

    // Stake the received LP token to farming contract
    _stakeLp(msg.sender, actualLpAmount);

    emit USDTStaked(lpToken, usdtAmount, actualLpAmount);
  }

  /**
   * @dev Unstake LP token from farming contract and withdraw USDT and lisUSD from PancakeStableSwapTwoPool
   * @param lpAmount amount of LP token
   * @param minLisUSDAmount minimum amount of lisUSD to withdraw
   * @param minUSDTAmount minimum amount of USDT to withdraw
   */
  function withdraw(uint256 lpAmount, uint256 minLisUSDAmount, uint256 minUSDTAmount) external {
    // 1. Validate lisUSD and USDT amount
    (uint256 expectLisUSDAmount, uint256 expectUSDTAmount) = getCoinsAmount(lpAmount);
    require(minLisUSDAmount <= expectLisUSDAmount, "Invalid lisUSD amount");
    require(minUSDTAmount <= expectUSDTAmount, "Invalid USDT amount");

    // 2. Update user's LP balance and LISTA reward, and distributor's LP total supply
    _withdraw(msg.sender, lpAmount);

    // 3. Unstake LP token from farming contract
    _unstakeLp(msg.sender, lpAmount);

    // 4. Remove liquidity from PancakeStableSwapTwoPool
    uint256 lisUSDAmountActual = lisUSD.balanceOf(address(this));
    uint256 usdtAmountActual = usdt.balanceOf(address(this));

    IStableSwap(stableSwapPool).remove_liquidity(lpAmount, [minLisUSDAmount, minUSDTAmount]);

    lisUSDAmountActual = lisUSD.balanceOf(address(this)) - lisUSDAmountActual;
    usdtAmountActual = usdt.balanceOf(address(this)) - usdtAmountActual;
    require(lisUSDAmountActual >= minLisUSDAmount, "Invalid lisUSD amount received");
    require(usdtAmountActual >= minUSDTAmount, "Invalid USDT amount received");

    // 5. Transfer lisUSD and USDT to user
    lisUSD.safeTransfer(msg.sender, lisUSDAmountActual);
    usdt.safeTransfer(msg.sender, usdtAmountActual);

    emit LpUnstaked(lpToken, usdtAmountActual, lisUSDAmountActual, lpAmount);
  }

  /**
   * @dev Harvest LP staking reward (CAKE) from farming contract
   * @return claimed CAKE amount
   */
  function harvest() external nonReentrant returns (uint256) {
    address distributor = address(this);

    if (noHarvest()) return 0;

    // Claim CAKE rewards from V2Wrapper
    uint256 beforeBalance = IERC20(cake).balanceOf(distributor);
    v2wrapper.deposit(0, false);
    uint256 claimed = IERC20(cake).balanceOf(distributor) - beforeBalance;
    lastHarvestTime = block.timestamp;

    // Send CAKE to StakingVault
    if (claimed > 0) {
      IERC20(cake).safeApprove(stakeVault, claimed);
      IStakingVault(stakeVault).sendRewards(distributor, claimed);
      emit Harvest(address(usdt), distributor, claimed);
    }

    return claimed;
  }

  /**
   * @dev claim staked LP reward (CAKE)
   * @return reward amount
   */
  function claimStakeReward() external returns (uint256) {
    address _account = msg.sender;
    uint256 amount = _claimStakingReward(_account);
    IStakingVault(stakeVault).transferAllocatedTokens(_account, amount);
    return amount;
  }

  /* ==================== Internal Functions ==================== */

  /**
   * @dev stake LP token to farming contract
   * @param _account account address
   * @param _amount LP token amount
   */
  function _stakeLp(address _account, uint256 _amount) private {
    address distributor = address(this);
    uint256 balance = lpBalanceOf[_account];
    uint256 supply = lpTotalSupply;

    lpBalanceOf[_account] = balance + _amount;
    lpTotalSupply = supply + _amount;

    _updateStakeReward(_account, balance, supply);

    uint256 beforeBalance = IERC20(cake).balanceOf(distributor);
    bool _noHarvest = noHarvest();
    if (!_noHarvest) {
      lastHarvestTime = block.timestamp;
    }
    // Stake LP tokens to V2Wrapper
    IERC20(lpToken).safeIncreaseAllowance(address(v2wrapper), _amount);
    v2wrapper.deposit(_amount, _noHarvest);

    uint256 claimed = IERC20(cake).balanceOf(distributor) - beforeBalance;

    // Send CAKE rewards to StakingVault
    if (claimed > 0) {
      IERC20(cake).safeIncreaseAllowance(stakeVault, claimed);
      IStakingVault(stakeVault).sendRewards(distributor, claimed);
      emit Harvest(address(usdt), distributor, claimed);
    }

    emit DepositLp(address(usdt), distributor, _amount);
    emit LPTokenDeposited(lpToken, _account, _amount);
  }

  // withdraw lp from staking pool
  function _unstakeLp(address _account, uint256 amount) private {
    uint256 balance = lpBalanceOf[_account];
    uint256 supply = lpTotalSupply;
    require(balance >= amount, "insufficient balance");
    lpBalanceOf[_account] = balance - amount;
    lpTotalSupply = supply - amount;

    _updateStakeReward(_account, balance, supply);

    address distributor = address(this);

    // withdraw lp token and claim rewards
    uint256 beforeBalance = IERC20(cake).balanceOf(distributor);

    bool _noHarvest = noHarvest();
    if (!_noHarvest) {
      lastHarvestTime = block.timestamp;
    }
    v2wrapper.withdraw(amount, _noHarvest);

    uint256 claimed = IERC20(cake).balanceOf(distributor) - beforeBalance;

    // Send CAKE rewards to StakingVault
    if (claimed > 0) {
      IERC20(cake).safeApprove(stakeVault, claimed);
      IStakingVault(stakeVault).sendRewards(distributor, claimed);
      emit Harvest(address(usdt), distributor, claimed);
    }

    // Withdraw staked LP tokens to this contract
    IERC20(lpToken).safeTransfer(distributor, amount);
    emit WithdrawLp(address(usdt), distributor, distributor, amount);

    emit LPTokenWithdrawn(address(lpToken), _account, amount);
  }

  // Claim CAKE reward; perform by staking vault or user
  function _claimStakingReward(address _account) internal returns (uint256) {
    _updateStakeReward(_account, lpBalanceOf[_account], lpTotalSupply);
    uint256 amount = stakeStoredPendingReward[_account];
    delete stakeStoredPendingReward[_account];

    emit StakeRewardClaimed(_account, amount);
    return amount;
  }

  // Calculate CAKE reward if any write operation is performed
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


  /* ==================== Role-Based Functions ==================== */

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
  function vaultClaimStakingReward(address _account) external onlyStakeVault returns (uint256) {
    return _claimStakingReward(_account);
  }

  /**
   * @dev set stake vault address
   * @param _stakeVault stake vault address
   */
  function setStakeVault(address _stakeVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_stakeVault != address(0), "stake vault is the zero address");
    stakeVault = _stakeVault;
  }

  /* ==================== View Functions ==================== */

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


  // Check if it's time to harvest. If not, return true
  function noHarvest() public view returns (bool) {
    return lastHarvestTime + harvestTimeGap > block.timestamp;
  }

  /**
   * @dev Get LP token amount by providing USDT amount to add
   * @param _usdtAmount amount of USDT
   * @return LP token amount
   */
  function getLpAmount(uint256 _usdtAmount) public view returns (uint256) {
    return IStableSwapPoolInfo(stableSwapPoolInfo).get_add_liquidity_mint_amount(stableSwapPool, [0, _usdtAmount]);
  }

  function getCoinsAmount(uint256 _lpAmount) public view returns (uint256 _lisUSDAmount, uint256 _usdtAmount) {
    uint256[2] memory coinsAmount = IStableSwapPoolInfo(stableSwapPoolInfo).calc_coins_amount(
      stableSwapPool,
      _lpAmount
    );
    _lisUSDAmount = coinsAmount[0];
    _usdtAmount = coinsAmount[1];
  }
}
