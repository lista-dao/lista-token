pragma solidity ^0.8.10;

interface OracleInterface {
    function peek(address asset) external view returns (uint256);
}