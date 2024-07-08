// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVeLista.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
  * @title VeListaDistributor
  * @dev VeListaDistributor contract for distributing rewards to veLista holders
  */
contract VeListaDistributor is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    event RewardRegistered(address token, uint256 week);
    event DepositReward(uint256 week, TokenAmount[] tokens);
    event Claimed(address account, address token, uint256 amount);
    event RecoveredERC20(address token, uint256 amount);

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
      * @dev initialize the contract
      * @param _admin address of the admin role
      * @param _manager address of the manager role
      * @param _veLista address of the veLista contract
      */
    function initialize(address _admin, address _manager, address _veLista) external initializer {
        __AccessControl_init();
        require(_admin != address(0), "admin is a zero address");
        require(_manager != address(0), "manager is a zero address");
        require(_veLista != address(0), "veLista is a zero address");
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);

        veLista = IVeLista(_veLista);
    }

    /**
      * @dev register a new token for distribution
      * @param _token address of the token to register
      */
    function registerNewToken(address _token) external onlyRole(MANAGER) {
        uint8 idx = rewardTokenIndexes[_token];
        require(_token != address(0), "token is a zero address");
        require(idx == 0, "token already registered");

        uint256 rewardTokensLength = rewardTokens.length;
        for (idx = 1; idx < rewardTokensLength; ++idx) {
            if (rewardTokens[idx].token == address(0)) {
                rewardTokens[idx] = RewardToken({
                    token: _token,
                    startWeek: veLista.getCurrentWeek()
                });
                rewardTokenIndexes[_token] = idx;

                emit RewardRegistered(_token, rewardTokens[idx].startWeek);
                return;
            }
        }
        revert("exceeded the maximum number of reward tokens");
    }

    /**
      * @dev deposit new rewards for a specific week
      * @param _week week number of rewards to deposit
      * @param _tokens array of token and amount to deposit
      */
    function depositNewReward(uint16 _week, TokenAmount[] memory _tokens) external onlyRole(MANAGER) {
        require(_tokens.length > 0, "no tokens");
        require(_week >= lastDepositWeek, "_week must be greater than or equal to last deposit week");
        require(_week < veLista.getCurrentWeek(), "_week must be less than current week");
        require(veLista.totalSupplyAtWeek(_week) > 0, "no veLista holders");

        lastDepositWeek = _week;

        for (uint8 i = 0; i < _tokens.length; ++i) {
            uint8 tokenIdx = rewardTokenIndexes[_tokens[i].token];
            uint16 tokenWeek = rewardTokens[tokenIdx].startWeek;
            require(tokenIdx > 0, "token not registered");
            require(_week >= tokenWeek, "_week must be greater than or equal to token start week");
            require(_tokens[i].amount > 0, "amount must be greater than 0");
            require(weeklyRewards[_week][tokenIdx].amount == 0, "reward already deposited");

            weeklyRewards[_week][tokenIdx] = TokenAmount({
                token: _tokens[i].token,
                amount: _tokens[i].amount
            });
            IERC20(_tokens[i].token).safeTransferFrom(msg.sender, address(this), _tokens[i].amount);
        }

        emit DepositReward(_week, _tokens);
    }

    /**
      * @dev get user's claimable rewards
      * @param _account address for receiving rewards
      * @param toWeek the week no. counting from the user's latest claimable week no.
      * @return array of claimable rewards including token address and amount
      */
    function getClaimable(address _account, uint16 toWeek) public view returns (TokenAmount[] memory) {
        uint256 currentWeek = veLista.getCurrentWeek();
        require(toWeek < currentWeek, "toWeek must be less than the current week");
        TokenAmount[] memory claimableAmount = new TokenAmount[](rewardTokens.length);

        uint256 rewardTokensLength = rewardTokens.length;

        uint256 len;
        for (uint8 i = 1; i < rewardTokensLength; ++i) {
            address token = rewardTokens[i].token;
            if (token == address(0)) {
                break;
            }
            uint16 accountWeek = accountClaimedWeek[_account][token];
            if (accountWeek == 0) {
                accountWeek = rewardTokens[i].startWeek;
            }
            (uint256 rewardAmount,) = getTokenClaimable(_account, token, toWeek);
            if (rewardAmount > 0) {
                claimableAmount[i].amount = rewardAmount;
                claimableAmount[i].token = token;
                ++len;
            }
        }

        TokenAmount[] memory claimable = new TokenAmount[](len);
        uint256 idx;
        for (uint8 i = 1; i < rewardTokensLength; ++i) {
            if (claimableAmount[i].amount > 0) {
                claimable[idx] = claimableAmount[i];
                ++idx;
            }
        }
        return claimable;
    }

    /**
      * @dev Get user's claimable amount of a token
      * @param _account address for receiving rewards
      * @param _token the reward token address
      * @param toWeek the week no. counting from the user's latest claimable week no.
      * @return amount of claimable rewards and the last
      * @return last claimable week and the latest claimable week
      */
    function getTokenClaimable(address _account, address _token, uint16 toWeek) public view returns (uint256, uint16) {
        uint256 currentWeek = veLista.getCurrentWeek();
        require(toWeek < currentWeek, "toWeek must be less than the current week");
        uint256 claimableAmount;

        uint16 accountWeek = accountClaimedWeek[_account][_token];
        uint16 lastClaimableWeek = accountWeek;
        uint8 tokenIdx = rewardTokenIndexes[_token];
        if (tokenIdx == 0) {
            return (0, 0);
        }
        if (accountWeek == 0) {
            accountWeek = rewardTokens[tokenIdx].startWeek;
        }
        for (uint16 j = accountWeek; j <= toWeek; ++j) {
            TokenAmount memory reward = weeklyRewards[j][tokenIdx];
            if (reward.amount == 0) {
                continue;
            }
            lastClaimableWeek = j+1;
            uint256 accountWeight = veLista.balanceOfAtWeek(_account, j);
            uint256 totalWeight = veLista.totalSupplyAtWeek(j);
            if (totalWeight == 0) {
                continue;
            }
            uint256 rewardAmount = reward.amount;
            claimableAmount += rewardAmount * accountWeight * 1e18 / totalWeight;
        }
        return (claimableAmount / 1e18, lastClaimableWeek);
    }

    /**
      * @dev claim rewards for an account
      * @param tokens addresses of the tokens to claim
      * @param toWeek the week no. counting from the user's latest claimable week no.
      */
    function claimAll(address[] memory tokens, uint16 toWeek) external {
        address _account = msg.sender;
        uint256 tokenLength = tokens.length;
        for (uint256 i = 0; i < tokenLength; ++i) {
            _claimWithToken(_account, tokens[i], toWeek);
        }
    }
    /**
      * @dev Claim rewards for a specific token on behalf of an account
      * @param token address of the claim
      * @param toWeek the week no. counting from the user's latest claimable week no.
      */
    function claimWithToken(address token, uint16 toWeek) external {
        _claimWithToken(msg.sender, token, toWeek);
    }

    function _claimWithToken(address _account, address token, uint16 toWeek) private {
        uint16 currentWeek = veLista.getCurrentWeek();
        require(toWeek < currentWeek, "toWeek must be less than the current week");

        uint256 tokenIdx = rewardTokenIndexes[token];
        require(tokenIdx > 0, "token not registered");

        uint16 accountWeek = accountClaimedWeek[_account][token];
        if (accountWeek == 0) {
            accountWeek = rewardTokens[tokenIdx].startWeek;
        }
        require(accountWeek < currentWeek, "no claimable rewards");


        (uint256 rewardAmount, uint16 lastClaimableWeek) = getTokenClaimable(_account, token, toWeek);

        accountClaimedWeek[_account][token] = lastClaimableWeek;
        if (rewardAmount > 0) {
            IERC20(token).safeTransfer(_account, rewardAmount);
            emit Claimed(_account, token, rewardAmount);
        }
    }

    /**
      * @dev get total rewards of a specific week
      * @param _week the week number of total rewards to get
      * @return rewards array of TokenAmount structs which includes token address and amount
      */
    function getTotalWeeklyRewards(uint16 _week) external view returns (TokenAmount[] memory rewards) {
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
        rewards = new TokenAmount[](len);
        uint8 idx;
        for (uint8 i = 1; i < rewardTokens.length; ++i) {
            if (rewardTokens[i].token == address(0)) {
                break;
            }
            if (rewardData[i].amount > 0) {
                rewards[idx] = rewardData[i];
                ++idx;
            }
        }
        return rewards;
    }

    /**
      * @dev get user's total rewards of a specific week
      * @param _account address to receiving rewards
      * @param _week the week number of rewards to get per user
      * @return rewards array of TokenAmount structs which includes token address and amount
      */
    function getAccountWeeklyRewards(address _account, uint16 _week) external view returns (TokenAmount[] memory rewards) {
        uint256 accountWeight = veLista.balanceOfAtWeek(_account, _week);
        if (accountWeight == 0) {
            return rewards;
        }

        uint256 totalWeight = veLista.totalSupplyAtWeek(_week);
        if (totalWeight == 0) {
            return rewards;
        }

        TokenAmount[10] memory tokenAmounts = weeklyRewards[_week];
        uint8 len;
        for (uint8 i = 1; i < tokenAmounts.length; ++i) {
            if (tokenAmounts[i].amount > 0) {
                ++len;
            }
        }
        rewards = new TokenAmount[](len);
        uint8 idx;
        for (uint8 i = 1; i < tokenAmounts.length; ++i) {
            if (tokenAmounts[i].amount > 0) {
                rewards[idx] = tokenAmounts[i];
                rewards[idx].amount = tokenAmounts[i].amount * accountWeight / totalWeight;
                ++idx;
            }
        }
    }

    /**
     * @dev recover ERC20 token added to support recovering mistaken rewards
      * @param token ERC20 token address
      * @param amount token amount
      */
    function recoverERC20(address token, uint256 amount) external onlyRole(MANAGER) {
        // Only the owner address can ever receive the recovery withdrawal
        IERC20(token).safeTransfer(msg.sender, amount);
        emit RecoveredERC20(token, amount);
    }

}
