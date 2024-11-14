// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { CommonListaDistributor, SafeERC20 } from "./CommonListaDistributor.sol";
import { IStaking } from "./interfaces/IStaking.sol";
import { IStakingVault } from "./interfaces/IStakingVault.sol";
import { IStableSwap, IStableSwapPoolInfo } from "./interfaces/IStableSwap.sol";
import { IVault } from "./interfaces/IVault.sol";

/**
 * @title USDTLpListaDistributor
 * @dev This contract is used to stake USDT and earn token emission rewards.
 */
contract USDTLpListaDistributor is CommonListaDistributor, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  // lisUSD/USDT PancakeStableSwapTwoPool coins[0]
  IERC20 public lisUSD;
  // lisUSD/USDT PancakeStableSwapTwoPool coins[1]
  IERC20 public usdt;
  // pancake staking address
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

  // lisUSD/USDT PancakeStableSwapTwoPool contract address
  address public stableSwapPool;

  // PancakeStableSwapTwoPoolInfo contract address
  address private poolInfo;

  event StakeRewardClaimed(address indexed receiver, uint256 amount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize contract
   * @param _admin admin address
   * @param _manager manager address
   */
  function initialize(
    address _admin,
    address _manager,
    address _vault,
    address _pancakeStaking,
    address _stakeVault,
    address _stableswap,
    address _poolInfo
  ) external initializer {
    require(_admin != address(0), "admin is the zero address");
    require(_manager != address(0), "manager is the zero address");
    require(_vault != address(0), "vault is the zero address");
    require(_pancakeStaking != address(0), "pancake staking is the zero address");
    require(_stakeVault != address(0), "stake vault is the zero address");
    require(_stableswap != address(0), "stableswap is the zero address");
    require(_poolInfo != address(0), "pool info is the zero address");

    __AccessControl_init();
    __Pausable_init();

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(MANAGER, _manager);
    _setupRole(VAULT, _vault);

    stableSwapPool = _stableswap;
    poolInfo = _poolInfo;

    lisUSD = IERC20(IStableSwap(stableSwapPool).coins(0));
    usdt = IERC20(IStableSwap(stableSwapPool).coins(1));
    lpToken = IStableSwap(stableSwapPool).token();
    vault = IVault(_vault);
    staking = _pancakeStaking;
    stakeVault = _stakeVault;
    name = string.concat("Lista-USDT-Staking", IERC20Metadata(lpToken).name());
    symbol = string.concat("Lista USDT Staking ", IERC20Metadata(lpToken).symbol(), " Distributor");
  }

  modifier onlyStakeVault() {
    require(msg.sender == stakeVault, "only stake vault can call this function");
    _;
  }

  /**
   * @dev deposit USDT
   * @param usdtAmount amount of USDT to stake
   */
  function deposit(uint256 usdtAmount, uint256 minLpAmount) external {
    require(usdtAmount > 0, "Invalid usdt amount");
    uint256 expectLpAmount = getLpAmount(usdtAmount);
    require(expectLpAmount >= minLpAmount, "Invalid min lp amount");

    // transfer USDT to this contract
    usdt.safeIncreaseAllowance(stableSwapPool, usdtAmount);
    usdt.safeTransferFrom(msg.sender, address(this), usdtAmount);

    uint256 actualLpAmount = IERC20(lpToken).balanceOf(address(this));
    IStableSwap(stableSwapPool).add_liquidity([0, usdtAmount], minLpAmount);
    actualLpAmount = IERC20(lpToken).balanceOf(address(this)) - actualLpAmount;

    require(actualLpAmount >= minLpAmount, "Invalid lp amount minted");

    // update balance, reward and total supply
    _deposit(msg.sender, actualLpAmount);
    // stake lp token
    _depositLp(msg.sender, actualLpAmount);
  }

  /**
   * @dev withdraw LP token
   * @param lpAmount amount of LP token
   */
  function withdraw(uint256 lpAmount, uint256 minLisUSDAmount, uint256 minUSDTAmount) external {
    // check lisUSD and USDT amount
    (uint256 expectLisUSDAmount, uint256 expectUSDTAmount) = getCoinsAmount(lpAmount);
    require(minLisUSDAmount <= expectLisUSDAmount, "Invalid lisUSD amount");
    require(minUSDTAmount <= expectUSDTAmount, "Invalid USDT amount");

    uint256 expectLpAmount = IStableSwap(stableSwapPool).calc_token_amount(
      [expectLisUSDAmount, expectUSDTAmount],
      false
    );
    require(lpAmount >= expectLpAmount, "Invalid lp amount");

    _withdraw(msg.sender, lpAmount);
    _withdrawLp(msg.sender, lpAmount);

    uint256 lisUSDAmountBefore = lisUSD.balanceOf(address(this));
    uint256 usdtAmountBefore = usdt.balanceOf(address(this));
    // don't need to approve
    IStableSwap(stableSwapPool).remove_liquidity(lpAmount, [minLisUSDAmount, minUSDTAmount]);
    uint256 lisUSDAmountActual = lisUSD.balanceOf(address(this)) - lisUSDAmountBefore;
    uint256 usdtAmountActual = usdt.balanceOf(address(this)) - usdtAmountBefore;
    require(lisUSDAmountActual >= minLisUSDAmount, "Invalid lisUSD amount received");
    require(usdtAmountActual >= minUSDTAmount, "Invalid USDT amount received");

    // transfer lisUSD and USDT to user
    lisUSD.safeTransfer(msg.sender, lisUSDAmountActual);
    usdt.safeTransfer(msg.sender, usdtAmountActual);
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

    // NOTE: different from ERC20LpListaDistributor
    // key is usdt address
    IStaking(staking).deposit(address(usdt), amount);

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

    // NOTE: different from ERC20LpListaDistributor
    // receiver is this contract; key is usdt address
    IStaking(staking).withdraw(address(this), address(usdt), amount);
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
  function vaultClaimStakingReward(address _account) external onlyStakeVault returns (uint256) {
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
   * @dev harvest stake reward from third-party staking pool
   */
  function harvest() external {
    IStaking(staking).harvest(address(usdt));
  }

  /**
   * @dev Get LP token amount by providing USDT amount to add
   * @param _usdtAmount amount of USDT
   * @return LP token amount
   */
  function getLpAmount(uint256 _usdtAmount) public view returns (uint256) {
    return IStableSwapPoolInfo(poolInfo).get_add_liquidity_mint_amount(stableSwapPool, [0, _usdtAmount]);
  }

  function getCoinsAmount(uint256 _lpAmount) public view returns (uint256 _lisUSDAmount, uint256 _usdtAmount) {
    uint256[2] memory coinsAmount = IStableSwapPoolInfo(poolInfo).calc_coins_amount(stableSwapPool, _lpAmount);
    _lisUSDAmount = coinsAmount[0];
    _usdtAmount = coinsAmount[1];
  }
}
