// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./MerkleVerifier.sol";

contract ListaAirdrop is Ownable {

    uint256 public reclaimPeriod;
    address public token;
    bytes32 public merkleRoot;
    uint256 public startTime;
    uint256 public endTime;
    mapping(bytes32 => bool) public claimed;

    event Claimed(address account, uint256 amount);

    /**
     * @param _token Address of the token to be airdropped
     * @param _merkleRoot Merkle root of the merkle tree generated for the airdrop by off-chain service
     * @param reclaimDelay Delay in seconds after contract creation for reclaiming unclaimed tokens
     * @param _startTime Block timestamp when airdrop claim starts
     * @param _endTime Block timestamp when airdrop claim ends
     */
    constructor(address _token, bytes32 _merkleRoot, uint256 reclaimDelay, uint256 _startTime, uint256 _endTime) {
        require(_startTime >= block.timestamp, "Invalid start time");
        require(_endTime > _startTime, "Invalid end time");
        require(_token != address(0), "Invalid token address");
        token = _token;
        merkleRoot = _merkleRoot;
        reclaimPeriod = block.timestamp + reclaimDelay;
        startTime = _startTime;
        endTime = _endTime;
    }

    /**
     * @dev Update merkle root. Merkle root can only be updated before the airdrop starts.
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        require(block.timestamp < startTime, "Cannot change merkle root after airdrop has started");
        merkleRoot = _merkleRoot;
    }

    /**
     * @dev Set start Block timestamp of airdrop. Users can only claim airdrop after the new start time.
     */
    function setStartTime(uint256 _startTime) external onlyOwner {
        require(_startTime != startTime, "Start time already set");
        require(endTime > _startTime, "Invalid start time");

        startTime = _startTime;
    }

    /**
     * @dev Set end Block timestamp of airdrop. Users are not allowed to claim airdrop after the new end time.
     */
    function setEndTime(uint256 _endTime) external onlyOwner {
        require(_endTime != endTime, "End time already set");
        require(_endTime > startTime, "Invalid end time");
        endTime = _endTime;
    }

    /**
     * @dev Claim airdrop rewards. Can be called by anyone as long as proof is valid.
     * @param account Address of the recipient
     * @param amount Amount of tokens to claim
     * @param proof Merkle proof of the claim
     */
    function claim(
        address account,
        uint256 amount,
        bytes32[] memory proof
    ) external {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Airdrop not started or has ended");
        bytes32 leaf = keccak256(abi.encodePacked(account, amount)); // Use abi.encode to deal with more than one dynamic types to prevents collision
        require(!claimed[leaf], "Airdrop already claimed");
        MerkleVerifier._verifyProof(leaf, merkleRoot, proof);
        claimed[leaf] = true;

        require(IERC20(token).transfer(account, amount), "Transfer failed");

        emit Claimed(account, amount);
    }

    /**
     * @dev Reclaim unclaimed airdrop rewards after the reclaim period expires by contract owner.
     * @param amount Amount of tokens to reclaim
     */
    function reclaim(uint256 amount) external onlyOwner {
        require(block.timestamp > reclaimPeriod && block.timestamp > endTime, "Tokens cannot be reclaimed");
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }
}
