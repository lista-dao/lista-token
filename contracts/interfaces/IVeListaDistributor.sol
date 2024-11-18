// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IVeLista.sol";

interface IVeListaDistributor {
    function veLista() external view returns (IVeLista);

    function getTokenClaimable(address _account, address _token, uint16 toWeek) external view returns (uint256, uint16);

    function claimForCompound(address _account, address _lista, uint16 toWeek) external returns (uint256 _claimedAmount);
}