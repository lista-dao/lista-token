// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IVeListaDistributor.sol";
import "./interfaces/IVeLista.sol";

/**
  * @title VeListaRewardsCourierV2
  * @dev VeListaRewardsCourier act as a courier of delivery of rewards to the veListaDistributor
  *      veLista rewards will be deposit to the VeListaRewardsCourier weekly(usually at the beginning of the week),
  *      and a off-chain component with the BOT role will be responsible for triggers the VeListaRewardsCourier
  *      to deliver the rewards to the veListaDistributor on-time.
  */
contract VeListaRewardsCourierV2 is Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;
    // 1 week and 1 day in seconds
    uint256 public constant WEEK = 1 weeks;
    uint256 public constant DAY = 1 days;

    // @dev rewards token: LISTA
    IERC20 public token;
    // @dev record if rewards has been delivered for the week
    mapping(uint16 => bool) public rewardsDeliveredForWeek;
    // @dev records the amount of rewards for each week
    mapping(uint16 => uint256)  public weeklyRewardAmounts;

    // veLista ecosystem contracts
    IVeLista public veLista;
    IVeListaDistributor public veListaDistributor;

    // --- events
    event RewardsRecharged(uint16 week, uint256 amount); // rewards has been pre-deposited to VeListaRewardsCourier
    event RewardsDelivered(uint16 week, uint256 amount); // rewards has been delivered to veListaDistributor
    event RewardsAdjusted(uint16 week, int256 amount); // reward has been adjust by the admin after reconciliation

    // --- roles
    bytes32 public constant BOT = keccak256("BOT"); // triggering the delivery
    bytes32 public constant DISTRIBUTOR = keccak256("DISTRIBUTOR"); // recharging rewards to VeListaRewardsCourier

    /**
      * @dev initialize the contract
    * @param _rewardsToken address of the rewards token
    * @param _admin address of the ADMIN role
    * @param _bot address of the BOT role
    * @param _distributor address of the DISTRIBUTOR role
    * @param _veLista address of the veLista contract
    * @param _veListaDistributor address of the veListaDistributor contract
    */
    function initialize(
        address _rewardsToken,
        address _admin,
        address _bot,
        address _distributor,
        address _veLista,
        address _veListaDistributor
    ) external initializer {
        __AccessControl_init();
        require(_rewardsToken != address(0), "rewardsToken is a zero address");
        require(_admin != address(0), "admin is a zero address");
        require(_bot != address(0), "bot is a zero address");
        require(_veLista != address(0), "veLista is a zero address");
        require(_veListaDistributor != address(0), "veListaDistributor is a zero address");
        token = IERC20(_rewardsToken);
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(BOT, _bot);
        _setupRole(DISTRIBUTOR, _distributor);
        veLista = IVeLista(_veLista);
        veListaDistributor = IVeListaDistributor(_veListaDistributor);
    }

    /**
      * @dev recharge rewards to VeListaRewardsCourier
    *      only address with DISTRIBUTOR role can call this function
    * @param amount amount of rewards to be recharged
    */
    function rechargeRewards(uint256 amount) external onlyRole(DISTRIBUTOR) {

        require(amount > 0, "Amount must be greater than 0");
        // @dev Note that a week starts from Wed as defined the VeLista contract
        //      but rewards will be counted from Mon to Sun
        //      So, rewards for week N+1 will be distributed as follows:
        //      Part 1: week N-1's Mon 00:00 to Tue 23:59
        //      Part 2: week N's Wed 00:00 to Sun 23:59
        //      Finally, week N's rewards will be delivered and distributed at week N+1
        uint16 rewardWeek = veLista.getCurrentWeek();
        uint256 rewardWeekTimestamp = veLista.startTime() + uint256(rewardWeek) * WEEK;
        uint256 now = block.timestamp;

        // actual rewards belongs to rewardWeek - 1
        if (now > rewardWeekTimestamp + 5 * DAY) {
            rewardWeek += 1;
        }
        require(!rewardsDeliveredForWeek[rewardWeek], "Rewards already delivered for the week");
        // add reward amount
        weeklyRewardAmounts[rewardWeek] += amount;
        // transfer token to contract
        token.safeTransferFrom(msg.sender, address(this), amount);
        // broadcast recharge event
        emit RewardsRecharged(rewardWeek, amount);
    }

    /**
      * @dev deliver rewards to veListaDistributor
    */
    function deliverRewards() external onlyRole(BOT) {
        // referring to rechargeRewards(), at this moment week is rewardWeek + 1
        // should be called at 00:00
        uint16 week = veLista.getCurrentWeek() - 1;
        // check if its delivered
        require(!rewardsDeliveredForWeek[week], "Rewards already delivered for the week");
        rewardsDeliveredForWeek[week] = true;
        // has non zero amount to deliver
        if (weeklyRewardAmounts[week] > 0) {
            // use token array as per veListaDistributor interface
            IVeListaDistributor.TokenAmount[] memory tokens = new IVeListaDistributor.TokenAmount[](1);
            tokens[0] = IVeListaDistributor.TokenAmount(address(token), weeklyRewardAmounts[week]);
            // approve token
            token.approve(address(veListaDistributor), weeklyRewardAmounts[week]);
            // send to veListaDistributor
            veListaDistributor.depositNewReward(week, tokens);
            // broadcast delivery event
            emit RewardsDelivered(week, weeklyRewardAmounts[week]);
        }
    }


    /**
      * @dev adjust the latest rewards
    * @param amount amount to adjust
    */
    function adjustRewards(uint16 week, int256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount != 0, "Amount must be non-zero");
        require(!rewardsDeliveredForWeek[week], "Rewards already delivered for the week");
        // adjust amount and transfer token
        if (amount > 0) {
            token.safeTransferFrom(msg.sender, address(this), uint256(amount));
            weeklyRewardAmounts[week] += uint256(amount);
        } else {
            token.safeTransfer(msg.sender, uint256(-amount));
            weeklyRewardAmounts[week] -= uint256(-amount);
        }
        emit RewardsAdjusted(week, amount);
    }

}
