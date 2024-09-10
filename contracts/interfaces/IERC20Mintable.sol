pragma solidity ^0.8.10;

interface IERC20Mintable {
    function mint(address to, uint256 value) external returns (bool);
}