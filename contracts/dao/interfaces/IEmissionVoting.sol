// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { EmissionVoting } from "../EmissionVoting.sol";
interface IEmissionVoting {
  function ADMIN_VOTER() external view returns (bytes32);
  function hasRole(bytes32 role, address account) external view returns (bool);
  function getWeeklyTotalWeight(uint16 week) external view returns (uint256);
  function getDistributorWeeklyTotalWeight(uint16 distributorId, uint16 week) external view returns (uint256);
  function getUserVotedDistributors(address user, uint16 week) external view returns (EmissionVoting.Vote[] memory);
  function userVotedDistributorIndex(address user, uint16 week, uint16 distributorId) external view returns (uint256);
}
