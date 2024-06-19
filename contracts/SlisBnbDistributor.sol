// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./dao/interfaces/IVault.sol";
import "./MerkleVerifier.sol";

contract SlisBnbDistributor is Initializable, AccessControlUpgradeable {
    // LISTA vault; lista token will be transferred from this vault to users directly upon claim success
    IVault public vault;

    // the id of slisBnb distributor
    uint16 private distributorId;

    // week => bi-weekly merkle root
    mapping(uint16 => bytes32) public merkleRoots;

    // week => account => claimed
    mapping(uint16 => mapping(address => bool)) public claimed;

    // claim expires after week + expireDelay
    uint256 public expireDelay = 10 weeks;

    // vault role
    bytes32 public constant VAULT = keccak256("VAULT");

    event SetMerkleRoot(uint16 week, bytes32 merkleRoot);
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
         _setupRole(DEFAULT_ADMIN_ROLE, _admin);
         _setupRole(VAULT, _vault);
    }

    /**
     * @dev Set merkle root for rewards epoch. Merkle root can only be updated before the epoch starts.
     * @param _merkleRoot Merkle root of the rewards period
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_merkleRoot != bytes32(0), "Invalid merkle root");
        uint16 _week = vault.getWeek(block.timestamp);

        if (merkleRoots[_week] == bytes32(0)) {
            vault.allocateNewEmissions(distributorId);
        }

        merkleRoots[_week] = _merkleRoot;

        emit SetMerkleRoot(_week, _merkleRoot);
    }

    /**
     * @dev Claim Lista rewards. Can be called by anyone as long as proof is valid. Rewards are available after the rewards period ends.
     * @param week Week of the rewards period
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
        MerkleVerifier._verifyProof(leaf, merkleRoots[week], proof);

        claimed[week][account] = true;

        uint256 amount = weight * vault.getDistributorWeeklyEmissions(distributorId, week) / 1e18;
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
     * @param _expireDelay Expire delay in seconds
     */
    function setExpireDelay(uint256 _expireDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_expireDelay != expireDelay, "Already set");
        expireDelay = _expireDelay;

        emit ExpireDelaySet(_expireDelay);
    }
}
