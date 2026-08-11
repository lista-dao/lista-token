// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../MerkleVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ClisBNBLaunchPoolDistributor
 * @author Lista
 * @dev Distribute rewards to users based on their clisBNB balance which is calculated by off chain service
 */
contract ClisBNBLaunchPoolDistributor is Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;

    event UpdateEpoch(uint64 epochId, bytes32 merkleRoot, address token, uint256 startTime, uint256 endTime, uint256 amount);

    event RevokeEpoch(uint64 epochId, address token, uint256 totalAmount, uint256 unclaimedAmount);

    event CollectUnclaimed(uint64 epochId, address token, uint256 totalAmount, uint256 unclaimedAmount);

    event Claimed(address account, uint64 epochId, address token, uint256 amount);

    event TopUpEpoch(uint64 epochId, address token, uint256 oldTotalAmount, uint256 newTotalAmount, uint256 addedAmount);

    struct Epoch {
        // merkle root of an epoch
        bytes32 merkleRoot;
        // reward token of an epoch, address(0) means BNB
        address token;
        // start time of an epoch
        uint256 startTime;
        // start time of an epoch
        uint256 endTime;
        // total reward amount of an epoch
        uint256 totalAmount;
        // unclaimed reward amount of an epoch
        uint256 unclaimedAmount;
    }

    // epochId => (merkleRoot, reward)
    // epochId is the id of setting merkle root
    // merkleRoot is the root of the merkle tree for the reward epoch
    // epochReward is the total reward for the epoch
    mapping(uint64 => Epoch) public epochs;

    // epochId => userAddress => claimed
    mapping(uint64 => mapping(address => bool)) public claimed;

    // auto increment id for epoch
    uint64 public nextEpochId;

    // since merkleRoot/epochReward can be updated/revoked within the same week of setting (one week dispute period),
    // we need to keep track of the unsettled reward
    // token => unclaimedAmount
    mapping(address => uint256) public totalUnclaimedAmount;

    // OPERATOR role
    bytes32 public constant OPERATOR = keccak256("OPERATOR");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @param _admin Address of the admin
     */
    function initialize(address _admin) external initializer {
        require(_admin != address(0), "Invalid admin address");

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
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
        require(epoch.merkleRoot != bytes32(0), "Invalid epochId");
        require(epoch.startTime <= block.timestamp && epoch.endTime >= block.timestamp, "Inactive epoch");

        bytes32 leaf = keccak256(abi.encode(block.chainid, _epochId, _account, _amount));
        MerkleVerifier._verifyProof(leaf, epoch.merkleRoot, _proof);
        claimed[_epochId][_account] = true;
        totalUnclaimedAmount[epoch.token] -= _amount;
        epoch.unclaimedAmount -= _amount;

        _transferTo(_account, epoch.token, _amount);
        emit Claimed(_account, _epochId, epoch.token, _amount);
    }

    /**
     * @dev Set merkle root for rewards epoch.
     * @param _epochId Epoch Id of the reward epoch
     * @param _merkleRoot Merkle root of the reward epoch
     * @param _token Reward token of the reward epoch, address(0) means BNB
     * @param _startTime Start time of the reward epoch
     * @param _endTime End time of the reward epoch
     * @param _totalAmount Total amount of the reward epoch
     */
    function setEpochMerkleRoot(uint64 _epochId, bytes32 _merkleRoot, address _token, uint256 _startTime, uint256 _endTime, uint256 _totalAmount)
        external onlyRole(OPERATOR)
    {
        require(_epochId == nextEpochId, "Invalid epochId");
        require(_merkleRoot != bytes32(0), "Invalid merkle root");
        require(_startTime > block.timestamp, "Invalid start time");
        require(_endTime > _startTime, "Invalid end time");
        require(_totalAmount > 0, "Invalid total amount");

        uint64 currentEpochId = nextEpochId++;
        Epoch storage epoch = epochs[currentEpochId];
        epoch.merkleRoot = _merkleRoot;
        epoch.token = _token;
        epoch.startTime = _startTime;
        epoch.endTime = _endTime;
        epoch.totalAmount = _totalAmount;
        epoch.unclaimedAmount = _totalAmount;
        totalUnclaimedAmount[_token] += _totalAmount;

        emit UpdateEpoch(currentEpochId, epoch.merkleRoot, epoch.token, epoch.startTime, epoch.endTime, epoch.totalAmount);
    }

    /**
     * @dev Raise an existing epoch's total to the correct amount (= sum of merkle leaves).
     *      Fixes epochs whose totalAmount was set below the leaf sum, which otherwise makes
     *      `claim` underflow `unclaimedAmount` for tail users once the under-set cap is drained.
     *      The merkle root is unchanged (it already contains every user); only the accounting
     *      caps are raised. Restricted to DEFAULT_ADMIN_ROLE (like collectUnclaimed /
     *      adminTransfer). The admin must fund the missing tokens into this contract first;
     *      the solvency check rejects raising the cap above the contract's actual balance. Only
     *      allowed while the epoch is still within its claim window, since a topped-up ended
     *      epoch would still be unclaimable via `claim` and merely strand the added amount.
     * @param _epochId Id of epoch
     * @param _newTotalAmount New total amount of the epoch, must exceed the current totalAmount
     */
    function topUpEpoch(uint64 _epochId, uint256 _newTotalAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Epoch storage epoch = epochs[_epochId];
        require(epoch.merkleRoot != bytes32(0), "Invalid epochId");
        require(block.timestamp <= epoch.endTime, "Epoch ended");
        require(_newTotalAmount > epoch.totalAmount, "Not an increase");

        uint256 oldTotalAmount = epoch.totalAmount;
        uint256 added = _newTotalAmount - oldTotalAmount;

        epoch.totalAmount = _newTotalAmount;
        epoch.unclaimedAmount += added;
        totalUnclaimedAmount[epoch.token] += added;

        require(_balanceOf(epoch.token) >= totalUnclaimedAmount[epoch.token], "Insufficient funds");

        emit TopUpEpoch(_epochId, epoch.token, oldTotalAmount, _newTotalAmount, added);
    }

    /**
     * @dev Revoke the reward of the given epoch;
     * @param _epochId Id of epoch
     */
    function revokeEpoch(uint64 _epochId) external onlyRole(OPERATOR) {
        Epoch storage epoch = epochs[_epochId];
        require(epoch.startTime > block.timestamp, "Epoch already started");
        require(epoch.totalAmount > 0, "Invalid epochId");

        address token = epoch.token;
        uint256 epochTotalAmount = epoch.totalAmount;
        uint256 epochUnclaimedAmount = epoch.unclaimedAmount;
        totalUnclaimedAmount[token] -= epochUnclaimedAmount;

        delete epochs[_epochId];

        emit RevokeEpoch(_epochId, token, epochTotalAmount, epochUnclaimedAmount);
    }

    /**
     * @dev Collect unclaimed rewards amount of the given ended epoch
     * @param _epochId Id of epoch
     */
    function collectUnclaimed(uint64 _epochId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Epoch storage epoch = epochs[_epochId];
        require(epoch.totalAmount > 0, "Invalid epochId");
        require(epoch.unclaimedAmount > 0, "No unclaimed amount");
        require(epoch.endTime < block.timestamp, "Epoch not ended");

        address token = epoch.token;
        uint256 epochUnclaimedAmount = epoch.unclaimedAmount;
        totalUnclaimedAmount[token] -= epochUnclaimedAmount;
        epoch.unclaimedAmount = 0;

        _transferTo(msg.sender, token, epochUnclaimedAmount);
        emit CollectUnclaimed(_epochId, token, epoch.totalAmount, epochUnclaimedAmount);
    }

    /**
     * @dev Transfer the given amount to the admin
     * @param _amount Amount to transfer
     */
    function adminTransfer(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount > 0, "Invalid amount");
        _transferTo(msg.sender, _token, _amount);
    }

    function _transferTo(address _to, address _token, uint256 _amount) private {
        if (_token == address(0)) {
            (bool success,) = payable(_to).call{value: _amount}("");
            require(success, "Transfer BNB failed");
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    function _balanceOf(address _token) private view returns (uint256) {
        return _token == address(0) ? address(this).balance : IERC20(_token).balanceOf(address(this));
    }

    function getEpochs(uint64[] memory _epochIds) external view returns (Epoch[] memory) {
        Epoch[] memory _epochs = new Epoch[](_epochIds.length);
        for (uint256 i = 0; i < _epochIds.length; i++) {
            _epochs[i] = epochs[_epochIds[i]];
        }

        return _epochs;
    }

    receive() external payable {}
}
