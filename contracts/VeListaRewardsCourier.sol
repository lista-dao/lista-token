// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IVeListaDistributor.sol";

/**
  * @title VeListaRewardsCourier
  * @dev VeListaRewardsCourier act as a courier of delivery of rewards to the veListaDistributor
  *      veLista rewards will be deposit to the VeListaRewardsCourier weekly(usually at the beginning of the week),
  *      and a off-chain component with the BOT role will be responsible for triggers the VeListaRewardsCourier
  *      to deliver the rewards to the veListaDistributor on-time.
  */
contract VeListaRewardsCourier is Initializable, AccessControlUpgradeable {
  using SafeERC20 for IERC20;

  // @dev records rewarding week and token info.
  // @dev week and tokens will be the parameter when calling `depositNewReward`
  uint16 public week;
  IVeListaDistributor.TokenAmount[] public tokens;
  IVeListaDistributor public veListaDistributor;
  bool public rewardsDeliveredForWeek;

  // --- events
  event RewardsRecharged(uint16, IVeListaDistributor.TokenAmount[]); // rewards has been pre-deposited to VeListaRewardsCourier
  event RewardsDelivered(uint16, IVeListaDistributor.TokenAmount[]); // rewards has been delivered to veListaDistributor
  event RewardsRevoked(IVeListaDistributor.TokenAmount[]); // reward has been revoked by the admin

  // --- roles
  bytes32 public constant BOT = keccak256("BOT");

  /**
    * @dev initialize the contract
    * @param _admin address of the ADMIN role
    * @param _bot address of the BOT role
    * @param _veListaDistributor address of the veListaDistributor contract
    */
  function initialize(address _admin, address _bot, address _veListaDistributor) external initializer {
    __AccessControl_init();
    require(_admin != address(0), "admin is a zero address");
    require(_bot != address(0), "bot is a zero address");
    require(_veListaDistributor != address(0), "veListaDistributor is a zero address");
    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(BOT, _bot);
    veListaDistributor = IVeListaDistributor(_veListaDistributor);
    rewardsDeliveredForWeek = true;
  }

  /**
    * @dev recharge rewards to VeListaRewardsCourier
    * @param _week rewards week
    * @param _tokens rewards token info
    */
  function rechargeRewards(uint16 _week, IVeListaDistributor.TokenAmount[] memory _tokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(rewardsDeliveredForWeek, "Pending rewards delivery for the week");
    require(_tokens.length > 0, "No rewards to recharge");
    // mark rewards as not delivered
    rewardsDeliveredForWeek = false;
    week = _week;
    tokens = _tokens;
    // moves token from sender to this contract
    for (uint8 i = 0; i < _tokens.length; ++i) {
      // validate if token is registered and non-zero amount
      require(veListaDistributor.rewardTokenIndexes(_tokens[i].token) > 0, "Token is not registered");
      require(_tokens[i].amount > 0, "Invalid token amount");
      IERC20(_tokens[i].token).safeTransferFrom(msg.sender, address(this), _tokens[i].amount);
    }
    emit RewardsRecharged(_week, _tokens);
  }

  /**
    * @dev deliver rewards to veListaDistributor
    */
  function deliverRewards() external onlyRole(BOT) {
    require(!rewardsDeliveredForWeek, "Rewards already delivered for the week");
    rewardsDeliveredForWeek = true;
    // approve veListaDistributor to move the token
    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20(tokens[i].token).approve(address(veListaDistributor), tokens[i].amount);
    }
    // send to veListaDistributor
    veListaDistributor.depositNewReward(week, tokens);
    emit RewardsDelivered(week, tokens);
  }

  /**
    * @dev revoke rewards in-case any need before rewards delivered to veListaDistributor
    *      extract rewards and send it back to the original sender
    */
  function revokeRewards() external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(!rewardsDeliveredForWeek, "Rewards already delivered for the week");
    rewardsDeliveredForWeek = true;
    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20(tokens[i].token).safeTransfer(msg.sender, tokens[i].amount);
    }
    emit RewardsRevoked(tokens);
  }

}
