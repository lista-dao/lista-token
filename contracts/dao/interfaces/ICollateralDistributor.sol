// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface ICollateralDistributor {
    function takeSnapshot(address _token, address _user, uint256 _ink) external;
}
