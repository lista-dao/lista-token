// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../library/RevertReasonParser.sol";

/**
  * @title ListaAutoBuyBack
  * @dev lista revenue auto buy back
  * @dev all tokens balance of ListaAutoBuyBack will be swapped to Lista Token using 1inch router
  * @dev result of swap will be sent to receiver address to distribute to users
  */
contract ListaAutoBuyback is Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;

    event BoughtBack(address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    event ReceiverChanged(address indexed receiver);

    event RouterChanged(address indexed router, bool added);

    bytes32 public constant BOT = keccak256("BOT");

    bytes4 public constant SWAP_FUNCTION_SELECTOR = bytes4(keccak256("swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)"));

    // The offset of the dstReceiver in the call data
    // 4 bytes for the function selector + 32 bytes for executor + 32 bytes for srcToken +
    // 32 bytes for dstToken + 32 bytes for srcReceiver = 132 bytes offset
    // @dev see SWAP_FUNCTION_SELECTOR
    uint256 public constant SWAP_DST_RECEIVER_OFFSET = 132;

    uint256 internal constant DAY = 1 days;

    address public defaultReceiver;

    mapping(address => bool) public oneInchRouterWhitelist;

    mapping(uint256 => uint256) public dailyBought;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        oneInchRouterWhitelist[_initRouter] = true;
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
        require(oneInchRouterWhitelist[_1inchRouter], "router not whitelisted");
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

    function adminTransfer(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function changeDefaultReceiver(address _receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_receiver != address(0), "_receiver is the zero address");
        require(_receiver != defaultReceiver, "_receiver is the same");

        defaultReceiver = _receiver;
        emit ReceiverChanged(defaultReceiver);
    }

    function add1InchRouterWhitelist(address _router) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!oneInchRouterWhitelist[_router], "router already whitelisted");

        oneInchRouterWhitelist[_router] = true;
        emit RouterChanged(_router, true);
    }

    function remove1InchRouterWhitelist(address _router) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(oneInchRouterWhitelist[_router], "router not whitelisted");

        delete oneInchRouterWhitelist[_router];
        emit RouterChanged(_router, false);
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
}
