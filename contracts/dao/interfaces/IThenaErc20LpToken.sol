// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IThenaErc20LpToken {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getTotalAmounts() external view returns (uint256 total0, uint256 total1);
    function currentTick() external view returns (int24);
    function token0() external view returns (address);
    function token1() external view returns (address);
}
