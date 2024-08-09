// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IVault.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
  * @title CommonListaDistributor
  * @dev lista token stake and distributor
 */
abstract contract CommonListaDistributor is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    event LPTokenDeposited(address indexed lpToken, address indexed receiver, uint256 amount);
    event LPTokenWithdrawn(address indexed lpToken, address indexed receiver, uint256 amount);
    event RewardClaimed(address indexed receiver, uint256 listaAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    // LP token address
    address public lpToken;
    // lista Vault address
    IVault public vault;
    // token name
    string public name;
    // token symbol
    string public symbol;
    // total supply
    uint256 public totalSupply;
    // balance of each account
    // account -> balance
    mapping(address => uint256) public balanceOf;
    // period finish
    uint256 public periodFinish;
    // last update operation timestamp
    uint256 public lastUpdate;
    // reward of per token
    uint256 public rewardIntegral;
    // reward of per second
    uint256 public rewardRate;
    // reward integral for each account on last update time
    // account -> reward integral
    mapping(address => uint256) public rewardIntegralFor;
    // pending reward for each account
    // account -> pending reward
    mapping(address => uint256) private storedPendingReward;
    // distributor id
    uint16 public distributorId;
    // manager role
    bytes32 public constant MANAGER = keccak256("MANAGER");
    // vault role
    bytes32 public constant VAULT = keccak256("VAULT");
    // pause role
    bytes32 public constant PAUSER = keccak256("PAUSER");
    // reward duration is 1 week
    uint256 constant REWARD_DURATION = 1 weeks;
    // decimals
    uint8 public constant decimals = 18;

    // deposit token and get rewards
    function _deposit(address _account, uint256 amount) internal {
        require(amount > 0, "cannot deposit zero");
        uint256 balance = balanceOf[_account];
        uint256 supply = totalSupply;

        balanceOf[_account] = balance + amount;
        totalSupply = supply + amount;

        _updateReward(_account, balance, supply);

        if (getWeek(block.timestamp) >= getWeek(periodFinish)) _fetchRewards();

        emit Transfer(address(0), _account, amount);
        emit LPTokenDeposited(address(lpToken), _account, amount);
    }

    // withdraw token
    function _withdraw(address _account, uint256 amount) internal {
        uint256 balance = balanceOf[_account];
        uint256 supply = totalSupply;
        require(balance >= amount, "insufficient balance");
        balanceOf[_account] = balance - amount;
        totalSupply = supply - amount;

        _updateReward(_account, balance, supply);
        if (getWeek(block.timestamp) >= getWeek(periodFinish)) _fetchRewards();

        emit Transfer(_account, address(0), amount);
        emit LPTokenWithdrawn(address(lpToken), _account, amount);
    }

    // when account do write operation, update reward
    function _updateReward(address _account, uint256 balance, uint256 supply) internal {
        // update reward
        uint256 updated = periodFinish;
        if (updated > block.timestamp) updated = block.timestamp;
        uint256 duration = updated - lastUpdate;
        if (duration > 0) lastUpdate = uint32(updated);

        if (duration > 0 && supply > 0) {
            rewardIntegral += (duration * rewardRate * 1e18) / supply;
        }
        if (_account != address(0)) {
            uint256 integralFor = rewardIntegralFor[_account];
            if (rewardIntegral > integralFor) {

                storedPendingReward[_account] += (balance * (rewardIntegral - integralFor)) / 1e18;
                rewardIntegralFor[_account] = rewardIntegral;
            }
        }
    }

    /**
      * @dev get claimable reward amount
      * @param account account address
      * @return reward amount
      */
    function claimableReward(
        address account
    ) external view returns (uint256) {
        uint256 updated = periodFinish;
        if (updated > block.timestamp) updated = block.timestamp;
        uint256 duration = updated - lastUpdate;
        uint256 balance = balanceOf[account];
        uint256 supply = totalSupply;

        uint256 integral = rewardIntegral;
        if (supply > 0) {
            integral += (duration * rewardRate * 1e18) / supply;
        }
        uint256 integralFor = rewardIntegralFor[account];
        return storedPendingReward[account] + ((balance * (integral - integralFor)) / 1e18);
    }

    /**
      * @dev get account reward rate
      * @param account account address
      * @return reward rate
      */
    function getAccountRewardRate(address account) external view returns (uint256) {
        uint256 balance = balanceOf[account];
        uint256 supply = totalSupply;
        if (supply == 0) return 0;
        return (rewardRate * balance) / supply;
    }

    /**
      * @dev claim reward, only vault can call this function
      * @param _account account address
      * @return reward amount
      */
    function vaultClaimReward(address _account) onlyRole(VAULT) external returns (uint256) {
        return _claimReward(_account);
    }

    function claimReward() external returns (uint256) {
        address _account = msg.sender;
        uint256 amount = _claimReward(_account);
        require(amount > 0, "no reward to claim");
        vault.transferAllocatedTokens(distributorId, _account, amount);
        return amount;
    }

    function _claimReward(address _account) internal returns (uint256) {
        _updateReward(_account, balanceOf[_account], totalSupply);
        uint256 amount = storedPendingReward[_account];
        delete storedPendingReward[_account];

        emit RewardClaimed(_account, amount);
        return amount;
    }

    /**
      * @dev fetch rewards weekly
      */
    function fetchRewards() external {
        require(getWeek(block.timestamp) >= getWeek(periodFinish), "Can only fetch once per week");
        _updateReward(address(0), 0, totalSupply);
        _fetchRewards();
    }

    // fetch rewards
    function _fetchRewards() internal {
        uint256 amount;
        uint16 id = distributorId;
        if (id > 0) {
            amount = vault.allocateNewEmissions(id);
        }

        uint256 _periodFinish = periodFinish;
        if (block.timestamp < _periodFinish) {
            uint256 remaining = _periodFinish - block.timestamp;
            amount += remaining * rewardRate;
        }

        rewardRate = amount / REWARD_DURATION;

        lastUpdate = block.timestamp;
        periodFinish = block.timestamp + REWARD_DURATION;
    }

    /**
      * @dev notify registered emission id, only vault can call this function
      * @param _distributorId emission id
      * @return success
      */
    function notifyRegisteredId(uint16 _distributorId) onlyRole(VAULT) external returns (bool) {
        require(distributorId == 0, "Already registered");
        require(_distributorId > 0, "Invalid emission id");
        distributorId = _distributorId;
        return true;
    }

    /**
      * @dev get week number by timestamp
      * @param timestamp timestamp
      * @return week number
      */
    function getWeek(uint256 timestamp) public view returns (uint16) {
        return vault.getWeek(timestamp);
    }


    /**
     * @dev Flips the pause state
     */
    function togglePause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused() ? _unpause() : _pause();
    }

    /**
     * @dev pause the contract
     */
    function pause() external onlyRole(PAUSER) {
        _pause();
    }


    // storage gap
    uint256[49] __gap;
}