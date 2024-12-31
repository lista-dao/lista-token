// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface ICollateralDistributor {
    function takeSnapshot(address _token, address _user, uint256 _ink) external;
}

interface IBorrowDistributor {
    function takeSnapshot(address _token, address _user, uint256 _debt) external;
    function lpToken() external view returns (address);
}
