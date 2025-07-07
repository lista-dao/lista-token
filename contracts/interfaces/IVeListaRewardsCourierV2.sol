// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IVeLista.sol";

interface IVeListaRewardsCourierV2 {
    function rechargeRewards(uint256 amount) external;
}
