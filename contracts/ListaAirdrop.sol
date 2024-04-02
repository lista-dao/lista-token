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

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setStartBlock(uint256 _startBlock) external onlyOwner {
        require(_startBlock != startBlock, "Start block already set");
        startBlock = _startBlock;
    }

    function setEndBlock(uint256 _endBlock) external onlyOwner {
        require(_endBlock != endBlock, "End block already set");
        require(_endBlock > startBlock, "Invalid end block");
        endBlock = _endBlock;
    }

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

    function reclaim(uint256 amount) external onlyOwner {
        require(block.timestamp > reclaimPeriod && block.number > endBlock, "Tokens cannot be reclaimed");
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }
}