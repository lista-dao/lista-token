// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../MerkleVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SlisBnbDistributor
 * @author Lista
 * @dev Distribute rewards to users based on their clisBNB balance
 */
contract ClisBNBLaunchPoolDistributor is Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;

    event UpdateEpoch(uint64 epochId, bytes32 merkleRoot, uint256 startTime, uint256 endTime, uint256 amount);

    event RevokeEpoch(uint64 epochId, uint256 totalAmount, uint256 unclaimedAmount);

    event CollectUnclaimed(uint64 epochId, uint256 totalAmount, uint256 unclaimedAmount);

    event Claimed(address account, uint64 epochId, uint256 amount);

    struct Epoch {
        // merkle root of an epoch
        bytes32 merkleRoot;
        // start time of an epoch
        uint256 startTime;
        // start time of an epoch
        uint256 endTime;
        // total reward amount of an epoch
        uint256 totalAmount;
        // unclaimed reward amount of an epoch
        uint256 unclaimedAmount;
    }

    bytes32 public constant MANAGER = keccak256("MANAGER");

    // epochId => (merkleRoot, reward)
    // epochId is the id of setting merkle root
    // merkleRoot is the root of the merkle tree for the reward epoch
    // epochReward is the total reward for the epoch
    mapping(uint64 => Epoch) public epochs;

    // epochId => userAddress => claimed
    mapping(uint64 => mapping(address => bool)) public claimed;

    // reward token
    address public token;

    // totalUnclaimedAmount is not yet finalized and will be included in the next epoch
    // since merkleRoot/epochReward can be updated/revoked within the same week of setting (one week dispute period),
    // we need to keep track of the unsettled reward
    uint256 public totalUnclaimedAmount;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @param _admin Address of the admin
     * @param _manager Address of the manager
     * @param _token Reward Token
     */
    function initialize(address _admin, address _manager, address _token) external initializer {
        require(_admin != address(0), "Invalid admin address");
        require(_token != address(0), "Invalid token address");

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);

        token = _token;
    }

    /**
     * @dev Claim Lista rewards. Can be called by anyone as long as proof is valid.
     * @param _epochId Id of epoch
     * @param _account Address of the recipient
     * @param _amount Reward amount of Lista to user
     * @param _proof Merkle proof of the claim
     */
    function claim(
        uint64 _epochId,
        address _account,
        uint256 _amount,
        bytes32[] memory _proof
    ) external {
        require(_amount > 0, "Invalid amount");
        require(!claimed[_epochId][_account], "User already claimed");

        Epoch storage epoch = epochs[_epochId];
        require(epoch.startTime > 0, "Invalid epochId");
        require(epoch.startTime <= block.timestamp && epoch.endTime >= block.timestamp, "Inactive epoch");

        bytes32 leaf = keccak256(abi.encode(block.chainid, _epochId, _account, _amount));
        MerkleVerifier._verifyProof(leaf, epoch.merkleRoot, _proof);
        claimed[_epochId][_account] = true;
        if (epoch.unclaimedAmount >= _amount) {
            epoch.unclaimedAmount -= _amount;
        } else if (epoch.unclaimedAmount > 0) {
            epoch.unclaimedAmount = 0;
        }

        IERC20(token).safeTransfer(_account, _amount);

        emit Claimed(_account, _epochId, _amount);
    }

    /**
     * @dev Set merkle root for rewards epoch.
     * @param _epochId Id of the reward epoch
     * @param _merkleRoot Merkle root of the reward epoch
     * @param _startTime Start time of the reward epoch
     * @param _endTime End time of the reward epoch
     * @param _totalAmount Total amount of the reward epoch
     */
    function setEpochMerkleRoot(uint64 _epochId, bytes32 _merkleRoot, uint256 _startTime, uint256 _endTime, uint256 _totalAmount)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_merkleRoot != bytes32(0), "Invalid merkle root");
        require(_startTime > 0, "Invalid start time");
        require(_endTime > 0, "Invalid end time");
        require(_totalAmount > 0, "Invalid total amount");

        Epoch storage epoch = epochs[_epochId];
        epoch.merkleRoot = _merkleRoot;
        epoch.startTime = _startTime;
        epoch.endTime = _endTime;
        epoch.totalAmount = _totalAmount;
        epoch.unclaimedAmount = _totalAmount;
        totalUnclaimedAmount += _totalAmount;

        emit UpdateEpoch(_epochId, epoch.merkleRoot, epoch.startTime, epoch.endTime, epoch.totalAmount);
    }

    /**
     * @dev Revoke the reward of the given epoch;
     * @param _epochId Id of epoch
     */
    function revokeEpoch(uint64 _epochId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Epoch storage epoch = epochs[_epochId];
        require(epoch.totalAmount > 0, "Invalid epochId");

        uint256 epochTotalAmount = epoch.totalAmount;
        uint256 epochUnclaimedAmount = epoch.unclaimedAmount;
        epoch.totalAmount = 0;
        epoch.unclaimedAmount = 0;
        epoch.merkleRoot = bytes32(0);
        epoch.startTime = 0;
        epoch.endTime = 0;
        totalUnclaimedAmount -= epochUnclaimedAmount;

        emit RevokeEpoch(_epochId, epochTotalAmount, epochUnclaimedAmount);
    }

    function collectUnclaimed(uint64 _epochId) external onlyRole(MANAGER) {
        Epoch storage epoch = epochs[_epochId];
        require(epoch.totalAmount > 0, "Invalid epochId");
        require(epoch.unclaimedAmount > 0, "No unclaimed amount");
        require(epoch.endTime < block.timestamp, "Epoch not ended");

        uint256 epochUnclaimedAmount = epoch.unclaimedAmount;
        totalUnclaimedAmount -= epochUnclaimedAmount;
        epoch.unclaimedAmount = 0;

        emit CollectUnclaimed(_epochId, epoch.totalAmount, epochUnclaimedAmount);
    }

    /**
     * @dev Transfer the given amount to the admin
     * @param _amount Amount to transfer
     */
    function adminTransfer(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount > 0, "Invalid amount");
        IERC20(token).safeTransfer(msg.sender, _amount);
    }

    function getTokenBalance() external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
