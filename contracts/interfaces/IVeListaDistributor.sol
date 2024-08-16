// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IVeListaDistributor {

  struct TokenAmount {
    address token;
    uint256 amount;
  }

  function rewardTokenIndexes(address _token) external view returns (uint8);

  function depositNewReward(uint16 _week, TokenAmount[] memory _tokens) external;

}
