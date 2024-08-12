// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IVault.sol";
import "../MerkleVerifier.sol";

/*
    * @title SlisBnbDistributor
    * @author Lista
    * @dev Distribute rewards to users based on their slisBnb balance
*/
contract SlisBnbDistributor is Initializable, AccessControlUpgradeable {
    // LISTA vault; lista token will be transferred from this vault to users directly upon claim success
    IVault public vault;

    // the id of slisBnb distributor
    uint16 public distributorId;

    // week => (merkleRoot, reward)
    // week is the week of setting merkle root
    // merkleRoot is the root of the merkle tree for the reward epoch
    // epochReward is the total reward for the epoch
    mapping(uint16 => Epoch) public epochs;

    // week => account => claimed
    mapping(uint16 => mapping(address => bool)) public claimed;

    // claim expires after week + expireDelay
    uint256 public expireDelay;

    // unsettledReward is not yet finalized and will be included in the next epoch
    // since merkleRoot/epochReward can be updated/revoked within the same week of setting (one week dispute period),
    // we need to keep track of the unsettled reward
    uint256 public unsettledReward;

    // vault role
    bytes32 public constant VAULT = keccak256("VAULT");

    struct Epoch {
        // merkle root of an epoch
        bytes32 merkleRoot;
        // total reward of an epoch
        uint256 reward;
    }
    event UpdateEpoch(uint16 week, bytes32 merkleRoot, uint256 reward, uint256 unsettledReward);
    event Claimed(address account, uint256 amount, uint16 week);
    event ExpireDelaySet(uint256 expireDelay);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @param _vault Address of Lista vault contract
     * @param _admin Address of the admin
     * @param _expireDelay Expire delay in seconds
     */
    function initialize(address _vault, address _admin, uint256 _expireDelay) external initializer {
        require( _vault != address(0) && _admin != address(0), "Invalid address");

        vault = IVault(_vault);
        expireDelay = _expireDelay;
        _setRoleAdmin(VAULT, DEFAULT_ADMIN_ROLE);
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(VAULT, _vault);
    }

    /**
     * @dev Set merkle root for rewards epoch.
     * @param _merkleRoot Merkle root of the reward epoch
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_merkleRoot != bytes32(0), "Invalid merkle root");
        uint16 _currentWeek = vault.getWeek(block.timestamp);

        Epoch storage epoch = epochs[_currentWeek];

        // Sync reward from the vault; fetch all unallocated rewards up to the current week, current week inclusive
        uint256 totalAllocated = epoch.reward + vault.allocateNewEmissions(distributorId);

        uint256 currentWeekReward = vault.getDistributorWeeklyEmissions(distributorId, _currentWeek);

        // Rewards of current week will be excluded from the current epoch because they're not included in the merkle root
        epoch.reward = totalAllocated + unsettledReward - currentWeekReward;
        require(epoch.reward > 0, "No reward for the epoch");

        // Rewards of current week will be included in the next epoch
        unsettledReward = currentWeekReward;

        epoch.merkleRoot = _merkleRoot;

        emit UpdateEpoch(_currentWeek, _merkleRoot, epoch.reward, unsettledReward);
    }

    /**
     * @dev Revoke the reward of the current epoch;
     *      the revoked amount will be added to unsettled reward which will be included in the next epoch
     */
    function revokeReward() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 _currentWeek = vault.getWeek(block.timestamp);
        Epoch storage epoch = epochs[_currentWeek];
        require(epoch.reward != 0, "No reward to revoke");

        unsettledReward += epoch.reward;
        epoch.reward = 0;
        epoch.merkleRoot = bytes32(0);

        emit UpdateEpoch(_currentWeek, epoch.merkleRoot, epoch.reward, unsettledReward);
    }

    /**
     * @dev Claim Lista rewards. Can be called by anyone as long as proof is valid. Rewards are available after the one week dispute period ends.
     * @param week Week of the rewards epoch
     * @param account Address of the recipient
     * @param weight Weight of the user's slisBnb balance against the total slisBnb balance
     * @param proof Merkle proof of the claim
     */
    function claim(
        uint16 week,
        address account,
        uint256 weight,
        bytes32[] memory proof
    ) external {
        uint16 currentWeek = vault.getWeek(block.timestamp);
        require(currentWeek <= week + expireDelay, "Claim expired");
        require(currentWeek > week, "Unable to claim yet");
        require(!claimed[week][account], "Airdrop already claimed");

        bytes32 leaf = keccak256(abi.encode(block.chainid, week, account, weight));
        Epoch memory epoch = epochs[week];
        MerkleVerifier._verifyProof(leaf, epoch.merkleRoot, proof);

        claimed[week][account] = true;

        uint256 amount = weight * epoch.reward / 1e18;
        vault.transferAllocatedTokens(distributorId, account, amount);

        emit Claimed(account, amount, week);
    }

    /**
     * @dev Notify the registered distributor id; can only be called by the lista vault
     * @param _distributorId Distributor id
     */
    function notifyRegisteredId(uint16 _distributorId) onlyRole(VAULT) external returns (bool) {
        require(distributorId == 0, "Already registered");
        require(_distributorId > 0, "Invalid distributor id");
        distributorId = _distributorId;
        return true;
    }

    /**
     * @dev Set the claim expire delay
     * @param _expireDelay Expire delay in weeks
     */
    function setExpireDelay(uint256 _expireDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_expireDelay != expireDelay, "Already set");
        expireDelay = _expireDelay;

        emit ExpireDelaySet(_expireDelay);
    }
}
