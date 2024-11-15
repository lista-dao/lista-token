pragma solidity ^0.8.10;

import "./interfaces/IStaking.sol";
import "./interfaces/IStakingVault.sol";
import "./interfaces/IV2Wrapper.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract PancakeStaking is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct Pool {
        address lpToken;
        address rewardToken;
        address poolAddress;
        address distributor;
        bool isActive;
        uint256 lastHarvestTime;
    }
    // staking vault address
    address public vault;
    // lp token address -> pool info
    mapping(address => Pool) public pools;

    uint256 public harvestTimeGap;

    bool public emergencyMode;

    event Harvest(address pool, address distributor, uint256 amount);
    event DepositLp(address pool, address distributor, uint256 amount);
    event WithdrawLp(address pool, address distributor, address account, uint256 amount);
    event RegisterPool(address lpToken, address pool, address distributor);
    event UnRegisterPool(address lpToken);
    event SetEmergencyMode(bool emergencyMode);
    event EmergencyWithdraw(address farming, uint256 lpAmount);

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
        __ReentrancyGuard_init();
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

    modifier notInEmergencyMode() {
        require(!emergencyMode, "In emergency mode");
        _;
    }

    /**
      * @dev deposit lp token to staking pool
      * @param pool lp token address
      * @param amount lp token amount
      */
    function deposit(address pool, uint256 amount) external onlyPoolActive(pool) onlyDistributor(pool) notInEmergencyMode nonReentrant {
        Pool storage poolInfo = pools[pool];
        IERC20(poolInfo.lpToken).safeTransferFrom(poolInfo.distributor, address(this), amount);
        IERC20(poolInfo.lpToken).safeApprove(poolInfo.poolAddress, amount);

        // deposit lp token and claim rewards
        uint256 beforeBalance = IERC20(poolInfo.rewardToken).balanceOf(address(this));
        if (poolInfo.lastHarvestTime + harvestTimeGap > block.timestamp) {
            IV2Wrapper(poolInfo.poolAddress).deposit(amount, true);
        } else {
            poolInfo.lastHarvestTime = block.timestamp;
            IV2Wrapper(poolInfo.poolAddress).deposit(amount, false);
        }

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
    function harvest(address pool) external nonReentrant returns (uint256) {
        Pool storage poolInfo = pools[pool];
        if (poolInfo.lastHarvestTime + harvestTimeGap > block.timestamp) {
            return 0;
        }

        // claim rewards
        uint256 beforeBalance = IERC20(poolInfo.rewardToken).balanceOf(address(this));
        IV2Wrapper(poolInfo.poolAddress).deposit(0, false);
        uint256 claimed = IERC20(poolInfo.rewardToken).balanceOf(address(this)) - beforeBalance;
        poolInfo.lastHarvestTime = block.timestamp;

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
    function withdraw(address to, address pool, uint256 amount) external onlyDistributor(pool) nonReentrant {
        Pool storage poolInfo = pools[pool];

        if (emergencyMode) {
            uint256 lpBalance = IERC20(poolInfo.lpToken).balanceOf(address(this));
            require(lpBalance >= amount, "Not enough LP token to withdraw");

            IERC20(poolInfo.lpToken).safeTransfer(to, amount);
            emit WithdrawLp(pool, poolInfo.distributor, to, amount);
            return;
        }

        // withdraw lp token and claim rewards
        uint256 beforeBalance = IERC20(poolInfo.rewardToken).balanceOf(address(this));
        if (poolInfo.lastHarvestTime + harvestTimeGap > block.timestamp) {
            IV2Wrapper(poolInfo.poolAddress).withdraw(amount, true);
        } else {
            poolInfo.lastHarvestTime = block.timestamp;
            IV2Wrapper(poolInfo.poolAddress).withdraw(amount, false);
        }
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
      * @param poolAddress staking pool address
      * @param distributor distributor address
      */
    function registerPool(address lpToken, address poolAddress, address distributor) external onlyOwner {
        require(!pools[lpToken].isActive, "Pool is active");

        pools[lpToken] = Pool({
            lpToken: lpToken,
            rewardToken: IStakingVault(vault).rewardToken(),
            poolAddress: poolAddress,
            distributor: distributor,
            isActive: true,
            lastHarvestTime: 0
        });

        emit RegisterPool(lpToken, poolAddress, distributor);
    }

    /**
      * @dev unregister staking pool
      * @param lpToken lp token address
      */
    function unregisterPool(address lpToken) external onlyOwner {
        require(pools[lpToken].isActive, "Pool is not active");

        pools[lpToken].isActive = false;

        emit UnRegisterPool(lpToken);
    }

    /**
      * @dev set harvest time gap
      * @param _harvestTimeGap harvest time gap
      */
    function setHarvestTimeGap(uint256 _harvestTimeGap) external onlyOwner {
        harvestTimeGap = _harvestTimeGap;
    }

    /**
      * @dev set emergency mode
      * @param _emergencyMode emergency mode
      */
    function setEmergencyMode(bool _emergencyMode) external onlyOwner {
        emergencyMode = _emergencyMode;
        emit SetEmergencyMode(_emergencyMode);
    }

    /**
      * @dev emergency withdraw all lp tokens from farming contract given the list of lp token addresses
      * @param lpTokens the list of lp token addresses
      */
    function emergencyWithdraw(address[] memory lpTokens) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < lpTokens.length; ++i) {
            address lpToken = lpTokens[i];
            Pool memory poolInfo = pools[lpToken];
            if (!poolInfo.isActive) {
                continue; // Skip inactive pool
            }
            uint256 lpAmount = IERC20(poolInfo.lpToken).balanceOf(address(this));
            IV2Wrapper(poolInfo.poolAddress).emergencyWithdraw();
            lpAmount = IERC20(poolInfo.lpToken).balanceOf(address(this)) - lpAmount;

            emit EmergencyWithdraw(poolInfo.poolAddress, lpAmount);
        }
        emergencyMode = true;
    }
}
