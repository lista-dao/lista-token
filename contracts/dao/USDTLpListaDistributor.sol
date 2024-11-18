// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { CommonListaDistributor, SafeERC20, IERC20 } from "./CommonListaDistributor.sol";

import { IStakingVault } from "./interfaces/IStakingVault.sol";
import { IStableSwap, IStableSwapPoolInfo } from "./interfaces/IStableSwap.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IV2Wrapper } from "./interfaces/IV2Wrapper.sol";

/**
 * @title USDTLpListaDistributor
 * @dev This contract enables users to provide USDT liquidity to PancakeStableSwapTwoPool and
 *      earn both LISTA and CAKE rewards by staking LP token to PancakeSwap Stable-LP Farming contract.
 */
contract USDTLpListaDistributor is CommonListaDistributor, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  /* ============ PancakeSwap Addresses ============ */
  // PancakeSwap lisUSD/USDT StableSwap contract address
  address public immutable stableSwapPool;
  // PancakeStableSwapTwoPoolInfo contract address
  address private immutable stableSwapPoolInfo;
  // PancakeSwap Stable-LP Farming contract address
  IV2Wrapper public immutable v2wrapper;
  // PancakeSwap lisUSD/USDT StableSwap coins[0]
  IERC20 public lisUSD;
  // PancakeSwap lisUSD/USDT StableSwap coins[1]
  IERC20 public usdt;
  // CAKE is the LP Farming reward token
  address public cake;

  /* ============ StakingVault Address ============ */
  // StakingVault address
  address public stakeVault;

  /* ============ State Variables ============ */
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
  // emergency mode
  // if emergency mode is on, the contract will not stake LP token to v2wrapper on depositing usdt
  bool public emergencyMode;
  // deposit is disabled when isActive is false
  bool public isActive;

  /* ============ Events ============ */
  event USDTStaked(address indexed lpToken, uint256 usdtAmount, uint256 lpAmount);
  event LpUnstaked(address indexed lpToken, uint256 usdtAmount, uint256 lisUSDAmount, uint256 lpAmount);
  event StakeRewardClaimed(address indexed receiver, uint256 amount);
  event Harvest(address usdt, address distributor, uint256 amount);
  event WithdrawLp(address usdt, address distributor, address account, uint256 amount);
  event DepositLp(address usdt, address distributor, uint256 amount);
  event StopEmergencyMode(address lpToken, uint256 lpAmount);
  event EmergencyWithdraw(address farming, uint256 lpAmount);
  event SetHarvestTimeGap(uint256 harvestTimeGap);
  event SetIsActive(bool isActive);

  modifier onlyActive() {
    require(isActive, "Distributor is not active");
    _;
  }

  modifier notInEmergencyMode() {
    require(!emergencyMode, "In emergency mode");
    _;
  }

  modifier onlyStakeVault() {
    require(msg.sender == stakeVault, "Only stake vault can call this function");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  /**
   * @param _stableswap lisUSD/USDT PancakeStableSwapTwoPool address
   * @param _poolInfo PancakeStableSwapTwoPoolInfo address
   * @param _v2wrapper Stable-LP V2wWapper address
   */
  constructor(address _stableswap, address _poolInfo, address _v2wrapper) {
    require(_stableswap != address(0) && _poolInfo != address(0) && _v2wrapper != address(0), "Invalid address");
    _disableInitializers();
    stableSwapPool = _stableswap;
    stableSwapPoolInfo = _poolInfo;
    v2wrapper = IV2Wrapper(_v2wrapper);
  }

  /**
   * @dev initialize contract
   * @param _admin admin address
   * @param _manager manager address
   * @param _vault ListaVault address
   * @param _stakeVault StakingVault address
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    address _vault,
    address _stakeVault
  ) external initializer {
    require(_admin != address(0), "admin is the zero address");
    require(_manager != address(0), "manager is the zero address");
    require(_vault != address(0), "vault is the zero address");
    require(_stakeVault != address(0), "stake vault is the zero address");

    __ReentrancyGuard_init();
    __AccessControl_init();
    __Pausable_init();

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(MANAGER, _manager);
    _setupRole(VAULT, _vault);
    _setupRole(PAUSER, _pauser);

    lisUSD = IERC20(IStableSwap(stableSwapPool).coins(0));
    usdt = IERC20(IStableSwap(stableSwapPool).coins(1));
    lpToken = IStableSwap(stableSwapPool).token();

    vault = IVault(_vault);
    stakeVault = _stakeVault;
    require(v2wrapper.rewardToken() == IStakingVault(stakeVault).rewardToken(), "Invalid reward token");
    cake = IStakingVault(stakeVault).rewardToken();

    harvestTimeGap = 1 hours;
    isActive = true;

    name = "USDT LP-Staked Reward Lista Distributor";
    symbol = "USDTLpListaDistributor";
  }

  /* ================ External Functions ================ */

  /**
   * @dev Deposit USDT to PancakeStableSwapTwoPool and stake LP token to farming contract
   * @param usdtAmount amount of USDT to deposit
   * @param minLpAmount minimum amount of LP token required to mint
   */
  function deposit(uint256 usdtAmount, uint256 minLpAmount) external onlyActive {
    require(usdtAmount > 0, "Invalid usdt amount");
    uint256 expectLpAmount = getLpToMint(usdtAmount);
    require(expectLpAmount >= minLpAmount, "Invalid min lp amount");

    // 1. Transfer USDT to this contract
    usdt.safeIncreaseAllowance(stableSwapPool, usdtAmount);
    usdt.safeTransferFrom(msg.sender, address(this), usdtAmount);

    // 2. Add USDT to PancakeStableSwapTwoPool
    uint256 actualLpAmount = IERC20(lpToken).balanceOf(address(this));
    IStableSwap(stableSwapPool).add_liquidity([0, usdtAmount], minLpAmount);
    actualLpAmount = IERC20(lpToken).balanceOf(address(this)) - actualLpAmount;

    require(actualLpAmount >= minLpAmount, "Invalid lp amount minted");

    // 3. Update user's LP balance and LISTA reward, and distributor's LP total supply
    _deposit(msg.sender, actualLpAmount);

    // 4. Stake the received LP token to farming contract only if not in emergency mode
    if (!emergencyMode) _stakeLp(msg.sender, actualLpAmount);

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

    // 3. Unstake LP token from farming contract if not in emergency mode
    if (!emergencyMode) _unstakeLp(msg.sender, lpAmount);

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
  function harvest() external whenNotPaused notInEmergencyMode returns (uint256) {
    address distributor = address(this);

    if (noHarvest()) return 0;

    // Claim CAKE rewards from V2Wrapper
    uint256 beforeBalance = IERC20(cake).balanceOf(distributor);
    lastHarvestTime = block.timestamp;
    v2wrapper.deposit(0, false);
    uint256 claimed = IERC20(cake).balanceOf(distributor) - beforeBalance;

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
  function claimStakeReward() external whenNotPaused returns (uint256) {
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

    _updateStakeReward(_account, balanceOf[_account]);

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
    _updateStakeReward(_account, balanceOf[_account]);

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

    emit WithdrawLp(address(usdt), distributor, distributor, amount);
    emit LPTokenWithdrawn(address(lpToken), _account, amount);
  }

  // Claim CAKE reward; perform by staking vault or user
  function _claimStakingReward(address _account) internal returns (uint256) {
    _updateStakeReward(_account, balanceOf[_account]);
    uint256 amount = stakeStoredPendingReward[_account];
    delete stakeStoredPendingReward[_account];

    emit StakeRewardClaimed(_account, amount);
    return amount;
  }

  // Calculate CAKE reward if any write operation is performed
  function _updateStakeReward(address _account, uint256 _balance) internal {
    // update reward
    uint256 updated = stakePeriodFinish;
    if (updated > block.timestamp) updated = block.timestamp;
    uint256 duration = updated - stakeLastUpdate;
    if (duration > 0) stakeLastUpdate = uint32(updated);

    if (duration > 0 && totalSupply > 0) {
      stakeRewardIntegral += (duration * stakeRewardRate * 1e18) / totalSupply;
    }
    if (_account != address(0)) {
      uint256 integralFor = stakeRewardIntegralFor[_account];
      if (stakeRewardIntegral > integralFor) {
        stakeStoredPendingReward[_account] += (_balance * (stakeRewardIntegral - integralFor)) / 1e18;
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
    _updateStakeReward(address(0), 0);
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

  /**
   * @dev stop emergency mode
   */
  function stopEmergencyMode() external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(emergencyMode, "Emergency mode is off");
    // 1. set emergency mode to false
    emergencyMode = false;

    // 2. stake lp token to farming contract
    uint256 balance = IERC20(lpToken).balanceOf(address(this));
    IERC20(lpToken).safeApprove(address(v2wrapper), balance);
    // don't harvest rewards
    v2wrapper.deposit(balance, true);

    emit StopEmergencyMode(lpToken, balance);
  }

  /**
   * @dev emergency withdraw LP token from farming contract
   */
  function emergencyWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) notInEmergencyMode {
    uint256 lpAmount = IERC20(lpToken).balanceOf(address(this));
    v2wrapper.emergencyWithdraw();
    lpAmount = IERC20(lpToken).balanceOf(address(this)) - lpAmount;

    emergencyMode = true;

    emit EmergencyWithdraw(address(v2wrapper), lpAmount);
  }

  function setHarvestTimeGap(uint256 _harvestTimeGap) external onlyRole(MANAGER) {
    harvestTimeGap = _harvestTimeGap;
    emit SetHarvestTimeGap(_harvestTimeGap);
  }

  function setIsActive(bool _isActive) external onlyRole(MANAGER) {
    isActive = _isActive;
    emit SetIsActive(_isActive);
  }

  /* ==================== View Functions ==================== */

  /**
   * @dev get stake claimable reward amount
   * @param account account address
   * @return reward amount
   */
  function getStakeClaimableReward(address account) external view returns (uint256) {
    uint256 updated = stakePeriodFinish;
    if (updated > block.timestamp) updated = block.timestamp;
    uint256 duration = updated - stakeLastUpdate;
    uint256 integral = stakeRewardIntegral;
    if (totalSupply > 0) {
      integral += (duration * stakeRewardRate * 1e18) / totalSupply;
    }
    uint256 integralFor = stakeRewardIntegralFor[account];
    return stakeStoredPendingReward[account] + (balanceOf[account] * (integral - integralFor)) / 1e18;
  }

  // Check if it's time to harvest. If not, return true
  function noHarvest() public view returns (bool) {
    return lastHarvestTime + harvestTimeGap > block.timestamp;
  }

  /**
   * @dev Get LP token amount to mint by providing USDT amount to add
   * @param _usdtAmount amount of USDT
   * @return LP token amount
   */
  function getLpToMint(uint256 _usdtAmount) public view returns (uint256) {
    return IStableSwapPoolInfo(stableSwapPoolInfo).get_add_liquidity_mint_amount(stableSwapPool, [0, _usdtAmount]);
  }

  /**
   * @dev Get lisUSD and USDT amount by providing LP token amount to remove
   * @param _lpAmount amount of LP token
   */
  function getCoinsAmount(uint256 _lpAmount) public view returns (uint256 _lisUSDAmount, uint256 _usdtAmount) {
    uint256[2] memory coinsAmount = IStableSwapPoolInfo(stableSwapPoolInfo).calc_coins_amount(
      stableSwapPool,
      _lpAmount
    );
    _lisUSDAmount = coinsAmount[0];
    _usdtAmount = coinsAmount[1];
  }
}
