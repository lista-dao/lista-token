pragma solidity ^0.8.10;

import "./CommonListaDistributor.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IStakingVault.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
  * @title ERC20LpListaDistributor
  * @dev lista token stake and distributor for erc20 LP token
 */
contract ERC20LpListaDistributor is CommonListaDistributor, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

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
    // staking vault role
    bytes32 public constant STAKING_VAULT = keccak256("STAKING_VAULT");

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

    /**
     * @dev deposit LP token to get rewards
     * @param amount amount of LP token
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Cannot deposit zero");
        _deposit(msg.sender, amount);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        _depositLp(msg.sender, amount);
    }

    /**
     * @dev withdraw LP token
     * @param amount amount of LP token
     */
    function withdraw(uint256 amount) external {
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
    function notifyStakingReward(uint256 amount) external onlyRole(STAKING_VAULT) {
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
    function vaultClaimStakingReward(address _account) onlyRole(STAKING_VAULT) external returns (uint256) {
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
        IStaking(staking).harvest(lpToken);
    }
}