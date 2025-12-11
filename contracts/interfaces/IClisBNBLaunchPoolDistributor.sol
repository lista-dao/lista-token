// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IClisBNBLaunchPoolDistributor {
    function setEpochMerkleRoot(uint64 _epochId, bytes32 _merkleRoot, address _token, uint256 _startTime, uint256 _endTime, uint256 _totalAmount) external;
}