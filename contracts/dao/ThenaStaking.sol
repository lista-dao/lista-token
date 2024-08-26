pragma solidity ^0.8.10;

import "./interfaces/IStaking.sol";
import "./interfaces/IStakingVault.sol";
import "./interfaces/IGaugeV2.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ThenaStaking is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct Pool {
        address lpToken;
        address rewardToken;
        address poolAddress;
        address distributor;
        bool isActive;
    }
    // staking vault address
    address public vault;
    // lp token address -> pool info
    mapping(address => Pool) public pools;

    event Harvest(address pool, address distributor, uint256 amount);
    event DepositLp(address pool, address distributor, uint256 amount);
    event WithdrawLp(address pool, address distributor, address account, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev initialize contract
      * @param _owner owner address
      * @param _vault staking vault address
      */
    function initialize(address _owner, address _vault) public initializer {
        require(_owner != address(0), "owner cannot be zero address");
        require(_vault != address(0), "vault cannot be zero address");
        __Ownable_init();
        transferOwnership(_owner);

        vault = _vault;
    }

    modifier onlyPoolActive(address pool) {
        require(pools[pool].isActive, "Pool is not active");
        _;
    }

    modifier onlyDistributor(address pool) {
        require(pools[pool].distributor == msg.sender, "Only distributor can call this function");
        _;
    }

    /**
      * @dev deposit lp token to staking pool
      * @param pool lp token address
      * @param amount lp token amount
      */
    function deposit(address pool, uint256 amount) external onlyPoolActive(pool) onlyDistributor(pool) {
        Pool memory poolInfo = pools[pool];
        IERC20(poolInfo.lpToken).safeTransferFrom(poolInfo.distributor, address(this), amount);
        IERC20(poolInfo.lpToken).safeApprove(poolInfo.poolAddress, amount);

        // deposit lp token and claim rewards
        uint256 beforeBalance = IERC20(poolInfo.rewardToken).balanceOf(address(this));
        IGaugeV2(poolInfo.poolAddress).deposit(amount);
        IGaugeV2(poolInfo.poolAddress).getReward();

        uint256 claimed = IERC20(poolInfo.rewardToken).balanceOf(address(this)) - beforeBalance;

        if (claimed > 0) {
            // send rewards to vault
            IERC20(poolInfo.rewardToken).safeApprove(vault, claimed);
            IStakingVault(vault).sendRewards(poolInfo.distributor, claimed);
            emit Harvest(pool, poolInfo.distributor, claimed);
        }

        emit DepositLp(pool, poolInfo.distributor, amount);
    }

    /**
      * @dev harvest rewards
      * @param pool lp token address
      */
    function harvest(address pool) external returns (uint256) {
        Pool memory poolInfo = pools[pool];

        // claim rewards
        uint256 beforeBalance = IERC20(poolInfo.rewardToken).balanceOf(address(this));
        IGaugeV2(poolInfo.poolAddress).getReward();
        uint256 claimed = IERC20(poolInfo.rewardToken).balanceOf(address(this)) - beforeBalance;

        if (claimed > 0) {
            // send rewards to vault
            IERC20(poolInfo.rewardToken).safeApprove(vault, claimed);
            IStakingVault(vault).sendRewards(poolInfo.distributor, claimed);
            emit Harvest(pool, poolInfo.distributor, claimed);
        }

        return claimed;
    }

    /**
      * @dev withdraw lp token from staking pool
      * @param to receiver address
      * @param pool lp token address
      * @param amount lp token amount
      */
    function withdraw(address to, address pool, uint256 amount) external onlyDistributor(pool) {
        Pool memory poolInfo = pools[pool];
        // withdraw lp token and claim rewards
        uint256 beforeBalance = IERC20(poolInfo.lpToken).balanceOf(address(this));
        IGaugeV2(poolInfo.poolAddress).withdraw(amount);
        IGaugeV2(poolInfo.poolAddress).getReward();
        uint256 claimed = IERC20(poolInfo.rewardToken).balanceOf(address(this)) - beforeBalance;

        if (claimed > 0) {
            // send rewards to vault
            IERC20(poolInfo.rewardToken).safeApprove(vault, claimed);
            IStakingVault(vault).sendRewards(poolInfo.distributor, claimed);
            emit Harvest(pool, poolInfo.distributor, claimed);
        }

        IERC20(poolInfo.lpToken).safeTransfer(to, amount);

        emit WithdrawLp(pool, poolInfo.distributor, to, amount);
    }

    /**
      * @dev register staking pool
      * @param lpToken lp token address
      * @param rewardToken reward token address
      * @param poolAddress staking pool address
      * @param distributor distributor address
      */
    function registerPool(address lpToken, address rewardToken, address poolAddress, address distributor) external onlyOwner {
        require(!pools[lpToken].isActive, "Pool is active");

        pools[lpToken] = Pool({
            lpToken: lpToken,
            rewardToken: rewardToken,
            poolAddress: poolAddress,
            distributor: distributor,
            isActive: true
        });
    }

    /**
      * @dev unregister staking pool
      * @param lpToken lp token address
      */
    function unregisterPool(address lpToken) external onlyOwner {
        require(pools[lpToken].isActive, "Pool is not active");

        pools[lpToken].isActive = false;
    }
}
