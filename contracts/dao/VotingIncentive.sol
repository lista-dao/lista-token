// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IVault } from "./interfaces/IVault.sol";
import { IEmissionVoting } from "./interfaces/IEmissionVoting.sol";
import { EmissionVoting } from "./EmissionVoting.sol";

/**
 *  @title Lista Voting Incentive
 *  @notice Voting Incentive module allows users to incentivize veLista holders to vote on the distribution of LP emissions.
 *          Incentivized voters can claim rewards based on their voting weight.
 */
contract VotingIncentive is Initializable, AccessControlUpgradeable, PausableUpgradeable {
  using SafeERC20 for IERC20;

  uint16 startWeek; // start week of voting incentives; set during deployment to reduce gas cost

  // ListaVault contract
  IVault public vault;

  // EmissionVoting contract
  IEmissionVoting public emissionVoting;

  address adminVoter;

  // asset address => true/false
  mapping(address => bool) public assetWhitelist;

  // user -> distributor -> week -> asset -> claimed
  mapping(address => mapping(uint16 => mapping(uint16 => mapping(address => bool)))) public claimedIncentives;

  // distributorId -> week -> asset -> amount
  mapping(uint16 => mapping(uint16 => mapping(address => uint256))) public weeklyIncentives;

  // @dev responsible to halt the contract
  bytes32 public constant PAUSER = keccak256("PAUSER");

  /********************** Events ***********************/
  event AssetChanged(address indexed asset, bool whitelisted);
  event AdminVoterChanged(address indexed _newAdminVoter);
  event IncentiveAdded(uint16 indexed distributorId, uint16 startWeek, uint16 endWeek, address asset, uint256 amount);
  event IncentiveClaimed(
    address indexed user,
    uint16 indexed distributorId,
    uint16 week,
    address asset,
    uint256 amount
  );

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev Initialize the contract
   * @param _vault address of ListaVault contract
   * @param _emissionVoting address of EmissionVoting contract
   * @param _adminVoter address of the admin voter
   * @param _admin address of the admin who can pause the contract
   */
  function initialize(address _vault, address _emissionVoting, address _adminVoter, address _admin) public initializer {
    __AccessControl_init();
    __Pausable_init();

    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

    vault = IVault(_vault);
    emissionVoting = IEmissionVoting(_emissionVoting);
    require(emissionVoting.hasRole(emissionVoting.ADMIN_VOTER(), _adminVoter), "Invalid adminVoter");
    adminVoter = _adminVoter;
    grantRole(DEFAULT_ADMIN_ROLE, _admin);

    startWeek = vault.getWeek(block.timestamp);
  }

  /**
   * @dev Whiltelist an asset for voting incentives; zero address to whitelist native token (BNB)
   * @param _asset address of the asset
   * @param _whitelist true/false; true to whitelist, false to remove from whitelist
   */
  function whitelistAsset(address _asset, bool _whitelist) external onlyRole(DEFAULT_ADMIN_ROLE) {
    assetWhitelist[_asset] = _whitelist;

    emit AssetChanged(_asset, _whitelist);
  }

  /**
   * @dev Add Bnb incentives for a distributor for a range of weeks. msg.value should be divisible by number of weeks
   * @param _distributorId id of the distributor
   * @param _startWeek start week
   * @param _endWeek end week
   */
  function addIncentivesBnb(uint16 _distributorId, uint16 _startWeek, uint16 _endWeek) external payable whenNotPaused {
    require(assetWhitelist[address(0)], "Bnb not whitelisted");
    require(msg.value > 0, "Invalid amount");
    require(_distributorId > 0 && _distributorId <= vault.distributorId(), "Invalid distributorId");
    require(
      _startWeek >= (vault.getWeek(block.timestamp) + 1) && _startWeek <= _endWeek,
      "Only current or future weeks"
    );

    uint256 numberOfWeeks = uint256(_endWeek) - uint256(_startWeek) + 1;
    uint256 weeklyAmount = msg.value / numberOfWeeks;

    // Ensure input amount is divisible by number of weeks
    require(weeklyAmount * numberOfWeeks == msg.value, "Input amount not divisible by number of weeks");

    address _asset = address(0);
    for (uint16 i = _startWeek; i <= _endWeek; ++i) {
      weeklyIncentives[_distributorId][i][_asset] += weeklyAmount;
    }

    emit IncentiveAdded(_distributorId, _startWeek, _endWeek, _asset, msg.value);
  }

  /**
   * @dev Add incentives for a distributor for a range of weeks
   * @param _distributorId id of the distributor
   * @param _startWeek start week
   * @param _endWeek end week
   * @param _asset address of the asset
   * @param _expectAmount expected amount to be added; actual amount may less than this due to rounding
   */
  function addIncentives(
    uint16 _distributorId,
    uint16 _startWeek,
    uint16 _endWeek,
    address _asset,
    uint256 _expectAmount
  ) external whenNotPaused {
    require(assetWhitelist[_asset], "Asset not whitelisted");
    require(_expectAmount > 0, "Invalid amount");
    require(_distributorId > 0 && _distributorId <= vault.distributorId(), "Invalid distributorId");
    require(
      _startWeek >= (vault.getWeek(block.timestamp) + 1) && _startWeek <= _endWeek,
      "Only current or future weeks"
    );

    uint256 numberOfWeeks = uint256(_endWeek) - uint256(_startWeek) + 1;
    uint256 weeklyAmount = _expectAmount / numberOfWeeks;

    uint256 actualAmount = 0;

    for (uint16 i = _startWeek; i <= _endWeek; ++i) {
      weeklyIncentives[_distributorId][i][_asset] += weeklyAmount;
      actualAmount += weeklyAmount;
    }

    // Transfer the actual amount from payer to this contract
    require(actualAmount > 0 && actualAmount <= _expectAmount, "Invalid amount");
    IERC20(_asset).safeTransferFrom(msg.sender, address(this), actualAmount);

    emit IncentiveAdded(_distributorId, _startWeek, _endWeek, _asset, actualAmount);
  }

  /**
   * @dev Claim all incentives for a distributor for a week
   * @param _distributorId id of the distributor
   * @param _week week number
   */
  function batchClaim(uint16 _distributorId, uint16 _week, address[] memory _assets) external whenNotPaused {
    for (uint256 i = 0; i < _assets.length; ++i) {
      claim(_distributorId, _week, _assets[i]);
    }
  }

  // TODO: reentrancy guard
  /**
   * @dev Claim incentives for a distributor for a week
   * @param _distributorId id of the distributor
   * @param _week week number
   * @param _asset address of the asset
   */
  function claim(uint16 _distributorId, uint16 _week, address _asset) public whenNotPaused {
    address _user = msg.sender;
    require(_user != adminVoter, "Invalid voter");
    require(_distributorId > 0 && _distributorId <= vault.distributorId(), "Invalid distributorId");
    require(!claimedIncentives[_user][_distributorId][_week][_asset], "Already claimed");
    uint256 adminWeight = getRawWeight(adminVoter, _distributorId, _week);

    uint256 amountToClaim = calculateAmount(_user, _distributorId, _week, _asset, adminWeight);

    claimedIncentives[_user][_distributorId][_week][_asset] = true;
    if (_asset == address(0)) {
      (bool success, ) = payable(_user).call{ value: amountToClaim }("");
      require(success, "Transfer failed");
    } else {
      IERC20(_asset).safeTransfer(_user, amountToClaim);
    }

    emit IncentiveClaimed(_user, _distributorId, _week, _asset, amountToClaim);
  }

  /**
   * @dev Calculate the claimable amount for a user for a week by removing admin weight
   * @param _user address of the user
   * @param _distributorId id of the distributor
   * @param _week week number
   * @param _asset address of the asset
   * @param _adminWeight weight of the admin voter
   */
  function calculateAmount(
    address _user,
    uint16 _distributorId,
    uint16 _week,
    address _asset,
    uint256 _adminWeight
  ) internal view returns (uint256 _amount) {
    uint256 poolWeight = emissionVoting.getDistributorWeeklyTotalWeight(_distributorId, _week);
    uint256 usrWeight = getRawWeight(_user, _distributorId, _week);

    require(poolWeight > _adminWeight, "Invalid pool weight");

    // If admin has voted, adjust user weight by removing admin weight from pool
    uint256 factor = _adminWeight > 0 ? (1e18 * poolWeight) / (poolWeight - _adminWeight) : 1e18;

    uint256 incentive = weeklyIncentives[_distributorId][_week][_asset];
    _amount = (usrWeight * incentive * factor) / poolWeight / 1e18;
    require(_amount <= incentive, "Invalid amount");
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

  /**
   * @dev update the adminVoter
   * @param _adminVoter address of the new adminVoter
   */
  function setAdminVoter(address _adminVoter) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_adminVoter != address(0) && _adminVoter != adminVoter, "Invalid adminVoter");
    adminVoter = _adminVoter;

    emit AdminVoterChanged(_adminVoter);
  }

  /**
   * @dev get the original weight of an account for a distributor for a week
   * @param _account address of the account
   * @param _distributorId id of the distributor
   * @param _week week number
   */
  function getRawWeight(address _account, uint16 _distributorId, uint16 _week) public view returns (uint256 _weight) {
    uint256 index = emissionVoting.userVotedDistributorIndex(_account, _week, _distributorId);
    EmissionVoting.Vote[] memory votes = emissionVoting.getUserVotedDistributors(_account, _week);
    if (votes.length == 0) {
      return 0; // account has not voted
    }
    require(votes.length > index, "Invalid index");
    EmissionVoting.Vote memory vote = votes[index];

    require(vote.distributorId == _distributorId, "Invalid distributorId");
    _weight = vote.weight;
  }

  /**
   * @dev get the total claimable amount for a user for all weeks for distributors
   * @param _account address of the account
   * @param _assets array of asset addresses
   * @return _amount array of total claimable amount for the input assets;
   */
  function getTotalClaimableAmount(
    address _account,
    address[] memory _assets
  ) external view returns (uint256[] memory _amount) {
    _amount = new uint256[](_assets.length);

    uint16 endWeek = vault.getWeek(block.timestamp); // current week

    uint16 maxDistributorId = vault.distributorId();

    for (uint16 id = 1; id <= maxDistributorId; ++id) {
      for (uint16 week = startWeek; week <= endWeek; ++week) {
        for (uint256 i = 0; i < _assets.length; ++i) {
          if (claimedIncentives[_account][id][week][_assets[i]]) {
            // skip if already claimed
            continue;
          }

          uint256 adminWeight = getRawWeight(adminVoter, id, week);

          uint256 amount = calculateAmount(_account, id, week, _assets[i], adminWeight);
          _amount[i] += amount;
        }
      }
    }
  }

  /**
   * @dev the function to get the incentives for a distributor for a week
   * @param _distributorId id of the distributor
   * @param _week week number
   * @param _assets array of asset addresses
   * @return _incentives array of incentives for the input assets
   */
  function getDistributorIncentives(
    uint16 _distributorId,
    uint16 _week,
    address[] memory _assets
  ) public view returns (uint256[] memory _incentives) {
    require(_distributorId > 0 && _distributorId <= vault.distributorId(), "Invalid distributorId");
    _incentives = new uint256[](_assets.length);

    for (uint256 i = 0; i < _assets.length; ++i) {
      _incentives[i] = weeklyIncentives[_distributorId][_week][_assets[i]];
    }
  }
}
