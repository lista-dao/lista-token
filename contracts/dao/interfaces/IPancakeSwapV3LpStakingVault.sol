// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IPancakeSwapV3LpStakingVault {
    function batchClaimRewardsWithProxy(address account, address[] memory providers, uint256[][] memory tokenIds) external;
}