// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../buyback/library/RevertReasonParser.sol";

/**
  * @title ListaAutoBuyBack
  * @dev lista revenue auto buy back
  * @dev all tokens balance of ListaAutoBuyBack will be swapped to Lista Token using 1inch router
  * @dev result of swap will be sent to receiver address to distribute to users
  */
contract ListaAutoBuyback is Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;

    event BoughtBack(address indexed tokenIn, uint256 amountIn, uint256 amountOut);
    event BoughtBack(
        address indexed pair,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event ReceiverChanged(address indexed receiver);
    event RouterChanged(address indexed router, bool added);
    event TokenWhitelistChanged(address indexed token, bool added);
    event AdminTransfer(address token, uint256 amount);


    bytes32 public constant BOT = keccak256("BOT");

    bytes4 public constant SWAP_FUNCTION_SELECTOR = bytes4(keccak256("swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)"));
    address public constant SWAP_NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // The offset of the dstReceiver in the call data
    // 4 bytes for the function selector + 32 bytes for executor + 32 bytes for srcToken +
    // 32 bytes for dstToken + 32 bytes for srcReceiver = 132 bytes offset
    // @dev see SWAP_FUNCTION_SELECTOR
    uint256 public constant SWAP_DST_RECEIVER_OFFSET = 132;

    uint256 internal constant DAY = 1 days;

    address public defaultReceiver;

    mapping(address => bool) public routerWhitelist;

    mapping(uint256 => uint256) public dailyBought;

    mapping(address => bool) public tokenWhitelist;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(
        address _admin,
        address _bot,
        address _initReceiver,
        address _initRouter
    ) public initializer {
        require(_admin != address(0), "admin is the zero address");
        require(_initReceiver != address(0), "receiver is the zero address");
        require(_initRouter != address(0), "router is the zero address");

        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(BOT, _bot);

        defaultReceiver = _initReceiver;
        routerWhitelist[_initRouter] = true;
    }

    /**
     * @dev swap tokenIn for Lista using 1inch router, swap data are encoded by off-chain bot task using 1inch api
     * @param _tokenIn, token to swap
     * @param _amountIn, amount of tokenIn to swap
     * @param _1inchRouter, 1inch router contract address
     * @param _data, actual call data to _1inchRouterV5 from 1inch api
     */
    function buyback(address _tokenIn, uint256 _amountIn, address _1inchRouter, bytes calldata _data)
        external
        onlyRole(BOT)
    {
        require(_amountIn > 0, "amountIn is zero");
        require(routerWhitelist[_1inchRouter], "router not whitelisted");
        require(_getFunctionSelector(_data) == SWAP_FUNCTION_SELECTOR, "invalid function selector of _data");
        require(_extractDstReceiver(_data) == defaultReceiver, "invalid dst receiver of _data");
        require(IERC20(_tokenIn).balanceOf(address(this)) >= _amountIn, "insufficient balance");
        // Approves the 1inch router contract to spend the specified amount of _tokenIn
        IERC20(_tokenIn).approve(_1inchRouter, _amountIn);

        // Calls the 1inch router contract to execute the trade, using the swap function call data provided in '_data'
        // receiver address should already be defined in data
        (bool success, bytes memory result) = _1inchRouter.call(_data);
        if (!success) {
            revert(RevertReasonParser.parse(result, "1inch call failed: "));
        }

        (uint256 amountOut,) = abi.decode(result, (uint256, uint256));
        uint256 today = block.timestamp / DAY * DAY;
        dailyBought[today] = dailyBought[today] + amountOut;

        emit BoughtBack(_tokenIn, _amountIn, amountOut);
    }

    /// @dev buy back tokens using router
    /// @param router The address of the router.
    /// @param tokenIn The address of the input token.
    /// @param tokenOut The address of the output token.
    /// @param amountIn The amount to sell.
    /// @param amountOutMin The minimum amount to receive.
    /// @param swapData The swap data.
    function buyback(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes calldata swapData
    ) external onlyRole(BOT) {
        require(tokenWhitelist[tokenIn], "token not whitelisted");
        require(tokenWhitelist[tokenOut], "token not whitelisted");
        require(routerWhitelist[router], "router not whitelisted");

        uint256 beforeTokenIn = _getTokenBalance(tokenIn, address(this));
        uint256 beforeTokenOut = _getTokenBalance(tokenOut, defaultReceiver);

        bool isNativeTokenIn = (tokenIn == SWAP_NATIVE_TOKEN_ADDRESS);
        if (!isNativeTokenIn) {
            IERC20(tokenIn).safeApprove(router, amountIn);
        }
        (bool success, ) = router.call{value: isNativeTokenIn ? amountIn : 0}(swapData);
        require(success, "swap failed");

        uint256 actualAmountIn = beforeTokenIn - _getTokenBalance(tokenIn, address(this));
        uint256 actualAmountOut = _getTokenBalance(tokenOut, defaultReceiver) - beforeTokenOut;

        require(actualAmountIn <= amountIn, "exceed amount in");
        require(actualAmountOut >= amountOutMin, "not enough profit");

        emit BoughtBack(router, tokenIn, tokenOut, actualAmountIn, actualAmountOut);
    }

    function adminTransfer(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_token == SWAP_NATIVE_TOKEN_ADDRESS) {
            (bool success, ) = payable(msg.sender).call{ value: _amount }("");
            require(success, "Withdraw failed");
        } else {
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
        emit AdminTransfer(_token, _amount);
    }

    function changeDefaultReceiver(address _receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_receiver != address(0), "_receiver is the zero address");
        require(_receiver != defaultReceiver, "_receiver is the same");

        defaultReceiver = _receiver;
        emit ReceiverChanged(defaultReceiver);
    }

    /// @dev sets the router whitelist.
    /// @param _router The address of the router.
    /// @param status The status of the router.
    function setRouterWhitelist(address _router, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_router != address(0), "Invalid router address");
        require(routerWhitelist[_router] != status, "whitelist same status");
        routerWhitelist[_router] = status;
        emit RouterChanged(_router, true);
    }

    /// @dev sets the token whitelist.
    /// @param token The address of the token.
    /// @param status The status of the token.
    function setTokenWhitelist(address token, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(tokenWhitelist[token] != status, "whitelist same status");
        tokenWhitelist[token] = status;
        emit TokenWhitelistChanged(token, status);
    }


    function _getFunctionSelector(bytes calldata _data) private pure returns (bytes4) {
        return bytes4(_data[0:4]);
    }

    // Function to extract dstReceiver from the raw call data
    function _extractDstReceiver(bytes calldata _data) private pure returns (address dstReceiver) {
        // Read the 32 bytes located at dstReceiverOffset and cast to address
        assembly {
            dstReceiver := calldataload(add(_data.offset, SWAP_DST_RECEIVER_OFFSET))
        }
    }

    function _getTokenBalance(address _token, address account) internal view returns (uint256) {
        if (_token == SWAP_NATIVE_TOKEN_ADDRESS) {
            return account.balance;
        } else {
            return IERC20(_token).balanceOf(account);
        }
    }
}
