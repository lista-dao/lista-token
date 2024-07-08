// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

abstract contract TransferLimiter {

  struct TransferLimit {
    uint32 dstEid;
    uint256 maxDailyTransferAmount;
    uint256 singleTransferUpperLimit;
    uint256 singleTransferLowerLimit;
    uint256 dailyTransferAmountPerAddress;
    uint256 dailyTransferAttemptPerAddress;
  }

  // @notice Configurations per destination endpoint id
  // @dev destination endpoint id => TransferLimit
  mapping(uint32 dstEid => TransferLimit limit) public transferLimitConfigs;

  // ------- global limits -------
  // @notice records the total amount of tokens transferred to a destination endpoint id
  // @dev destination endpoint id => amount
  mapping(uint32 dstEid => uint256 amount) public dailyTransferAmount;
  // @notice records the timestamp of the latest transfer made to a destination endpoint id
  // @dev destination endpoint id => last updated time
  mapping(uint32 dstEid => uint256 lastUpdatedTime) public lastUpdatedTime;

  // ------- limits per address -------
  // @notice Records the amount of tokens transferred by a user
  // @dev destination endpoint id => user address => amount
  mapping(uint32 dstEid => mapping(address user => uint256 amount)) public userDailyTransferAmount;
  // @notice Records the number of transfer attempts made by a user
  // @dev destination endpoint id => user address => number of attempts
  mapping(uint32 dstEid => mapping(address user => uint256 attempt)) public userDailyAttempt;
  // @notice Records the last succeed transfer of the user
  // @dev records the last succeed transfer of the user
  mapping(uint32 dstEid => mapping(address user => uint256 updatedTime)) public lastUserUpdatedTime;

  // -------- Events --------
  // @dev event of transfer limit changed
  event TransferLimitChanged(
    uint32 dstEid,
    uint256 maxDailyTransferAmount,
    uint256 singleTransferUpperLimit,
    uint256 singleTransferLowerLimit,
    uint256 dailyTransferAmountPerAddress,
    uint256 dailyTransferAttemptPerAddress
  );

  // -------- Errors --------
  // @dev Error that is thrown when an amount exceeds the rate_limit.
  error TransferLimitExceeded();
  // @dev Error that is thrown when the transfer limit is not set.
  error TransferLimitNotSet();

  /**
   * @notice sets the transfer limit configurations
   * @param limit TransferLimit
   */
  function _setTransferLimitConfig(TransferLimit memory limit) internal virtual {
    // validate transfer limit config
    require(limit.dstEid > 0, "dstEid must be greater than 0");
    require(limit.singleTransferUpperLimit > limit.singleTransferLowerLimit, "upper limit must be greater than lower limit");
    require(limit.dailyTransferAttemptPerAddress > 0, "dailyTransferAttemptPerAddress must be greater than 0");
    require(limit.maxDailyTransferAmount > limit.singleTransferUpperLimit, "maxDailyTransferAmount must be greater than singleTransferUpperLimit");
    require(limit.dailyTransferAmountPerAddress > limit.singleTransferUpperLimit, "dailyTransferAmountPerAddress must be greater than singleTransferUpperLimit");
    require(limit.maxDailyTransferAmount > limit.dailyTransferAmountPerAddress, "maxDailyTransferAmount must be greater than dailyTransferAmountPerAddress");
    // assign limit to the mapping
    transferLimitConfigs[limit.dstEid] = limit;
    // emit event
    emit TransferLimitChanged(
      limit.dstEid,
      limit.maxDailyTransferAmount,
      limit.singleTransferUpperLimit,
      limit.singleTransferLowerLimit,
      limit.dailyTransferAmountPerAddress,
      limit.dailyTransferAttemptPerAddress
    );
  }

  /**
   * @notice sets multiple transfer limit configurations are once
   * @param _transferLimitConfigs an array of TransferLimit
   */
  function _setTransferLimitConfigs(TransferLimit[] memory _transferLimitConfigs) internal virtual {
    for (uint256 i = 0; i < _transferLimitConfigs.length; i++) {
      TransferLimit memory limit = _transferLimitConfigs[i];
      _setTransferLimitConfig(limit);
    }
  }

  /**
   * @notice check if the transfer amount exceeds the limit
   * @dev reset limit if the last transfer is made more than a calendar day, and then check the limit
   * @param _dstEid destination endpoint id
   * @param _amount transfer amount
   * @param _user user address
   */
  function _checkAndUpdateTransferLimit(uint32 _dstEid, uint256 _amount, address _user) internal virtual {
    TransferLimit memory limit = transferLimitConfigs[_dstEid];
    // check if transfer limit is set
    if (limit.dstEid == 0) {
      revert TransferLimitNotSet();
    }
    // check if amount is greater than 0
    if (_amount == 0) {
      revert TransferLimitExceeded();
    }

    // reset global transfer limit if the last transfer is made more than a calendar day
    if (isMoreThanACalendarDay(lastUpdatedTime[_dstEid], block.timestamp)) {
      dailyTransferAmount[_dstEid] = 0;
    }
    // reset user transfer limit and attempt if the last transfer is made more than a calendar day
    if (isMoreThanACalendarDay(lastUserUpdatedTime[_dstEid][_user], block.timestamp)) {
      userDailyTransferAmount[_dstEid][_user] = 0;
      userDailyAttempt[_dstEid][_user] = 0;
    }

    // check if the transfer amount exceeds the upper and lower limit
    if (_amount > limit.singleTransferUpperLimit || _amount < limit.singleTransferLowerLimit) {
      revert TransferLimitExceeded();
    }

    // check if the transfer amount exceeds the daily transfer amount limit
    if (dailyTransferAmount[_dstEid] + _amount > limit.maxDailyTransferAmount) {
      revert TransferLimitExceeded();
    }

    // check if the transfer amount exceeds the daily transfer amount limit per address
    if (userDailyTransferAmount[_dstEid][_user] + _amount > limit.dailyTransferAmountPerAddress) {
      revert TransferLimitExceeded();
    }

    // check if the user exceeds the daily transfer attempt limit
    if (userDailyAttempt[_dstEid][_user] >= limit.dailyTransferAttemptPerAddress) {
      revert TransferLimitExceeded();
    }
    // update global transfer limit and updated timestamp
    dailyTransferAmount[_dstEid] += _amount;
    lastUpdatedTime[_dstEid] = block.timestamp;
    // update user transfer limit and updated timestamp
    userDailyTransferAmount[_dstEid][_user] += _amount;
    userDailyAttempt[_dstEid][_user] += 1;
    lastUserUpdatedTime[_dstEid][_user] = block.timestamp;
  }



  /**
   * @notice compare two timestamp and check if the difference is more than a calendar day
   * @param timestampA timestamp A
   * @param timestampB timestamp B
   * @return true if the difference is more than a calendar day
   */
  function isMoreThanACalendarDay(uint256 timestampA, uint256 timestampB) internal virtual pure returns (bool) {
    uint256 secondsPerDay = 86400; // 60 * 60 * 24
    uint256 diffInDays = (timestampB - timestampA)/secondsPerDay;
    return diffInDays >= 1;
  }
}
