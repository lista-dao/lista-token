// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IEmissionVoting {
    function getWeeklyTotalWeight(uint16 week) external view returns (uint256);
    function getDistributorWeeklyTotalWeight(uint16 distributorId, uint16 week) external view returns (uint256);
}
