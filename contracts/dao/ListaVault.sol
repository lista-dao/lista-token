// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IDistributor.sol";
import "../interfaces/IVeLista.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IEmissionVoting.sol";

/**
  * @title ListaVault
  * @dev lista token vault, distribute rewards to distributors
 */
contract ListaVault is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    event IncreasedAllocation(address indexed distributor, uint256 increasedAmount);

    using SafeERC20 for IERC20;

    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event NewDistributorRegistered(address distributor, uint256 id);
    event EmergencyWithdraw(address token, uint256 amount);
    event EmissionVotingSet(address emissionVoting);
    event Paused(address account);
    event Unpaused(address account);

    // lista token address
    IERC20 public token;
    // allocated balance for each distributor
    // distributor -> allocated balance
    mapping(address => uint256) public allocated;
    // distributor id to address
    // id -> distributor
    mapping(uint16 => address) public idToDistributor;
    // distributor updated week
    // distributorId -> week
    uint16[65535] public distributorUpdatedWeek;
    // weekly emissions
    // week -> emissions
    uint256[65535] public weeklyEmissions;
    // weekly distributor percent
    // week -> distributorId -> percent
    uint256[65535][65535] public weeklyDistributorPercent;
    // veLista address
    IVeLista public veLista;
    // max distributor id
    uint16 public distributorId;
    // emission voting address
    IEmissionVoting public emissionVoting;
    // lp proxy address
    address public lpProxy;

    // manager role
    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant PAUSER = keccak256("PAUSER");

    // paused flag
    bool public paused;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev Initialize contract
      * @param _admin admin address
      * @param _manager manager address
      * @param _token lista token address
      * @param _veLista veLista token address
      */
    function initialize(
        address _admin,
        address _manager,
        address _token,
        address _veLista
    ) public initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_token != address(0), "token is the zero address");
        require(_veLista != address(0), "veLista is the zero address");

        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        token = IERC20(_token);
        veLista = IVeLista(_veLista);
    }

    modifier onlyLpProxy() {
        require(msg.sender == lpProxy, "Only lp proxy can call this function");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Pausable: not paused");
        _;
    }

    /**
     * @dev deposit lista token as rewards
     * @param amount amount of token
     * @param week week number
     */
    function depositRewards(uint256 amount, uint16 week) onlyRole(MANAGER) external {
        require(amount > 0, "Amount must be greater than 0");
        require(week > veLista.getCurrentWeek(), "week must be greater than current week");

        weeklyEmissions[week] += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);
    }

    /**
     * @dev set weekly distributor percent
     * @param week week number
     * @param ids distributor ids
     * @param percent distributor percent
     */
    function setWeeklyDistributorPercent(uint16 week, uint16[] memory ids, uint256[] memory percent) onlyRole(MANAGER) external {
        require(week > veLista.getCurrentWeek(), "week must be greater than current week");
        require(ids.length > 0 && ids.length == percent.length, "ids and percent length mismatch");
        uint256 totalPercent;

        if (weeklyDistributorPercent[week][0] == 1) {
            // this week has set, reset last distributor percent
            for (uint16 i = 1; i <= distributorId; ++i) {
                weeklyDistributorPercent[week][i] = 0;
            }
        }
        for (uint16 i = 0; i < ids.length; ++i) {
            require(idToDistributor[ids[i]] != address(0), "distributor not registered");
            require(weeklyDistributorPercent[week][ids[i]] == 0, "distributor percent already set");
            weeklyDistributorPercent[week][ids[i]] = percent[i];
            totalPercent += percent[i];
        }

        // mark this week set flag
        weeklyDistributorPercent[week][0] = 1;
        require(totalPercent <= 1e18, "Total percent must be less than or equal to 1e18");
    }

    /**
     * @dev register distributor which can claim rewards
     * @param distributor distributor address
     * @return distributor id
     */
    function registerDistributor(address distributor) external onlyRole(MANAGER) returns (uint16) {
        uint16 week = veLista.getCurrentWeek();
        ++distributorId;
        distributorUpdatedWeek[distributorId] = week;
        idToDistributor[distributorId] = distributor;
        require(IDistributor(distributor).notifyRegisteredId(distributorId), "distributor registration failed");
        emit NewDistributorRegistered(distributor, distributorId);
        return distributorId;
    }

    /**
     * @dev set emission voting contract address
     * @param _emissionVoting emission voting contract address
     */
    function setEmissionVoting(address _emissionVoting) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_emissionVoting != address(0) && _emissionVoting != address(emissionVoting), "emission voting is invalid");
        emissionVoting = IEmissionVoting(_emissionVoting);
        emit EmissionVotingSet(_emissionVoting);
    }

    /**
     * @dev batch claim rewards
     * @param _distributors distributor contracts
     */
    function batchClaimRewards(address[] memory _distributors) whenNotPaused external {
        _batchClaimRewards(msg.sender, _distributors);
    }

    function _batchClaimRewards(address account, address[] memory _distributors) private {
        uint256 total;
        for (uint16 i = 0; i < _distributors.length; ++i) {
            uint256 amount = IDistributor(_distributors[i]).vaultClaimReward(account);
            require(allocated[_distributors[i]] >= amount, "Insufficient allocated balance");
            allocated[_distributors[i]] -= amount;
            total += amount;
        }
        if (total > 0) {
            token.safeTransfer(account, total);
        }
    }

    /**
     * @dev get claimable list
     * @param account account address
     * @param distributors array of distributor address
     * @return claimable list
     */
    function claimableList(address account, address[] memory distributors) external view returns (uint256[] memory) {
        uint256[] memory claimable = new uint256[](distributors.length);
        for (uint16 i = 0; i < distributors.length; ++i) {
            claimable[i] = IDistributor(distributors[i]).claimableReward(account);
        }
        return claimable;
    }

    /**
     * @dev transfer allocated tokens to account
     * @param _distributorId distributor id
     * @param account account address
     * @param amount amount of token
     */
    function transferAllocatedTokens(uint16 _distributorId, address account, uint256 amount) whenNotPaused external {
        require(amount > 0, "amount must be greater than 0");
        address distributor = idToDistributor[_distributorId];
        require(distributor == msg.sender, "distributor not registered");
        require(allocated[distributor] >= amount, "insufficient allocated balance");
        allocated[distributor] -= amount;

        token.safeTransfer(account, amount);
    }

    /**
     * @dev allocate new emissions to distributor
     * @param id distributor id
     * @return amount allocated amount
     */
    function allocateNewEmissions(uint16 id) external returns (uint256) {
        address distributor = idToDistributor[id];
        require(distributor == msg.sender, "Distributor not registered");

        uint16 week = distributorUpdatedWeek[id];
        uint16 currentWeek = veLista.getCurrentWeek();
        if (week == currentWeek) return 0;

        uint256 amount;
        while (week < currentWeek) {
            ++week;
            amount += getDistributorWeeklyEmissions(id, week);
        }

        distributorUpdatedWeek[id] = currentWeek;
        allocated[msg.sender] += amount;
        emit IncreasedAllocation(msg.sender, amount);
        return amount;
    }

    /**
     * @dev get distributor weekly emissions
     * @param id distributor id
     * @param week week number
     * @return emissions
     */
    function getDistributorWeeklyEmissions(uint16 id, uint16 week) public view returns (uint256) {
        // emission voting contract not set OR override voting result
        if (emissionVoting == IEmissionVoting(address(0)) || weeklyDistributorPercent[week][0] == 1) {
            uint256 pct = weeklyDistributorPercent[week][id];
            return Math.mulDiv(weeklyEmissions[week], pct, 1e18);
        }
        // no one votes
        if (emissionVoting.getWeeklyTotalWeight(week) == 0) {
            return 0;
        }
        // @dev emission = weeklyEmissions[week] * distributorWeight / totalWeight
        return Math.mulDiv(
            weeklyEmissions[week],
            emissionVoting.getDistributorWeeklyTotalWeight(id, week),
            emissionVoting.getWeeklyTotalWeight(week)
        );
    }

    /**
     * @dev get week number by timestamp
     * @param timestamp timestamp
     * @return week number
     */
    function getWeek(uint256 timestamp) public view returns (uint16) {
        if (timestamp < veLista.startTime()) {
            return 0;
        }
        return veLista.getWeek(timestamp);
    }

    /**
     * @dev allows manager to withdraw reward tokens for emergency or recover any other mistaken ERC20 tokens.
      * @param token ERC20 token address
      * @param amount token amount
      */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(MANAGER) {
        IERC20(token).safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(token, amount);
    }

    /**
      * @dev batch claim rewards with proxy
      * @param account user address
      * @param _distributors distributor addresses
      */
    function batchClaimRewardsWithProxy(address account, address[] memory _distributors) external onlyLpProxy whenNotPaused {
        _batchClaimRewards(account, _distributors);
    }

    /**
      * @dev set lp proxy address
      * @param _lpProxy lp proxy address
      */
    function setLpProxy(address _lpProxy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_lpProxy != address(0), "lpProxy cannot be zero address");
        lpProxy = _lpProxy;
    }

    function _pause() private whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() private whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(PAUSER) {
        _pause();
    }

    /**
     * @dev Flips the pause state
     */
    function togglePause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused ? _unpause() : _pause();
    }
}
