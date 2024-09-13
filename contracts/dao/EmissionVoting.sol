// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../interfaces/IVeLista.sol";
import "./interfaces/IVault.sol";

/**
 *  @title Lista Emission Voting
 *  @notice Users with LISTA balances locked in `veLista` may register their
 *          veLista weights in this contract, and use this weight to vote on where
 *          new LISTA emissions will be released in the following week.
 */
contract EmissionVoting is Initializable, AccessControlUpgradeable, PausableUpgradeable {

    // @dev define 1 week in seconds
    uint256 constant public WEEK = 604800;

    // @dev user vote struct
    struct Vote {
        uint16 distributorId;
        uint256 weight;
    }

    // @dev veLista contract address
    IVeLista public veLista;
    // @dev ListaVault contract address
    IVault public vault;

    // @dev weekly total weight
    //      week -> total voted veLista weight
    mapping(uint16 => uint256) public weeklyTotalWeight;
    // @dev distributorId -> week -> total voted veLista weight
    mapping(uint16 => mapping(uint16 => uint256)) public distributorWeeklyTotalWeight;
    // @dev user -> week -> weight
    mapping(address => mapping(uint16 => uint256)) public userWeeklyVotedWeight;

    // @dev user -> week -> Vote[]
    mapping(address => mapping(uint16 => Vote[])) public userVotedDistributors;
    // @dev user -> week -> distributorId -> index
    mapping(address => mapping(uint16 => mapping(uint16 => uint256))) public userVotedDistributorIndex;

    // @dev disabled distributors
    mapping(uint16 => bool) public disabledDistributors;

    // @dev the role can vote within ADMIN_VOTE_PERIOD
    bytes32 public constant ADMIN_VOTER = keccak256("ADMIN_VOTER");
    // @dev responsible to halt the contract
    bytes32 public constant PAUSER = keccak256("PAUSER");
    // @dev only user has the ADMIN_VOTER role can vote within ADMIN_VOTE_PERIOD
    uint256 public ADMIN_VOTE_PERIOD;

    // @dev events
    event UserVoted(address indexed user, uint16[] distributorIds, uint256[] weights);
    event DistributorToggled(uint16 distributorId, bool disabled);
    event AdminVotePeriodChanged(uint256 newAdminVotePeriod);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev Initialize contract
      * @param _admin admin address
      * @param _adminVoter adminVoter address
      * @param _veLista veLista token address
      * @param _vault lista vault address
      * @param _adminVotePeriod admin vote period
      */
    function initialize(
        address _admin,
        address _adminVoter,
        address _veLista,
        address _vault,
        uint256 _adminVotePeriod
    ) public initializer {
        require(_admin != address(0), "admin is a zero address");
        require(_adminVoter != address(0), "adminVoter is a zero address");
        require(_veLista != address(0), "veLista is a zero address");
        require(_vault != address(0), "vault is a zero address");

        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(ADMIN_VOTER, _adminVoter);
        veLista = IVeLista(_veLista);
        vault = IVault(_vault);
        ADMIN_VOTE_PERIOD = _adminVotePeriod;
    }


    // ------------------------------------- //
    //                Voting                 //
    // ------------------------------------- //

    /**
     * @dev Admin vote for the next week
     * @param distributorIds distributor ids
     * @param weights weights
     */
    function adminVote(uint16[] calldata distributorIds, uint256[] calldata weights) public whenNotPaused onlyRole(ADMIN_VOTER) {
        require(
            block.timestamp >= veLista.startTime() + (veLista.getCurrentWeek() + 1) * WEEK - ADMIN_VOTE_PERIOD,
            "non admin voting period"
        );
        _vote(distributorIds, weights, false);
    }

    /**
     * @dev User vote for the next week
     * @param distributorIds distributor ids
     * @param weights weights
     */
    function vote(uint16[] calldata distributorIds, uint256[] calldata weights) public whenNotPaused {
        require(
            block.timestamp < veLista.startTime() + (veLista.getCurrentWeek() + 1) * WEEK - ADMIN_VOTE_PERIOD,
            "only admin voter can vote now"
        );
        _vote(distributorIds, weights, true);
    }


    // ------------------------------------- //
    //            View Functions             //
    // ------------------------------------- //

    /**
     * @dev Get total weight of the week
     * @param week week number
     */
    function getWeeklyTotalWeight(uint16 week) external view returns (uint256) {
        return weeklyTotalWeight[week];
    }

    /**
     * @dev Get distributor total weight of the week
     * @param distributorId distributor id
     * @param week week number
     */
    function getDistributorWeeklyTotalWeight(uint16 distributorId, uint16 week) external view returns (uint256) {
        return distributorWeeklyTotalWeight[distributorId][week];
    }

    // ------------------------------------- //
    //            Admin Functions            //
    // ------------------------------------- //

    /**
     * @dev Set admin vote period,
            when (block.timestamp < right before next week - adminVotePeriod), only admin voter can vote
     * @param _adminVotePeriod admin vote period (in seconds)
     */
    function setAdminVotePeriod(uint256 _adminVotePeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_adminVotePeriod >= 0 && _adminVotePeriod <= WEEK, "admin vote period should within 0 to 1 week");
        ADMIN_VOTE_PERIOD = _adminVotePeriod;
        emit AdminVotePeriodChanged(_adminVotePeriod);
    }

    /**
     * @dev Toggle distributor (when distributor is disabled, user/admin cannot vote for it)
     * @param distributorId distributor id
     */
    function toggleDistributor(uint16 distributorId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        disabledDistributors[distributorId] = !disabledDistributors[distributorId];
        emit DistributorToggled(distributorId, disabledDistributors[distributorId]);
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


    // ------------------------------------- //
    //          Internal Functions           //
    // ------------------------------------- //
    /**
     * @dev Vote for the next week
     * @param distributorIds distributor ids
     * @param weights weights
     * @param needBalanceCheck need to check veLista balance
     */
    function _vote(uint16[] calldata distributorIds, uint256[] calldata weights, bool needBalanceCheck) internal {

        require(distributorIds.length == weights.length, "distributorIds and weights length mismatch");
        require(distributorIds.length > 0, "distributorIds and weights should not be empty");

        // get current veLista balance of user
        uint256 userLatestWeight = veLista.balanceOf(msg.sender);
        // only user needs to check balance
        if (needBalanceCheck) {
            require(userLatestWeight > 0, "veLista balance must be greater than 0");
        }
        // the next week user voting for
        uint16 votingWeek = veLista.getCurrentWeek() + 1;
        // get user all votes of this week
        Vote[] storage userVotes = userVotedDistributors[msg.sender][votingWeek];
        // save user old weight of this week
        uint256 oldUserVotedWeight = userWeeklyVotedWeight[msg.sender][votingWeek];
        uint256 newUserVotedWeight = oldUserVotedWeight;

        // process each vote
        for (uint256 i = 0 ; i < distributorIds.length; ++i) {
            uint16 distributorId = distributorIds[i];
            uint256 weight = weights[i];
            require(!disabledDistributors[distributorId], "distributor is disabled");
            require(weight >= 0, "weight should be equals to or greater than 0");
            require(distributorId > 0 && distributorId <= vault.distributorId(), "distributor does not exists");

            int256 idx = int256(userVotedDistributorIndex[msg.sender][votingWeek][distributorId]) - 1;
            bool voted = idx >= 0;

            // first time vote and weight is not 0
            if (!voted) {
                userVotes.push(Vote(distributorId, weight));
                userVotedDistributorIndex[msg.sender][votingWeek][distributorId] = userVotes.length;
                newUserVotedWeight += weight;
                distributorWeeklyTotalWeight[distributorId][votingWeek] += weight;
            } else {
                // updates user's vote record of this distributor
                distributorWeeklyTotalWeight[distributorId][votingWeek] =
                    distributorWeeklyTotalWeight[distributorId][votingWeek] - userVotes[uint256(idx)].weight + weight;
                newUserVotedWeight = newUserVotedWeight - userVotes[uint256(idx)].weight + weight;
                userVotes[uint256(idx)].weight = weight;
            }
        }
        // update user's consumed weight of this week
        userWeeklyVotedWeight[msg.sender][votingWeek] =
            userWeeklyVotedWeight[msg.sender][votingWeek] - oldUserVotedWeight + newUserVotedWeight;
        // all user's weight of this week
        weeklyTotalWeight[votingWeek] =
            weeklyTotalWeight[votingWeek] - oldUserVotedWeight + newUserVotedWeight;

        // check balance is enough to vote
        if (needBalanceCheck) {
            require(userLatestWeight >= userWeeklyVotedWeight[msg.sender][votingWeek], "veLista balance is not enough to vote");
        }

        emit UserVoted(msg.sender, distributorIds, weights);
    }
}
