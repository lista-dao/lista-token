// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVeLista.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
    * @title Distributor
    * @dev Distributor contract for distributing rewards to veLista holders
    */
contract VeListaDistributor is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    event RewardRegistered(address token, uint256 week);
    event DepositReward(uint256 week, TokenAmount[] tokens);
    event Claimed(address account, address token, uint256 amount);

    struct TokenAmount {
        address token;
        uint256 amount;
    }

    struct RewardToken {
        address token;
        uint16 startWeek;
    }

    // week -> tokens and amounts
    TokenAmount[10][65535] public weeklyRewards;
    // token -> reward token index
    mapping(address => uint8) public rewardTokenIndexes;
    // index -> start week
    RewardToken[10] public rewardTokens;
    // account -> token -> week
    mapping(address => mapping(address => uint16)) public accountClaimedWeek;
    IVeLista public veLista; // veLista contract
    bytes32 public constant MANAGER = keccak256("MANAGER"); // manager role
    uint16 public lastDepositWeek; // last deposit week

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev Initialize the contract
      * @param _admin Address of the admin role
      * @param _manager Address of the manager role
      * @param _veLista Address of the veLista contract
      */
    function initialize(address _admin, address _manager, address _veLista) external initializer {
        __AccessControl_init();
        require(_admin != address(0), "Distributor: admin is the zero address");
        require(_manager != address(0), "Distributor: _manager is the zero address");
        require(_veLista != address(0), "Distributor: veLista is the zero address");
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);

        veLista = IVeLista(_veLista);
    }

    /**
      * @dev Register a new token for distribution
      * @param _token Address of the token to register
      */
    function registerNewToken(address _token) external onlyRole(MANAGER) {
        uint8 idx = rewardTokenIndexes[_token];
        require(idx == 0, "token already registered");
        for (idx = 1; idx < rewardTokens.length; ++idx) {
            if (rewardTokens[idx].token == address(0)) {
                break;
            }
        }
        require(idx < rewardTokens.length, "exceeded the maximum number of reward tokens");
        rewardTokens[idx] = RewardToken({
            token: _token,
            startWeek: veLista.getCurrentWeek()
        });
        rewardTokenIndexes[_token] = idx;

        emit RewardRegistered(_token, rewardTokenIndexes[_token]);
    }

    /**
      * @dev Deposit new rewards for a specific week
      * @param _week Week number to deposit rewards for
      * @param _tokens Array of token and amount to deposit
      */
    function depositNewReward(uint16 _week, TokenAmount[] memory _tokens) external onlyRole(MANAGER) {
        require(_tokens.length > 0, "no tokens");
        require(_week > lastDepositWeek, "week must be greater than last deposit week");
        require(_week < veLista.getCurrentWeek(), "week must be less than current week");
        lastDepositWeek = _week;

        for (uint8 i = 0; i < _tokens.length; ++i) {
            uint8 tokenIdx = rewardTokenIndexes[_tokens[i].token];
            uint16 tokenWeek = rewardTokens[tokenIdx].startWeek;
            require(tokenIdx > 0, "token not registered");
            require(_week >= tokenWeek, "deposit week must be greater than token start week");
            require(_tokens[i].amount > 0, "amount must be greater than 0");
            IERC20(_tokens[i].token).safeTransferFrom(msg.sender, address(this), _tokens[i].amount);

            weeklyRewards[_week][tokenIdx] = TokenAmount({
                token: _tokens[i].token,
                amount: _tokens[i].amount
            });
        }

        emit DepositReward(_week, _tokens);
    }

    /**
      * @dev Get claimable rewards for an account
      * @param _account Address of the account to get claimable rewards for
      * @return Array of TokenAmount structs representing claimable rewards
      */
    function getClaimable(address _account) public view returns (TokenAmount[] memory) {
        uint256 currentWeek = veLista.getCurrentWeek();
        TokenAmount[] memory claimableAmount = new TokenAmount[](rewardTokens.length);

        uint256 len;
        for (uint8 i = 1; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i].token;
            if (token == address(0)) {
                break;
            }
            uint16 accountWeek = accountClaimedWeek[_account][token];
            if (accountWeek == 0) {
                accountWeek = rewardTokens[i].startWeek;
            }
            for (uint16 j = accountWeek; j < currentWeek; ++j) {
                TokenAmount memory reward = weeklyRewards[j][i];
                if (reward.amount == 0) {
                    continue;
                }
                uint256 accountWeight = veLista.balanceOfAtWeek(_account, j);
                uint256 totalWeight = veLista.totalSupplyAtWeek(j);
                if (totalWeight == 0) {
                    continue;
                }
                uint256 rewardAmount = reward.amount;
                claimableAmount[i].amount += rewardAmount * accountWeight / totalWeight;
                claimableAmount[i].token = reward.token;
            }
            if (claimableAmount[i].amount > 0) {
                ++len;
            }
        }


        TokenAmount[] memory claimable = new TokenAmount[](len);
        uint256 idx;
        for (uint8 i = 1; i < rewardTokens.length; ++i) {
            if (claimableAmount[i].amount > 0) {
                claimable[idx] = claimableAmount[i];
                ++idx;
            }
        }
        return claimable;
    }

    /**
      * @dev Get claimable rewards for an account for a specific token
      * @param _account Address of the account to get claimable rewards for
      * @param _token Address of the token to get claimable rewards for
      * @return Amount of claimable rewards
      */
    function getTokenClaimable(address _account, address _token) public view returns (uint256) {
        uint256 currentWeek = veLista.getCurrentWeek();
        uint256 claimableAmount;

        uint16 accountWeek = accountClaimedWeek[_account][_token];
        uint8 tokenIdx = rewardTokenIndexes[_token];
        if (tokenIdx == 0) {
            return 0;
        }
        if (accountWeek == 0) {
            accountWeek = rewardTokens[tokenIdx].startWeek;
        }
        for (uint16 j = accountWeek; j < currentWeek; ++j) {
            TokenAmount memory reward = weeklyRewards[j][tokenIdx];
            if (reward.amount == 0) {
                continue;
            }
            uint256 accountWeight = veLista.balanceOfAtWeek(_account, j);
            uint256 totalWeight = veLista.totalSupplyAtWeek(j);
            if (totalWeight == 0) {
                continue;
            }
            uint256 rewardAmount = reward.amount;
            claimableAmount += rewardAmount * accountWeight / totalWeight;
        }
        return claimableAmount;
    }

    /**
      * @dev Claim rewards for an account
      * @param tokens Addresses of the tokens to claim
      */
    function claimAll(address[] memory tokens) external {
        address _account = msg.sender;
        for (uint256 i = 0; i < tokens.length; ++i) {
            claimWithToken(_account, tokens[i]);
        }
    }
    /**
      * @dev Claim rewards for an account for a specific token
      * @param _account Address of the account to claim rewards for
      * @param token Address of the token to claim
      */
    function claimWithToken(address _account, address token) public {
        uint256 tokenIdx = rewardTokenIndexes[token];
        require(tokenIdx > 0, "token not registered");

        uint16 currentWeek = veLista.getCurrentWeek();
        uint16 accountWeek = accountClaimedWeek[_account][token];
        if (accountWeek == 0) {
            accountWeek = rewardTokens[tokenIdx].startWeek;
        }
        require(accountWeek < currentWeek, "no claimable");

        uint256 amount;

        for (; accountWeek < currentWeek; ++accountWeek) {
            TokenAmount memory reward = weeklyRewards[accountWeek][tokenIdx];
            if (reward.amount == 0) {
                continue;
            }
            uint256 accountWeight = veLista.balanceOfAtWeek(_account, accountWeek);
            uint256 totalWeight = veLista.totalSupplyAtWeek(accountWeek);
            if (totalWeight == 0) {
                continue;
            }
            uint256 rewardAmount = reward.amount;

            amount += rewardAmount * accountWeight / totalWeight;
        }
        accountClaimedWeek[msg.sender][token] = accountWeek;

        if (amount > 0) {
            IERC20(token).safeTransfer(_account, amount);
            emit Claimed(_account, token, amount);
        }
    }

    /**
      * @dev Get total reward for a specific week
      * @param _week Week number to get total reward for
      * @return Array of TokenAmount structs representing total reward
      */
    function getTotalRewardByWeek(uint16 _week) external view returns (TokenAmount[] memory) {
        TokenAmount[10] memory rewardData = weeklyRewards[_week];
        uint8 len;
        for (uint8 i = 1; i < rewardTokens.length; ++i) {
            if (rewardTokens[i].token == address(0)) {
                break;
            }
            if (rewardData[i].amount > 0) {
                ++len;
            }
        }
        TokenAmount[] memory reward = new TokenAmount[](len);
        uint8 idx;
        for (uint8 i = 1; i < rewardTokens.length; ++i) {
            if (rewardTokens[i].token == address(0)) {
                break;
            }
            if (rewardData[i].amount > 0) {
                reward[idx] = rewardData[i];
                ++idx;
            }
        }
        return reward;
    }

    /**
      * @dev Get total reward for the last deposit week
      * @return Array of TokenAmount structs representing total reward
      */
    function getLastWeeklyRewards() external view returns (TokenAmount[] memory) {
        TokenAmount[10] memory tokenAmounts = weeklyRewards[lastDepositWeek];
        uint8 len;
        for (uint8 i = 0; i < tokenAmounts.length; ++i) {
            if (tokenAmounts[i].amount > 0) {
                ++len;
            }
        }
        TokenAmount[] memory reward = new TokenAmount[](len);
        uint8 idx;
        for (uint8 i = 0; i < tokenAmounts.length; ++i) {
            if (tokenAmounts[i].amount > 0) {
                reward[idx] = tokenAmounts[i];
                ++idx;
            }
        }
        return reward;
    }

    /**
      * @dev Get account reward for the last deposit week
      * @param _account Address of the account to get rewards for
      * @return rewards Array of TokenAmount structs representing account reward
      */
    function getAccountLastWeeklyRewards(address _account) external view returns (TokenAmount[] memory rewards) {
        uint256 accountWeight = veLista.balanceOfAtWeek(_account, lastDepositWeek);
        if (accountWeight == 0) {
            return rewards;
        }

        uint256 totalWeight = veLista.totalSupplyAtWeek(lastDepositWeek);
        if (totalWeight == 0) {
            return rewards;
        }

        TokenAmount[10] memory tokenAmounts = weeklyRewards[lastDepositWeek];
        uint8 len;
        for (uint8 i = 0; i < tokenAmounts.length; ++i) {
            if (tokenAmounts[i].amount > 0) {
                ++len;
            }
        }
        rewards = new TokenAmount[](len);
        uint8 idx;
        for (uint8 i = 0; i < tokenAmounts.length; ++i) {
            if (tokenAmounts[i].amount > 0) {
                rewards[idx] = tokenAmounts[i];
                rewards[idx].amount = tokenAmounts[i].amount * accountWeight / totalWeight;
                ++idx;
            }
        }
    }

    /**
      * @dev Get reward token start week
      * @param _token Address of the token to get start week for
      * @return Start week of the reward token
      */
    function getRewardTokenStartWeek(address _token) external view returns(uint16) {
        return rewardTokens[rewardTokenIndexes[_token]].startWeek;
    }
}
