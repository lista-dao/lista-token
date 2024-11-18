pragma solidity ^0.8.10;

interface IGaugeV2 {
    function emergency() external view returns (bool);

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function emergencyWithdraw() external;
}
