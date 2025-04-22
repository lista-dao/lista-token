// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.10;

interface IERC20LpProvidableDistributor {
    function balanceOf(address account) external view returns (uint256);

    function depositFor(uint256 amount, address account) external;

    function withdrawFor(uint256 amount, address account) external;

    function getUserLpTotalValueInQuoteToken(address account) external view returns (uint256);

    function getLpToQuoteToken(uint256 amount) external view returns (uint256);

    function notifyStakingReward(uint256 amount) external;
}
