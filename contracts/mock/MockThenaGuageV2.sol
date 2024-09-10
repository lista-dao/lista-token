pragma solidity ^0.8.10;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IERC20Mintable.sol";

contract MockThenaGaugeV2 is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    event LPTokenDeposited(address indexed lpToken, address indexed receiver, uint256 amount);
    event LPTokenWithdrawn(address indexed lpToken, address indexed receiver, uint256 amount);
    event RewardClaimed(address indexed receiver, uint256 listaAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);

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
    // total supply
    uint256 public totalSupply;
    // balance of each account
    // account -> balance
    mapping(address => uint256) public balanceOf;
    // reward token
    address public rewardToken;
    // stake token
    address public stakeToken;

    function initialize(address _rewardToken, address _stakeToken) public initializer {
        require(_rewardToken != address(0), "rewardToken cannot be zero address");
        require(_stakeToken != address(0), "stakeToken cannot be zero address");
        __Ownable_init();

        rewardToken = _rewardToken;
        stakeToken = _stakeToken;
    }

    // deposit token and get rewards
    function deposit(uint256 amount) external {
        require(amount > 0, "cannot deposit zero");
        address _account = msg.sender;
        IERC20(stakeToken).transferFrom(_account, address(this), amount);
        uint256 balance = balanceOf[_account];
        uint256 supply = totalSupply;

        balanceOf[_account] = balance + amount;
        totalSupply = supply + amount;

        _updateReward(_account, balance, supply);

        emit Transfer(address(0), _account, amount);
        emit LPTokenDeposited(address(stakeToken), _account, amount);
    }

    // withdraw token
    function withdraw(uint256 amount) external {
        address _account = msg.sender;
        uint256 balance = balanceOf[_account];
        uint256 supply = totalSupply;
        require(balance >= amount, "insufficient balance");
        balanceOf[_account] = balance - amount;
        totalSupply = supply - amount;

        IERC20(stakeToken).transfer(_account, amount);

        _updateReward(_account, balance, supply);

        emit Transfer(_account, address(0), amount);
        emit LPTokenWithdrawn(address(stakeToken), _account, amount);
    }

    // when account do write operation, update reward
    function _updateReward(address _account, uint256 balance, uint256 supply) internal {
        // update reward
        uint256 updated = block.timestamp;
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
        uint256 updated = block.timestamp;
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


    function getReward() external returns (uint256) {
        address _account = msg.sender;
        uint256 amount = _claimReward(_account);
        if (amount > 0) {
            IERC20Mintable(rewardToken).mint(address(this), amount);
            IERC20(rewardToken).safeTransfer(_account, amount);
        }
        return amount;
    }

    function _claimReward(address _account) internal returns (uint256) {
        _updateReward(_account, balanceOf[_account], totalSupply);
        uint256 amount = storedPendingReward[_account];
        delete storedPendingReward[_account];

        emit RewardClaimed(_account, amount);
        return amount;
    }

    function setRewardRate(uint256 _rewardRate) onlyOwner external {
        _updateReward(address(0), 0, totalSupply);
        rewardRate = _rewardRate;

        lastUpdate = block.timestamp;
    }

}
