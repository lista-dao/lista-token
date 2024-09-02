// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../interfaces/IVeLista.sol";
import "./interfaces/IVault.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


/**
 *  @title Lista Incentive Voting
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
    mapping(uint256 => uint256) public weeklyTotalWeight;
    // @dev distributorId -> week -> total voted veLista weight
    mapping(uint16 => mapping(uint256 => uint256)) public distributorWeeklyTotalWeight;
    // @dev user -> week -> weight
    mapping(address => mapping(uint256 => uint256)) public userWeeklyVotedWeight;
    // @dev user -> week -> Vote[]
    mapping(address => mapping(uint256 => Vote[])) public userVotedDistributors;
    // @dev disabled distributors
    mapping(uint16 => bool) public disabledDistributors;

    // @dev the role can vote within ADMIN_VOTE_PERIOD
    bytes32 public constant ADMIN_VOTER = keccak256("MANAGER");
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
    function adminVote(uint16[] calldata distributorIds, uint256[] calldata weights) public whenNotPaused onlyRole(ADMIN_VOTER) {
        _vote(distributorIds, weights);
    }

    function vote(uint16[] calldata distributorIds, uint256[] calldata weights) public whenNotPaused {
        require(block.timestamp < (veLista.getCurrentWeek() + 1) * WEEK - ADMIN_VOTE_PERIOD, "only admin voter can vote now");
        _vote(distributorIds, weights);
    }


    // ------------------------------------- //
    //            View Functions             //
    // ------------------------------------- //
    function getDistributorWeight(uint16 distributorId) external view returns (uint256 weight) {
        // get latest week
        uint256 _week = veLista.getCurrentWeek();
        // get distributor weight
        weight = distributorWeeklyTotalWeight[distributorId][_week];
    }


    // ------------------------------------- //
    //            Admin Functions            //
    // ------------------------------------- //
    function setAdminVotePeriod(uint256 _adminVotePeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_adminVotePeriod > 0 && _adminVotePeriod < WEEK, "admin vote period should be greater than 0 and less than 1 week");
        ADMIN_VOTE_PERIOD = _adminVotePeriod;
        emit AdminVotePeriodChanged(_adminVotePeriod);
    }

    function toggleDistributor(uint16 distributorId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        disabledDistributors[distributorId] = !disabledDistributors[distributorId];
        emit DistributorToggled(distributorId, disabledDistributors[distributorId]);
    }

    // @dev Flips the pause state
    function togglePause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused() ? _unpause() : _pause();
    }

    // @dev pause the contract
    function pause() external onlyRole(PAUSER) {
        _pause();
    }

    // ------------------------------------- //
    //          Internal Functions           //
    // ------------------------------------- //
    function _vote(uint16[] calldata distributorIds, uint256[] calldata weights) internal {

        require(distributorIds.length == weights.length, "distributorIds and weights length mismatch");
        require(distributorIds.length > 0, "distributorIds and weights should not be empty");

        // get current veLista balance of user
        uint256 userLatestWeight = veLista.balanceOf(msg.sender);
        require(userLatestWeight > 0, "veLista balance must be greater than 0");
        // the next week user voting for
        uint256 votingWeek = veLista.getCurrentWeek() + 1;
        // get user current votes
        Vote[] storage userVotes = userVotedDistributors[msg.sender][votingWeek];

        uint256 weightDelta = 0;
        // process each vote
        for (uint256 i = 0 ; i < distributorIds.length; ++i) {
            uint16 distributorId = distributorIds[i];
            uint256 weight = weights[i];
            require(!disabledDistributors[distributorId], "distributor is disabled");
            require(weight >= 0, "weight should be equals to or greater than 0");
            require(distributorId <= vault.distributorId(), "distributor not exists");

            uint256 subWeightDelta = 0;
            // check if user already voted for this distributor
            for (uint256 j = 0; j < userVotes.length; ++j) {
                if (userVotes[j].distributorId == distributorId) {
                    // calculate weight delta
                    subWeightDelta = weight - userVotes[j].weight;
                    // updates user's vote record of this distributor
                    userVotes[j].weight = weight;
                }
            }
            // if user has not voted for this distributor
            if (subWeightDelta == 0) {
                // add new vote record
                userVotes.push(Vote(distributorId, weight));
                subWeightDelta = weight;
            }
            weightDelta += subWeightDelta;
            // update distributor weekly weight
            distributorWeeklyTotalWeight[distributorId][votingWeek] += subWeightDelta;
        }
        // update user weight usage
        userWeeklyVotedWeight[msg.sender][votingWeek] += weightDelta;
        // update total weight
        weeklyTotalWeight[votingWeek] += weightDelta;
        require(userLatestWeight >= userWeeklyVotedWeight[msg.sender][votingWeek], "veLista balance is not enough to vote");

        emit UserVoted(msg.sender, distributorIds, weights);
    }
}
