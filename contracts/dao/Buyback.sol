// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../library/RevertReasonParser.sol";
import "./interfaces/IBuyback.sol";

contract Buyback is
  IBuyback,
  Initializable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // bot role
  bytes32 public constant BOT = keccak256("BOT");

  uint256 internal constant DAY = 1 days;

  bytes4 public constant SWAP_FUNCTION_SELECTOR = bytes4(keccak256("swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)"));


  /* ============ State Variables ============ */
  // 1Inch router whitelist
  mapping(address => bool) public oneInchRouterWhitelist;
  // swap input token whitelist
  mapping(address => bool) public tokenInWhitelist;
  // swap output token
  address public tokenOut;
  // buyback receiver address
  address public receiver;
  // daily Bought
  mapping(uint256 => uint256) public dailyBought;

  /* ============ Events ============ */
  event BoughtBack(
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );
  event ReceiverChanged(address indexed receiver);
  event OneInchRouterChanged(address indexed oneInchRouter, bool added);
  event TokenInChanged(address indexed token, bool added);
  event EmergencyWithdraw(address token, uint256 amount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _manager - Address of the manager
   * @param _pauser - Address of the pauser
   * @param _bot - Address of the bot
   * @param _1InchRouter - Address of swap 1Inch router
   * @param _tokenIns - Array of the swap input tokens
   * @param _tokenOut - Address of the swap output token
   * @param _receiver - Address of the receiver
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    address _bot,
    address _1InchRouter,
    address[] memory _tokenIns,
    address _tokenOut,
    address _receiver
  ) external initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_manager != address(0), "Invalid _manager address");
    require(_pauser != address(0), "Invalid pauser address");
    require(_bot != address(0), "Invalid bot address");
    require(_1InchRouter != address(0), "Invalid 1Inch router address");
    // check swap in tokens
    for (uint256 i = 0; i < _tokenIns.length; ++i) {
      require(_tokenIns[i] != address(0), "Invalid swap input token address");
      tokenInWhitelist[_tokenIns[i]] = true;
    }
    require(_tokenOut != address(0), "Invalid swap output token address");
    require(_receiver != address(0), "Invalid receiver address");

    __Pausable_init();
    __ReentrancyGuard_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);
    _grantRole(BOT, _bot);

    oneInchRouterWhitelist[_1InchRouter] = true;
    tokenOut = _tokenOut;
    receiver = _receiver;
  }

  // /* ============ External Functions ============ */

  /**
   * @dev buyback
   * @param _1inchRouter - 1inch router
   * @param _data - 1inch swap data
   */
  function buyback(
    address _1inchRouter,
    bytes calldata _data
  ) external override onlyRole(BOT) nonReentrant whenNotPaused {
    require(
      oneInchRouterWhitelist[_1inchRouter],
      "invalid 1Inch router"
    );
    require(bytes4(_data[0:4]) == SWAP_FUNCTION_SELECTOR, "invalid 1Inch function selector");

    (, SwapDescription memory swapDesc, ) = abi.decode(
      _data[4:],
      (address, SwapDescription, bytes)
    );
    require(
      tokenInWhitelist[address(swapDesc.srcToken)],
      "invalid swap input token"
    );
    require(address(swapDesc.dstToken) == tokenOut, "invalid swap output token");
    require(address(swapDesc.dstReceiver) == receiver, "invalid receiver");
    require(swapDesc.amount > 0, "invalid swap input amount");
    require(
      swapDesc.srcToken.balanceOf(address(this)) >= swapDesc.amount,
      "insufficient balance of swap input token"
    );

    swapDesc.srcToken.approve(_1inchRouter, swapDesc.amount);
    uint256 beforeBalance = swapDesc.dstToken.balanceOf(receiver);
    (bool success, bytes memory result) = _1inchRouter.call(_data);
    if (!success) {
      revert(RevertReasonParser.parse(result, "1inch call failed: "));
    }
    uint256 afterBalance = swapDesc.dstToken.balanceOf(receiver);
    uint256 diff = afterBalance - beforeBalance;
    (uint256 amountOut, ) = abi.decode(result, (uint256, uint256));
    require(amountOut == diff && amountOut >= swapDesc.minReturnAmount, "invalid swap output amount");

    uint256 today = (block.timestamp / DAY) * DAY;
    dailyBought[today] = dailyBought[today] + amountOut;

    emit BoughtBack(
      address(swapDesc.srcToken),
      address(swapDesc.dstToken),
      swapDesc.amount,
      amountOut
    );
  }

  /**
   * @dev change receiver
   * @param _receiver - Address of the receiver
   */
  function changeReceiver(address _receiver) external onlyRole(MANAGER) {
    require(_receiver != address(0), "receiver is the zero address");
    require(_receiver != receiver, "receiver is the same");

    receiver = _receiver;
    emit ReceiverChanged(_receiver);
  }

  /**
   * @dev add 1Inch router to whitelist
   * @param _1InchRouter - Address of the 1Inch router
   */
  function add1InchRouterWhitelist(
    address _1InchRouter
  ) external onlyRole(MANAGER) {
    require(_1InchRouter != address(0), "1Inch router is the zero address");
    require(
      !oneInchRouterWhitelist[_1InchRouter],
      "1Inch router has been whitelisted"
    );

    oneInchRouterWhitelist[_1InchRouter] = true;
    emit OneInchRouterChanged(_1InchRouter, true);
  }

  /**
   * @dev remove 1Inch router from whitelist
   * @param _1InchRouter - Address of the 1Inch router
   */
  function remove1InchRouterWhitelist(
    address _1InchRouter
  ) external onlyRole(MANAGER) {
    require(
      oneInchRouterWhitelist[_1InchRouter],
      "1Inch router is not in whitelist"
    );

    delete oneInchRouterWhitelist[_1InchRouter];
    emit OneInchRouterChanged(_1InchRouter, false);
  }

  /**
   * @dev add token to swap input token whitelist
   * @param _tokenIn - Address of the swap input token
   */
  function addTokenInWhitelist(
    address _tokenIn
  ) external onlyRole(MANAGER) {
    require(_tokenIn != address(0), "the token is the zero address");
    require(!tokenInWhitelist[_tokenIn], "the token has been whitelisted");

    tokenInWhitelist[_tokenIn] = true;
    emit TokenInChanged(_tokenIn, true);
  }

  /**
   * @dev remove token from swap input token whitelist
   * @param _tokenIn - Address of the swap input token
   */
  function removeTokenInWhitelist(
    address _tokenIn
  ) external onlyRole(MANAGER) {
    require(tokenInWhitelist[_tokenIn], "the token is not in whitelist");

    delete tokenInWhitelist[_tokenIn];
    emit TokenInChanged(_tokenIn, false);
  }

  /**
   * @dev allows admin to withdraw tokens for emergency or recover any other mistaken ERC20 tokens.
      * @param _token ERC20 token address
      * @param _amount token amount
      */
  function emergencyWithdraw(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    IERC20(_token).safeTransfer(msg.sender, _amount);
    emit EmergencyWithdraw(_token, _amount);
  }

  /**
   * @dev Flips the pause state
   */
  function togglePause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    paused() ? _unpause() : _pause();
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  // /* ============ Internal Functions ============ */

  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
