// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.10;

interface IERC20TokenProvider {
    function deposit(uint256 amount) external returns (uint256);
    function deposit(uint256 amount, address delegateTo) external returns (uint256);
    function withdraw(uint256 amount) external returns (uint256);
    function delegateAllTo(address newDelegateTo) external;
}
