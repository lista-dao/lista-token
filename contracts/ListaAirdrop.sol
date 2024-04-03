// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./MerkleVerifier.sol";

contract ListaAirdrop is Ownable {

    uint256 public reclaimPeriod;
    address public token;
    bytes32 public merkleRoot;
    uint256 public startBlock;
    uint256 public endBlock;
    mapping(bytes32 => bool) public claimed;

    event Claimed(address account, uint256 amount);

    /**
     * @param _token Address of the token to be airdropped
     * @param _merkleRoot Merkle root of the merkle tree generated for the airdrop by off-chain service
     * @param reclaimDelay Delay in seconds after contract creation for reclaiming unclaimed tokens
     * @param _startBlock Block number when airdrop claim starts
     * @param _endBlock Block number when airdrop claim ends
     */
    constructor(address _token, bytes32 _merkleRoot, uint256 reclaimDelay, uint256 _startBlock, uint256 _endBlock) {
        require(_startBlock >= block.number, "Invalid start block");
        require(_endBlock > _startBlock, "Invalid end block");
        require(_token != address(0), "Invalid token address");
        token = _token;
        merkleRoot = _merkleRoot;
        reclaimPeriod = block.timestamp + reclaimDelay;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    /**
     * @dev Update merkle root. Merkle root can only be updated before the airdrop starts.
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        require(block.number < startBlock, "Cannot change merkle root after airdrop has started");
        merkleRoot = _merkleRoot;
    }

    /**
     * @dev Set start block of airdrop. Users can only claim airdrop after the new start block.
     */
    function setStartBlock(uint256 _startBlock) external onlyOwner {
        require(_startBlock != startBlock, "Start block already set");
        require(_startBlock < endBlock, "Invalid start block");

        startBlock = _startBlock;
    }

    /**
     * @dev Set end block of airdrop. Users are not allowed to claim airdrop after the new end block.
     */
    function setEndBlock(uint256 _endBlock) external onlyOwner {
        require(_endBlock != endBlock, "End block already set");
        require(_endBlock > startBlock, "Invalid end block");
        endBlock = _endBlock;
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
        require(block.number >= startBlock && block.number <= endBlock, "Airdrop not started or has ended");
        bytes32 leaf = keccak256(abi.encodePacked(account, amount));
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
        require(block.timestamp > reclaimPeriod && block.number > endBlock, "Tokens cannot be reclaimed");
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }
}