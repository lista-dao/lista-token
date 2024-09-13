// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IVeLista} from "./interfaces/IVeLista.sol";

/**
  * @title VeLista
  * @dev lock lista token to get veLista (voting power)
  */
contract VeLista is IVeLista, Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    // account -> account data
    mapping(address => AccountData) public accountData;
    // account -> account history locked data
    mapping(address => LockedData[]) public accountLockedData;

    // week -> total locked weight
    LockedData[65535] public totalLockedData;
    // week -> total unlocked amount
    uint256[65535] public totalUnlockedData;

    uint256 public startTime; // start time
    IERC20 public token; // lista token

    uint256 public totalPenalty; // total penalty
    address public penaltyReceiver; // penalty receiver

    uint16 public constant MAX_LOCK_WEEKS = 52; // max lock weeks
    uint16 private lastUpdateTotalWeek; // last update total week
    uint256 public constant decimals = 18; // decimals
    string public constant name = "Vote-escrowed Lista"; // name
    string public constant symbol = "veLista"; // symbol
    bytes32 public constant MANAGER = keccak256("MANAGER"); // manager role


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev initialize veLista contract
      * @param _admin admin address
      * @param _manager manager address
      * @param _startTime start time
      * @param _token lista token address
      * @param _penaltyReceiver penalty receiver
      */
    function initialize(
        address _admin,
        address _manager,
        uint256 _startTime,
        address _token,
        address _penaltyReceiver
    ) external initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_manager != address(0), "manager is the zero address");
        require(_token != address(0), "lista token is the zero address");
        require(_penaltyReceiver != address(0), "penalty receiver is the zero address");
        require(_startTime < block.timestamp && block.timestamp - _startTime <= 10 weeks, "invalid start time");
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        startTime = _startTime;
        token = IERC20(_token);
        penaltyReceiver = _penaltyReceiver;
    }

    /**
     * @dev get week number by timestamp
     * @param timestamp second timestamp
     * @return week number
     */
    function getWeek(uint256 timestamp) public view returns (uint16) {
        uint256 week = (timestamp - startTime) / 1 weeks;
        if (week <= 65535) {
            return uint16(week);
        }
        revert("exceeds MAX_WEEKS");
    }

    /**
     * @dev get current week number
     * @return week number array of TokenAmount structs which includes token address and amount
     */
    function getCurrentWeek() public view returns (uint16) {
        return getWeek(block.timestamp);
    }

    /**
     * @dev create a new lock to get veLista
     * @param amount amount of token to lock
     * @param week number of weeks to lock
     * @param autoLock auto lock status
     */
    function lock(uint256 amount, uint16 week, bool autoLock) external {
        require(amount >= 1e16, "lock amount must be greater or equal than 0.01");
        address _account = msg.sender;
        require(accountData[_account].locked == 0, "locked amount must be 0");
        _createLock(_account, amount, week, autoLock);
        token.safeTransferFrom(_account, address(this), amount);
    }

    /**
     * @dev relock token without claiming them
     * @param week the number of weeks to extend the lock
     * @param autoLock auto lock status
     */
    function relockUnclaimed(uint16 week, bool autoLock) external {
        address _account = msg.sender;
        require(balanceOf(_account) == 0, "already locked");

        AccountData storage _accountData = accountData[_account];
        require(_accountData.locked > 0 && block.timestamp >= _accountData.lockTimestamp + uint256(_accountData.lockWeeks) * 1 weeks, "no unlock data");
        _createLock(_account, _accountData.locked, week, autoLock);
    }

    // create new lock
    function _createLock(address _account, uint256 _amount, uint16 _week, bool autoLock) private {
        require(_week <= MAX_LOCK_WEEKS, "exceeds MAX_LOCK_WEEKS");
        require(_week > 0, "invalid lock week");

        // write history total weight
        _writeTotalWeight();
        uint16 currentWeek = lastUpdateTotalWeek; // lastUpdateTotalWeek is current week after _writeTotalWeight()

        // update account data
        AccountData storage _accountData = accountData[_account];

        _accountData.locked = _amount;
        _accountData.lastLockWeek = currentWeek;
        _accountData.lockWeeks = _week;
        _accountData.autoLock = autoLock;
        _accountData.lockTimestamp = block.timestamp;

        uint256 weight = _amount * uint256(_week);

        // update account locked data
        LockedData[] storage lockedDataHistory = accountLockedData[_account];
        if (lockedDataHistory.length == 0) {
            lockedDataHistory.push(LockedData({
                week: currentWeek,
                locked: _amount,
                weight: weight,
                autoLockAmount: autoLock ? _amount : 0
            }));
        } else {
            LockedData storage lastAccountLockedData = lockedDataHistory[lockedDataHistory.length - 1];
            if (lastAccountLockedData.week == currentWeek) {
                lastAccountLockedData.locked = _amount;
                lastAccountLockedData.weight = weight;
                lastAccountLockedData.autoLockAmount = autoLock ? _amount : 0;
            } else {
                lockedDataHistory.push(LockedData({
                    week: currentWeek,
                    locked: _amount,
                    weight: weight,
                    autoLockAmount: autoLock ? _amount : 0
                }));
            }
        }

        // update total locked data
        LockedData storage _totalLockedData = totalLockedData[currentWeek];
        _totalLockedData.locked += _amount;
        _totalLockedData.weight += weight;
        if (autoLock) {
            _totalLockedData.autoLockAmount += _amount;
        } else {
            // update total unlocked data
            totalUnlockedData[currentWeek + _week] += _amount;
        }

        emit LockCreated(_account, _amount, _week, autoLock);
    }

    /**
     * @dev increase lock amount
     * @param _amount amount of token to increase
     */
    function increaseAmount(uint256 _amount) external {
        address _account = msg.sender;
        uint256 oldWeight = balanceOf(_account);
        require(oldWeight > 0, "no lock data");
        require(_amount > 0, "invalid amount");

        // transfer lista token
        token.safeTransferFrom(_account, address(this), _amount);
        // write history total weight
        _writeTotalWeight();
        uint16 currentWeek = lastUpdateTotalWeek; // lastUpdateTotalWeek is current week after _writeTotalWeight()

        AccountData storage _accountData = accountData[_account];

        // update account data
        _accountData.locked += _amount;
        _accountData.lockTimestamp = block.timestamp;

        if (!_accountData.autoLock) {
            uint16 remainWeek = _accountData.lastLockWeek + _accountData.lockWeeks - currentWeek;
            _accountData.lastLockWeek = currentWeek;
            _accountData.lockWeeks = remainWeek;
        }

        uint256 newWeight = _accountData.locked * uint256(_accountData.lockWeeks);

        // update account locked data
        LockedData[] storage lockedDataHistory = accountLockedData[_account];
        LockedData storage lastAccountLockedData = lockedDataHistory[lockedDataHistory.length - 1];
        if (lastAccountLockedData.week == currentWeek) {
            lastAccountLockedData.locked = _accountData.locked;
            lastAccountLockedData.weight = newWeight;
            lastAccountLockedData.autoLockAmount = _accountData.autoLock ? _accountData.locked : 0;
        } else {
            lockedDataHistory.push(LockedData({
                week: currentWeek,
                locked: _accountData.locked,
                weight: newWeight,
                autoLockAmount: _accountData.autoLock ? _accountData.locked : 0
            }));
        }

        // update total locked data
        LockedData storage _totalLockedData = totalLockedData[currentWeek];
        _totalLockedData.locked += _amount;
        _totalLockedData.weight += newWeight - oldWeight;
        if (_accountData.autoLock) {
            _totalLockedData.autoLockAmount += _amount;
        } else {
            // update total unlocked data
            totalUnlockedData[currentWeek + _accountData.lockWeeks] += _amount;
        }

        emit LockAmountIncreased(_account, _amount);
    }

    /**
     * @dev extend number of weeks to lock
     * @param _week number of weeks to increase of the lock
     */
    function extendWeek(uint16 _week) external {
        require(_week > 0, "invalid lock week");
        require(_week <= MAX_LOCK_WEEKS, "exceeds MAX_LOCK_WEEKS");
        address _account = msg.sender;
        uint256 oldWeight = balanceOf(_account);
        require(oldWeight > 0, "no lock data");

        // write history total weight
        _writeTotalWeight();
        uint16 currentWeek = lastUpdateTotalWeek; // lastUpdateTotalWeek is current week after _writeTotalWeight()

        // update account data
        AccountData storage _accountData = accountData[_account];
        _accountData.lockTimestamp = block.timestamp;

        uint16 oldUnlockWeek = _accountData.lastLockWeek + _accountData.lockWeeks;

        uint16 addWeek;
        if (_accountData.autoLock) {
            require(_week > _accountData.lockWeeks, "invalid lock week");
            addWeek = _week - _accountData.lockWeeks;
            _accountData.lockWeeks = _week;
        } else {
            uint16 remainWeek = _accountData.lastLockWeek + _accountData.lockWeeks - currentWeek;
            require(_week > remainWeek, "invalid lock week");
            addWeek = _week - remainWeek;
            _accountData.lastLockWeek = currentWeek;
            _accountData.lockWeeks = _week;
        }

        // update account locked data
        LockedData[] storage lockedDataHistory = accountLockedData[_account];
        LockedData storage lastAccountLockedData = lockedDataHistory[lockedDataHistory.length - 1];
        if (lastAccountLockedData.week == currentWeek) {
            lastAccountLockedData.weight = _accountData.locked * uint256(_accountData.lockWeeks);
        } else {
            lockedDataHistory.push(LockedData({
                week: currentWeek,
                locked: _accountData.locked,
                weight: _accountData.locked * uint256(_accountData.lockWeeks),
                autoLockAmount: _accountData.autoLock ? _accountData.locked : 0
            }));
        }

        // update total locked data
        LockedData storage _totalLockedData = totalLockedData[currentWeek];
        _totalLockedData.weight += _accountData.locked * uint256(addWeek);


        // update total unlocked data
        if (!_accountData.autoLock) {
            totalUnlockedData[oldUnlockWeek] -= _accountData.locked;
            totalUnlockedData[_accountData.lastLockWeek + _accountData.lockWeeks] += _accountData.locked;
        }

        emit LockWeekExtended(_account, _week);
    }

    /**
     * @dev get veLista balance of account (aka user's Voting Power or Weight)
     * @param account account address
     * @return veLista balance of account
     */
    function balanceOf(address account) public view returns (uint256) {
        AccountData memory _accountData = accountData[account];
        if (_accountData.autoLock) {
            return _accountData.locked * uint256(_accountData.lockWeeks);
        } else {
            uint16 currentWeek = getCurrentWeek();
            uint256 unlockWeek = _accountData.lastLockWeek + _accountData.lockWeeks;
            if (unlockWeek > currentWeek) {
                return uint256(unlockWeek - currentWeek) * _accountData.locked;
            }
            return 0;
        }
    }

    /**
     * @dev get veLista balance of account at time
     * @param account account address
     * @param timestamp timestamp in second
     * @return veLista balance of the account
     */
    function balanceOfAtTime(address account, uint256 timestamp) public view returns (uint256) {
        return _balanceOfAtWeek(account, getWeek(timestamp));
    }

    /**
     * @dev get veLista balance of account at week
     * @param account account address
     * @param week week number
     * @return veLista balance of account
     */
    function balanceOfAtWeek(address account, uint16 week) public view returns (uint256) {
        return _balanceOfAtWeek(account, week);
    }

    // get veLista balance of account at week
    function _balanceOfAtWeek(address account, uint16 week) private view returns (uint256) {
        LockedData[] memory lockedData = accountLockedData[account];
        if (lockedData.length == 0) {
            return 0;
        }
        uint256 min = 0;
        uint256 max = lockedData.length - 1;
        uint256 result = type(uint256).max;
        uint8 i = 0;
        for (; i < 16 && min <= max; i++) {
            uint256 mid = (min + max) / 2;
            if (lockedData[mid].week == week) {
                result = mid;
                break;
            } else if (lockedData[mid].week < week) {
                result = mid;
                min = mid + 1;
            } else {
                if (mid == 0) {
                    break;
                }
                max = mid - 1;
            }
        }
        if (i >= 16) {
            revert("array overflow");
        }

        if (result == type(uint256).max) {
            return 0;
        }

        LockedData memory locked = lockedData[result];

        if (locked.week > week) {
            return 0;
        } else if (locked.week == week) {
            return locked.weight;
        } else {
            if (locked.autoLockAmount > 0) {
                return locked.weight;
            }

            uint256 decay = locked.locked * uint256(week - locked.week);
            if (locked.weight < decay) {
                return 0;
            }
            return locked.weight - decay;
        }

    }

    /**
     * @notice All lock/claim/extend functions must call this function before updating the locked data.
     * @dev This function updates the historical record of the total locked weight up to the current week.
            This ensures that the contract maintains an accurate history of locked token data,
            which is crucial for calculating voting power (veLista) and other token metrics over time.
     */
    function _writeTotalWeight() private {
        uint16 currentWeek = getCurrentWeek();

        uint16 updateWeek = lastUpdateTotalWeek;
        if (updateWeek == currentWeek) {
            return;
        }


        LockedData storage lastTotalLockedData = totalLockedData[updateWeek];
        uint256 locked = lastTotalLockedData.locked;
        uint256 weight = lastTotalLockedData.weight;
        uint256 autoLock = lastTotalLockedData.autoLockAmount;
        uint256 decay = locked - autoLock;

        while(updateWeek < currentWeek) {
            ++updateWeek;
            weight -= decay;
            uint256 unlocked = totalUnlockedData[updateWeek];
            if (unlocked > 0) {
                decay -= unlocked;
                locked -= unlocked;
            }
            totalLockedData[updateWeek].week= updateWeek;
            totalLockedData[updateWeek].weight = weight;
            totalLockedData[updateWeek].autoLockAmount = autoLock;
            totalLockedData[updateWeek].locked = locked;
        }

        lastUpdateTotalWeek = currentWeek;
    }

    /**
     * @dev get veLista's total supply
     * @return total supply of veLista
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupplyAtWeek(getCurrentWeek());
    }

    /**
     * @dev get veLista's total supply at week
     * @param week week number
     * @return total supply of veLista
     */
    function totalSupplyAtWeek(uint16 week) public view returns (uint256) {
        return _totalSupplyAtWeek(week);
    }

    /**
     * @dev get total supply at time
     * @param timestamp second timestamp
     * @return total supply of veLista
     */
    function totalSupplyAtTime(uint256 timestamp) public view returns (uint256) {
        return _totalSupplyAtWeek(getWeek(timestamp));
    }

    // get total supply at week
    function _totalSupplyAtWeek(uint16 week) private view returns (uint256) {
        if (lastUpdateTotalWeek >= week) {
            return totalLockedData[week].weight;
        }

        LockedData memory lastTotalLockedData = totalLockedData[lastUpdateTotalWeek];
        uint256 locked = lastTotalLockedData.locked;
        uint256 weight = lastTotalLockedData.weight;
        uint256 autoLock = lastTotalLockedData.autoLockAmount;
        uint256 decay = locked - autoLock;

        uint256 updateWeek = lastUpdateTotalWeek;
        while(updateWeek < week) {
            ++updateWeek;
            weight -= decay;
            uint256 unlocked = totalUnlockedData[updateWeek];
            if (unlocked > 0) {
                decay -= unlocked;
            }
        }

        return weight;
    }

    /**
     * @dev Claim tokens when the lock period is over
     * @return claimed amount
     */
    function claim() external returns (uint256) {
        address _account = msg.sender;
        AccountData storage _accountData = accountData[_account];
        require(!_accountData.autoLock && block.timestamp >= _accountData.lockTimestamp + uint256(_accountData.lockWeeks) * 1 weeks, "no claimable tokens");

        _writeTotalWeight();

        uint256 amount = _accountData.locked;
        _accountData.locked = 0;
        _accountData.lastLockWeek = 0;
        _accountData.lockWeeks = 0;
        _accountData.lockTimestamp = 0;

        require(amount > 0, "invalid claimed amount");

        token.safeTransfer(_account, amount);


        emit Claimed(_account, amount);
        return amount;
    }

    /**
     * @dev claim tokens even if the lock is still ongoing, resulting in a penalty
     * @return claimed amount after penalty
     */
    function earlyClaim() external returns (uint256) {
        address _account = msg.sender;
        AccountData storage _accountData = accountData[_account];
        uint256 weight = balanceOf(_account);
        uint256 locked = _accountData.locked;
        uint16 unlockWeek = _accountData.lastLockWeek + _accountData.lockWeeks;
        bool autoLock = _accountData.autoLock;

        require(_accountData.autoLock || block.timestamp < _accountData.lockTimestamp + uint256(_accountData.lockWeeks) * 1 weeks, "cannot claim with penalty");
        _writeTotalWeight();
        uint16 currentWeek = lastUpdateTotalWeek; // lastUpdateTotalWeek is current week after _writeTotalWeight()

        uint256 penalty;
        if (!autoLock) {
            uint16 remainWeek = _accountData.lastLockWeek + _accountData.lockWeeks - currentWeek;
            if (remainWeek == 0) {
                remainWeek = 1;
            }
            penalty = _accountData.locked * uint256(remainWeek) / uint256(MAX_LOCK_WEEKS);
        } else {
            penalty = _accountData.locked * uint256(_accountData.lockWeeks) / uint256(MAX_LOCK_WEEKS);
        }
        totalPenalty += penalty;

        uint256 amount = _accountData.locked - penalty;

        // update account data
        _accountData.locked = 0;
        _accountData.autoLock = false;
        _accountData.lastLockWeek = 0;
        _accountData.lockWeeks = 0;
        _accountData.lockTimestamp = 0;

        // update account locked data
        LockedData[] storage lockedDataHistory = accountLockedData[_account];
        LockedData storage lastAccountLockedData = lockedDataHistory[lockedDataHistory.length - 1];
        if (lastAccountLockedData.week == currentWeek) {
            lastAccountLockedData.locked = 0;
            lastAccountLockedData.weight = 0;
            lastAccountLockedData.autoLockAmount = 0;
        } else {
            lockedDataHistory.push(LockedData({
                week: currentWeek,
                locked: 0,
                weight: 0,
                autoLockAmount: 0
            }));
        }

        // The weight is 0, which means it's unlocked week but the claim time has not yet arrived. In this case, the data has been updated in _writeTotalWeight.
        if (weight > 0) {
            // update total locked data
            LockedData storage _totalLockedData = totalLockedData[currentWeek];
            _totalLockedData.locked -= locked;
            _totalLockedData.weight -= weight;
            if (autoLock) {
                _totalLockedData.autoLockAmount -= locked;
            }

            // update total unlocked data
            totalUnlockedData[currentWeek] += locked;
            if (!autoLock) {
                totalUnlockedData[unlockWeek] -= locked;
            }
        }


        if (amount > 0) {
            token.safeTransfer(_account, amount);
        }

        emit EarlyClaimed(_account, amount, penalty);
        return amount;
    }

    /**
     * @dev enable auto lock
     */
    function enableAutoLock() external {
        address _account = msg.sender;
        AccountData storage _accountData = accountData[_account];
        require(balanceOf(_account) > 0, "no lock data");
        require(!_accountData.autoLock, "already auto lock");
        _writeTotalWeight();
        uint16 currentWeek = lastUpdateTotalWeek; // lastUpdateTotalWeek is current week after _writeTotalWeight()
        uint16 unlockWeek = _accountData.lastLockWeek + _accountData.lockWeeks;
        uint16 remainWeek = unlockWeek - currentWeek;

        // update account data
        _accountData.autoLock = true;
        _accountData.lastLockWeek = currentWeek;
        _accountData.lockTimestamp = block.timestamp;
        _accountData.lockWeeks = remainWeek;

        // update account locked data
        LockedData[] storage lockedDataHistory = accountLockedData[_account];
        LockedData storage lastAccountLockedData = lockedDataHistory[lockedDataHistory.length - 1];
        if (lastAccountLockedData.week == currentWeek) {
            lastAccountLockedData.autoLockAmount = _accountData.locked;
        } else {
            lockedDataHistory.push(LockedData({
                week: currentWeek,
                locked: _accountData.locked,
                weight: _accountData.locked * uint256(_accountData.lockWeeks),
                autoLockAmount: _accountData.locked
            }));
        }

        // update total locked data
        LockedData storage _totalLockedData = totalLockedData[currentWeek];
        _totalLockedData.autoLockAmount += _accountData.locked;

        // update total unlocked data
        totalUnlockedData[unlockWeek] -= _accountData.locked;

        emit EnableAutoLock(_account);
    }

    /**
     * @dev disable auto lock
     */
    function disableAutoLock() external {
        address _account = msg.sender;
        AccountData storage _accountData = accountData[_account];
        require(_accountData.locked > 0 && _accountData.autoLock, "no lock data");

        _writeTotalWeight();
        uint16 currentWeek = lastUpdateTotalWeek; // lastUpdateTotalWeek is current week after _writeTotalWeight()

        // update account data
        _accountData.autoLock = false;
        _accountData.lastLockWeek = currentWeek;
        _accountData.lockTimestamp = block.timestamp;

        // update account locked data
        LockedData[] storage lockedDataHistory = accountLockedData[_account];
        LockedData storage lastAccountLockedData = lockedDataHistory[lockedDataHistory.length - 1];
        if (lastAccountLockedData.week == currentWeek) {
            lastAccountLockedData.autoLockAmount = 0;
        } else {
            lockedDataHistory.push(LockedData({
                week: currentWeek,
                locked: _accountData.locked,
                weight: _accountData.locked * uint256(_accountData.lockWeeks),
                autoLockAmount: 0
            }));
        }

        // update total locked data
        LockedData storage _totalLockedData = totalLockedData[currentWeek];
        _totalLockedData.autoLockAmount -= _accountData.locked;

        // update total unlocked data
        totalUnlockedData[currentWeek + _accountData.lockWeeks] += _accountData.locked;

        emit DisableAutoLock(_account);
    }

    /**
     * @dev get locked data of account
     * @param account account address
     * @return locked data of the account
     */
    function getLockedData(address account) external view returns (AccountData memory) {
        return accountData[account];
    }

    /**
     * @dev claim penalty collected from early claim, only manager can call this function
     */
    function claimPenalty() external onlyRole(MANAGER) {
        require(totalPenalty > 0, "no penalty");
        uint256 amount = totalPenalty;
        totalPenalty = 0;
        token.safeTransfer(penaltyReceiver, amount);
        emit PenaltyClaimed(penaltyReceiver, amount);
    }

    /**
     * @dev get penalty of the account
     * @param _account account address
     * @return penalty of account
     */
    function getPenalty(address _account) external view returns (uint256) {
        uint16 currentWeek = getCurrentWeek();
        AccountData memory _accountData = accountData[_account];

        if (!_accountData.autoLock && block.timestamp >= _accountData.lockTimestamp + uint256(_accountData.lockWeeks) * 1 weeks) {
            return 0;
        }

        uint256 penalty;
        if (!_accountData.autoLock) {
            uint16 remainWeek = _accountData.lastLockWeek + _accountData.lockWeeks - currentWeek;
            if (remainWeek == 0) {
                remainWeek = 1;
            }
            penalty = _accountData.locked * uint256(remainWeek) / uint256(MAX_LOCK_WEEKS);
        } else {
            penalty = _accountData.locked * uint256(_accountData.lockWeeks) / uint256(MAX_LOCK_WEEKS);
        }
        return penalty;
    }

    /**
     * @dev get total locked data at week
     * @param week week number
     * @return total locked data
     */
    function getTotalLockedAtWeek(uint16 week) external view returns (uint256) {
        if (lastUpdateTotalWeek >= week) {
            return totalLockedData[week].locked;
        }
        LockedData memory lastTotalLockedData = totalLockedData[lastUpdateTotalWeek];
        uint256 locked = lastTotalLockedData.locked;

        uint256 updateWeek = lastUpdateTotalWeek;
        while(updateWeek < week) {
            ++updateWeek;
            uint256 unlocked = totalUnlockedData[updateWeek];
            if (unlocked > 0) {
                locked -= unlocked;
            }
        }
        return locked;
    }
}
