// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVeLista {

    struct LockedData {
        uint16 week; // lock week number
        uint256 locked; // locked amount
        uint256 weight; // weight of the lock
        uint256 autoLockAmount; // auto lock amount
    }

    struct UnlockedData {
        uint16 week; // unlock week number
        uint256 unlocked; // unlocked amount
    }

    struct AccountData {
        uint256 locked; // total locked amount
        uint16 lastLockWeek; // last lock week
        uint16 lockWeeks; // lock weeks
        bool autoLock; // auto lock status
        uint256 lockTimestamp; // lock timestamp
    }

    function getWeek(uint256 timestamp) external view returns (uint16);

    function getCurrentWeek() external view returns (uint16);

    function startTime() external view returns (uint256);

    function lock(uint256 amount, uint16 week, bool autoLock) external;

    function relockUnclaimed(uint16 week, bool autoLock) external;

    function increaseAmount(uint256 _amount) external;

    function increaseAmountForCompound(address _account, uint256 _amount) external;

    function extendWeek(uint16 _week) external;

    function balanceOf(address account) external view returns (uint256);

    function balanceOfAtTime(address account, uint256 timestamp) external view returns (uint256);

    function balanceOfAtWeek(address account, uint16 week) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalSupplyAtWeek(uint16 week) external view returns (uint256);

    function totalSupplyAtTime(uint256 timestamp) external view returns (uint256);

    function claim() external returns (uint256);

    function earlyClaim() external returns (uint256);

    function disableAutoLock() external;

    function enableAutoLock() external;

    function getLockedData(address account) external view returns (AccountData memory);

    function claimPenalty() external;

    function getPenalty(address _account) external view returns (uint256);

    function token() external view returns (IERC20);

    event LockCreated(address indexed account, uint256 amount, uint16 week, bool autoLock);
    event LockAmountIncreased(address indexed account, uint256 amount);
    event LockWeekExtended(address indexed account, uint16 week);
    event Claimed(address indexed account, uint256 amount);
    event EarlyClaimed(address indexed account, uint256 amount, uint256 penalty);
    event DisableAutoLock(address indexed account);
    event EnableAutoLock(address indexed account);
    event PenaltyClaimed(address indexed account, uint256 amount);
}
