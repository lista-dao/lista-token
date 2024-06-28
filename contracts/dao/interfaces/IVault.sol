pragma solidity ^0.8.10;

interface IVault {
    function allocateNewEmissions(uint16 id) external returns (uint256);
    function getWeek(uint256 timestamp) external view returns (uint16);
    function transferAllocatedTokens(uint16 _receiverId, address account, uint256 amount) external;
    function getDistributorWeeklyEmissions(uint16 id, uint16 week) external view returns (uint256);
}
