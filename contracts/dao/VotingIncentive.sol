// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { IVault } from "./interfaces/IVault.sol";
import { IEmissionVoting } from "./interfaces/IEmissionVoting.sol";
import { EmissionVoting } from "./EmissionVoting.sol";

/**
 *  @title Lista Voting Incentive
 *  @notice Voting Incentive module allows users to incentivize veLista holders to vote on the distribution of LP emissions.
 *          Incentivized voters can claim rewards based on their voting weight.
 */
contract VotingIncentive is AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
  using SafeERC20 for IERC20;

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

  /********************** Roles ***********************/
  bytes32 public constant MANAGER = keccak256("MANAGER");

  // @dev responsible to halt the contract
  bytes32 public constant PAUSER = keccak256("PAUSER");

  /********************** Structs ***********************/
  struct ClaimParams {
    uint16 distributorId;
    uint16 week;
    address[] assets;
  }

  struct Incentive {
    address asset;
    uint256 amount;
  }

  struct ClaimableAmount {
    uint16 distributorId;
    uint16 week;
    Incentive[] incentives;
  }

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
  event EmergencyWithdrawal(address indexed asset, address indexed to, uint256 amount);

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
   * @param _manager address of the manager
   * @param _pauser address of the pauser who can pause the contract
   */
  function initialize(
    address _vault,
    address _emissionVoting,
    address _adminVoter,
    address _admin,
    address _manager,
    address _pauser
  ) public initializer {
    require(
      _vault != address(0) &&
        _emissionVoting != address(0) &&
        _adminVoter != address(0) &&
        _admin != address(0) &&
        _manager != address(0) &&
        _pauser != address(0),
      "Zero address provided"
    );
    __AccessControl_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();

    vault = IVault(_vault);
    emissionVoting = IEmissionVoting(_emissionVoting);
    require(emissionVoting.hasRole(emissionVoting.ADMIN_VOTER(), _adminVoter), "Invalid adminVoter");
    adminVoter = _adminVoter;

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(MANAGER, _manager);
    _setupRole(PAUSER, _pauser);
  }

  /**
   * @dev Add Bnb incentives for a distributor for a range of weeks.
   * @param _distributorId id of the distributor
   * @param _startWeek start week
   * @param _endWeek end week
   */
  function addIncentivesBnb(uint16 _distributorId, uint16 _startWeek, uint16 _endWeek) external payable whenNotPaused {
    require(assetWhitelist[address(0)], "Bnb not whitelisted");
    require(msg.value > 0, "Invalid amount");
    require(!emissionVoting.disabledDistributors(_distributorId), "Distributor is disabled");
    require(_distributorId > 0 && _distributorId <= vault.distributorId(), "Invalid distributorId");
    require(_startWeek >= (vault.getWeek(block.timestamp) + 1) && _startWeek <= _endWeek, "Only future weeks");

    uint256 numberOfWeeks = uint256(_endWeek) - uint256(_startWeek) + 1;
    uint256 weeklyAmount = msg.value / numberOfWeeks;

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
  ) external nonReentrant whenNotPaused {
    require(assetWhitelist[_asset], "Asset not whitelisted");
    require(_expectAmount > 0, "Invalid amount");
    require(!emissionVoting.disabledDistributors(_distributorId), "Distributor is disabled");
    require(_distributorId > 0 && _distributorId <= vault.distributorId(), "Invalid distributorId");
    require(_startWeek >= (vault.getWeek(block.timestamp) + 1) && _startWeek <= _endWeek, "Only future weeks");

    uint256 numberOfWeeks = uint256(_endWeek) - uint256(_startWeek) + 1;

    // FOT tokens
    uint256 actualAmount = IERC20(_asset).balanceOf(address(this));
    IERC20(_asset).safeTransferFrom(msg.sender, address(this), _expectAmount);
    actualAmount = IERC20(_asset).balanceOf(address(this)) - actualAmount;

    uint256 weeklyAmount = actualAmount / numberOfWeeks;
    require(weeklyAmount > 0 && actualAmount <= _expectAmount, "Invalid amount");

    for (uint16 i = _startWeek; i <= _endWeek; ++i) {
      weeklyIncentives[_distributorId][i][_asset] += weeklyAmount;
    }

    emit IncentiveAdded(_distributorId, _startWeek, _endWeek, _asset, actualAmount);
  }

  /**
   * @dev Claim all incentives for a distributor for a week
   * @param _input array of ClaimParams to claim
   */
  function batchClaim(ClaimParams[] memory _input) external {
    address user = msg.sender;
    for (uint256 i = 0; i < _input.length; ++i) {
      ClaimParams memory _params = _input[i];
      address[] memory _assets = _params.assets;
      for (uint256 j = 0; j < _assets.length; ++j) {
        if (claimedIncentives[user][_params.distributorId][_params.week][_assets[j]]) continue;
        claim(user, _params.distributorId, _params.week, _assets[j]);
      }
    }
  }

  /**
   * @dev Claim incentives for a distributor for a week
   * @param _user address of the user
   * @param _distributorId id of the distributor
   * @param _week week number
   * @param _asset address of the asset
   */
  function claim(address _user, uint16 _distributorId, uint16 _week, address _asset) public nonReentrant whenNotPaused {
    require(_user != adminVoter, "Invalid voter");
    require(_week <= vault.getWeek(block.timestamp), "Invalid week");
    require(_distributorId > 0 && _distributorId <= vault.distributorId(), "Invalid distributorId");
    require(!claimedIncentives[_user][_distributorId][_week][_asset], "Already claimed");
    require(weeklyIncentives[_distributorId][_week][_asset] > 0, "No incentives");

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

    // If no one has voted, return 0
    if (poolWeight == _adminWeight) return 0;

    uint256 usrWeight = getRawWeight(_user, _distributorId, _week);

    uint256 incentive = weeklyIncentives[_distributorId][_week][_asset];
    // If admin has voted, adjust user weight by removing admin weight from pool
    _amount = (usrWeight * incentive) / (poolWeight - _adminWeight);
  }

  // ------------------------------------- //
  //            Admin Functions            //
  // ------------------------------------- //

  /**
   * @dev Whiltelist an asset for voting incentives; zero address to whitelist native token (BNB)
   * @param _asset address of the asset
   * @param _whitelist true/false; true to whitelist, false to remove from whitelist
   */
  function whitelistAsset(address _asset, bool _whitelist) external onlyRole(MANAGER) {
    assetWhitelist[_asset] = _whitelist;

    emit AssetChanged(_asset, _whitelist);
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /**
   * @dev unpause the contract
   */
  function unpause() external onlyRole(MANAGER) {
    _unpause();
  }

  /**
   * @dev update the adminVoter
   * @param _adminVoter address of the new adminVoter
   */
  function setAdminVoter(address _adminVoter) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_adminVoter != address(0) && _adminVoter != adminVoter, "Invalid adminVoter");
    require(emissionVoting.hasRole(emissionVoting.ADMIN_VOTER(), _adminVoter), "_adminVoter is not granted role");
    adminVoter = _adminVoter;

    emit AdminVoterChanged(_adminVoter);
  }

  /**
   * @dev the function to withdraw funds in case of emergency
   * @param _asset address of the asset
   * @param _to address of the recipient
   * @param _amount amount to withdraw
   */
  function emergencyWithdraw(address _asset, address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_asset == address(0)) {
      (bool success, ) = payable(_to).call{ value: _amount }("");
      require(success, "Transfer failed");
    } else {
      IERC20(_asset).safeTransfer(_to, _amount);
    }

    emit EmergencyWithdrawal(_asset, _to, _amount);
  }

  // ------------------------------------- //
  //            Override Function          //
  // ------------------------------------- //

  function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  // ------------------------------------- //
  //            View Functions             //
  // ------------------------------------- //

  /**
   * @dev get the original weight of an account for a distributor for a week
   * @param _account address of the account
   * @param _distributorId id of the distributor
   * @param _week week number
   */
  function getRawWeight(address _account, uint16 _distributorId, uint16 _week) public view returns (uint256 _weight) {
    int256 index = int256(emissionVoting.userVotedDistributorIndex(_account, _week, _distributorId)) - 1;
    if (index < 0) {
      return 0; // account has not voted
    }
    EmissionVoting.Vote[] memory votes = emissionVoting.getUserVotedDistributors(_account, _week);
    EmissionVoting.Vote memory vote = votes[uint256(index)];

    require(vote.distributorId == _distributorId, "Invalid distributorId");
    _weight = vote.weight;
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

  /**
   * @dev the function to get the claimable amount for a user for given params
   * @param _user address of the user
   * @param _input array of ClaimParams
   * @return claimableAmt array of ClaimableAmount
   */
  function getClaimableAmount(
    address _user,
    ClaimParams[] memory _input
  ) public view returns (ClaimableAmount[] memory claimableAmt) {
    claimableAmt = new ClaimableAmount[](_input.length);
    for (uint256 i = 0; i < _input.length; ++i) {
      ClaimParams memory _params = _input[i];
      address[] memory _assets = _params.assets;
      Incentive[] memory _incentives = new Incentive[](_assets.length);

      for (uint256 j = 0; j < _assets.length; ++j) {
        uint256 amount = calculateAmount(
          _user,
          _params.distributorId,
          _params.week,
          _assets[j],
          getRawWeight(adminVoter, _params.distributorId, _params.week)
        );
        _incentives[j] = Incentive({ asset: _assets[j], amount: amount });
      }
      claimableAmt[i] = ClaimableAmount({
        distributorId: _params.distributorId,
        week: _params.week,
        incentives: _incentives
      });
    }
  }
}
