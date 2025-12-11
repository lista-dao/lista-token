// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./library/RevertReasonParser.sol";
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

  bytes4 public constant SWAP_FUNCTION_SELECTOR =
    bytes4(keccak256("swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)"));

  address public constant SWAP_NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  /* ============ State Variables ============ */
  // swap router whitelist
  mapping(address => bool) public routerWhitelist;
  // swap input token whitelist
  mapping(address => bool) public tokenInWhitelist;
  // swap output token
  address public tokenOut;
  // buyback receiver address
  address public receiver;
  // daily Bought
  mapping(uint256 => uint256) public dailyBought;

  /* ============ Events ============ */
  event BoughtBack(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
  event BoughtBack(
    address indexed pair,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );
  event BoughtBack(
    address indexed pair,
    address  spender,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );
  event ReceiverChanged(address indexed receiver);
  event RouterChanged(address indexed router, bool added);
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
    require(_manager != address(0), "Invalid manager address");
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

    routerWhitelist[_1InchRouter] = true;
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
    require(routerWhitelist[_1inchRouter], "router not whitelisted");
    require(bytes4(_data[0:4]) == SWAP_FUNCTION_SELECTOR, "Invalid 1Inch function selector");

    (, SwapDescription memory swapDesc, ) = abi.decode(_data[4:], (address, SwapDescription, bytes));
    require(tokenInWhitelist[address(swapDesc.srcToken)], "Invalid swap input token");
    require(address(swapDesc.dstToken) == tokenOut, "Invalid swap output token");
    require(address(swapDesc.dstReceiver) == receiver, "Invalid receiver");
    require(swapDesc.amount > 0, "Invalid swap input amount");

    bool isNativeSrcToken = address(swapDesc.srcToken) == SWAP_NATIVE_TOKEN_ADDRESS ? true : false;
    uint256 srcTokenBalance = isNativeSrcToken ? address(this).balance : swapDesc.srcToken.balanceOf(address(this));
    require(srcTokenBalance >= swapDesc.amount, "Insufficient balance of swap input token");

    if (!isNativeSrcToken) {
      swapDesc.srcToken.approve(_1inchRouter, swapDesc.amount);
    }
    uint256 beforeBalance = swapDesc.dstToken.balanceOf(receiver);
    (bool success, bytes memory result) = _1inchRouter.call{ value: isNativeSrcToken ? swapDesc.amount : 0 }(_data);
    if (!success) {
      revert(RevertReasonParser.parse(result, "1inch call failed: "));
    }
    uint256 afterBalance = swapDesc.dstToken.balanceOf(receiver);
    uint256 diff = afterBalance - beforeBalance;
    (uint256 amountOut, ) = abi.decode(result, (uint256, uint256));
    require(amountOut == diff && amountOut >= swapDesc.minReturnAmount, "Invalid swap output amount");

    uint256 today = (block.timestamp / DAY) * DAY;
    dailyBought[today] = dailyBought[today] + amountOut;

    emit BoughtBack(address(swapDesc.srcToken), address(swapDesc.dstToken), swapDesc.amount, amountOut);
  }

  /// @dev buy back tokens using router
  /// @param _router The address of the router.
  /// @param _tokenIn The address of the input token.
  /// @param _tokenOut The address of the output token.
  /// @param _amountIn The amount to sell.
  /// @param _amountOutMin The minimum amount to receive.
  /// @param _swapData The swap data.
  function buyback(
    address _router,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _amountOutMin,
    bytes calldata _swapData
  ) external onlyRole(BOT) nonReentrant whenNotPaused {
   _buyback(_router, _router, _tokenIn, _tokenOut, _amountIn, _amountOutMin, _swapData);
  }

  /// @dev buy back tokens using router
  /// @param _router The address of the router.
  /// @param _spender The address of the spender.
  /// @param _tokenIn The address of the input token.
  /// @param _tokenOut The address of the output token.
  /// @param _amountIn The amount to sell.
  /// @param _amountOutMin The minimum amount to receive.
  /// @param _swapData The swap data.
  function buyback(
    address _router,
    address _spender,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _amountOutMin,
    bytes calldata _swapData
  ) external onlyRole(BOT) nonReentrant whenNotPaused {
    _buyback(_router, _spender, _tokenIn, _tokenOut, _amountIn, _amountOutMin, _swapData);
  }
  function _buyback(
    address _router,
    address _spender,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _amountOutMin,
    bytes calldata _swapData
  ) private {
    require(tokenInWhitelist[_tokenIn], "token not whitelisted");
    require(tokenOut == _tokenOut, "token not whitelisted");
    require(routerWhitelist[_router], "router not whitelisted");
    require(routerWhitelist[_spender], "spender not whitelisted");

    uint256 beforeTokenIn = _getTokenBalance(_tokenIn, address(this));
    uint256 beforeTokenOut = _getTokenBalance(_tokenOut, address(this));
    {
      bool isNativeTokenIn = (_tokenIn == SWAP_NATIVE_TOKEN_ADDRESS);
      if (!isNativeTokenIn) {
        IERC20(_tokenIn).safeApprove(_spender, _amountIn);
      }
      (bool success, ) = _router.call{ value: isNativeTokenIn ? _amountIn : 0 }(_swapData);
      require(success, "swap failed");

      if (!isNativeTokenIn) {
        IERC20(_tokenIn).safeApprove(_spender, 0);
      }
    }

    uint256 actualAmountIn = beforeTokenIn - _getTokenBalance(_tokenIn, address(this));
    uint256 actualAmountOut = _getTokenBalance(_tokenOut, address(this)) - beforeTokenOut;

    require(actualAmountIn <= _amountIn, "exceed amount in");
    require(actualAmountOut >= _amountOutMin, "not enough profit");

    IERC20(_tokenOut).safeTransfer(receiver, actualAmountOut);

    emit BoughtBack(_router, _spender, _tokenIn, _tokenOut, actualAmountIn, actualAmountOut);
  }

  /**
   * @dev change receiver
   * @param _receiver - Address of the receiver
   */
  function changeReceiver(address _receiver) external onlyRole(MANAGER) {
    require(_receiver != address(0), "Invalid receiver");
    require(_receiver != receiver, "Receiver is the same");

    receiver = _receiver;
    emit ReceiverChanged(_receiver);
  }

  /// @dev sets the router whitelist.
  /// @param _router The address of the router.
  /// @param status The status of the router.
  function setRouterWhitelist(address _router, bool status) external onlyRole(MANAGER) {
    require(_router != address(0), "Invalid router address");
    require(routerWhitelist[_router] != status, "whitelist same status");
    routerWhitelist[_router] = status;
    emit RouterChanged(_router, status);
  }

  /**
   * @dev add token to swap input token whitelist
   * @param _tokenIn - Address of the swap input token
   */
  function addTokenInWhitelist(address _tokenIn) external onlyRole(MANAGER) {
    require(_tokenIn != address(0), "Invalid token");
    require(!tokenInWhitelist[_tokenIn], "Already whitelisted");

    tokenInWhitelist[_tokenIn] = true;
    emit TokenInChanged(_tokenIn, true);
  }

  /**
   * @dev remove token from swap input token whitelist
   * @param _tokenIn - Address of the swap input token
   */
  function removeTokenInWhitelist(address _tokenIn) external onlyRole(MANAGER) {
    require(tokenInWhitelist[_tokenIn], "Token is not in whitelist");

    delete tokenInWhitelist[_tokenIn];
    emit TokenInChanged(_tokenIn, false);
  }

  /**
   * @dev allows admin to withdraw tokens for emergency or recover any other mistaken tokens.
   * @param _token token address
   * @param _amount token amount
   */
  function emergencyWithdraw(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_token == address(0)) {
      (bool success, ) = payable(msg.sender).call{ value: _amount }("");
      require(success, "Withdraw failed");
    } else {
      IERC20(_token).safeTransfer(msg.sender, _amount);
    }
    emit EmergencyWithdraw(_token, _amount);
  }

  /**
   * @dev allows bot to withdraw tokens to the receiver address
   * @param _token token address
   * @param _amount token amount
   */
  function withdraw(address _token, uint256 _amount) external onlyRole(BOT) {
    require(
      tokenInWhitelist[_token] || _token == SWAP_NATIVE_TOKEN_ADDRESS || _token == tokenOut,
      "Token not whitelisted"
    );
    require(_amount > 0, "Invalid amount");
    if (_token == SWAP_NATIVE_TOKEN_ADDRESS) {
      (bool success, ) = payable(receiver).call{ value: _amount }("");
      require(success, "Withdraw failed");
    } else {
      IERC20(_token).safeTransfer(receiver, _amount);
    }
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /**
   * @dev unpause the contract
   */
  function unpause() external onlyRole(MANAGER) {
    _unpause();
  }

  receive() external payable {}

  // /* ============ Internal Functions ============ */

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  function _getTokenBalance(address _token, address account) internal view returns (uint256) {
    if (_token == SWAP_NATIVE_TOKEN_ADDRESS) {
      return account.balance;
    } else {
      return IERC20(_token).balanceOf(account);
    }
  }
}
