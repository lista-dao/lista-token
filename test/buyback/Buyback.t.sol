// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/buyback/Buyback.sol";

contract BuybackTest is Test {
  /**
   * @dev Storage slot with the address of the implementation.
   * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
   */
  bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  address admin = 0x08aE09467ff962aF105c23775B9Bc8EAa175D27F;
  address manager = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;
  address pauser = 0xEEfebb1546d88EA0909435DF6f615084DD3c5Bd8;
  address bot = 0x44CA74923aA2036697a3fA7463CD0BA68AB7F677;
  address receiver = 0x09702Ea135d9D707DD51f530864f2B9220aAD87B;
  address oneInchRouter = 0x111111125421cA6dc452d289314280a0f8842A65;
  address tokenIn = 0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5; // lisUSD
  address oneInchNativeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address tokenOut = 0x55d398326f99059fF775485246999027B3197955; // USDT

  Buyback buyback;
  address buybackImpl;

  function setUp() public {
    vm.createSelectFork("https://rpc.ankr.com/bsc", 43143645);

    // deploy buyback
    address[] memory tokenIns = new address[](2);
    tokenIns[0] = address(tokenIn);
    tokenIns[1] = address(oneInchNativeToken);
    Buyback buybackImplContract = new Buyback();
    buybackImpl = address(buybackImplContract);
    ERC1967Proxy proxy = new ERC1967Proxy(
      buybackImpl,
      abi.encodeCall(
        buybackImplContract.initialize,
        (admin, manager, pauser, bot, oneInchRouter, tokenIns, tokenOut, receiver)
      )
    );
    address proxyAddress = address(proxy);
    buyback = Buyback(proxyAddress);
    console.log("buyback proxy address: %s", proxyAddress);
    console.log("buyback impl address: %s", buybackImpl);
    deal(tokenIn, proxyAddress, 10000 ether);
    deal(proxyAddress, 10000 ether);
  }

  function _swap(bytes memory _data) private {
    vm.startPrank(bot);
    (, IBuyback.SwapDescription memory swapDesc, ) = abi.decode(
      sliceBytes(_data, 4, _data.length - 4),
      (address, IBuyback.SwapDescription, bytes)
    );

    bool isNativeSrcToken = address(swapDesc.srcToken) == oneInchNativeToken;
    uint256 buybackBalanceBefore = isNativeSrcToken
      ? address(buyback).balance
      : swapDesc.srcToken.balanceOf(address(buyback));
    uint256 receiverBalanceBefore = swapDesc.dstToken.balanceOf(receiver);

    vm.startPrank(bot);
    buyback.buyback(oneInchRouter, _data);
    vm.stopPrank();

    uint256 buybackBalanceAfter = isNativeSrcToken
      ? address(buyback).balance
      : swapDesc.srcToken.balanceOf(address(buyback));
    uint256 receiverBalanceAfter = swapDesc.dstToken.balanceOf(receiver);

    assertEq(buybackBalanceAfter, buybackBalanceBefore - swapDesc.amount);

    uint256 today = (block.timestamp / 1 days) * 1 days;
    uint256 amountOut = buyback.dailyBought(today);
    assertTrue(amountOut >= swapDesc.minReturnAmount);
    assertEq(amountOut, receiverBalanceAfter - receiverBalanceBefore);
    vm.stopPrank();
  }

  function test_buyback() public {
    bytes
      memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b3197955000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000009702ea135d9d707dd51f530864f2b9220aad87b0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000d9fdf681582420500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000010e0000000000000000000000000000000000000000000000000000000000f051200520451b19ad0bb00ed35ef391086a692cfc74b20782b6d8c4551b9760e74c0545a9bcd90bdc41e500449908fc8b0000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000000000000067153898000000000000000000000000000000000000b3276493";

    // only bot can call buyback
    vm.startPrank(admin);
    vm.expectRevert();
    buyback.buyback(oneInchRouter, data);
    vm.stopPrank();

    vm.startPrank(pauser);
    buyback.pause();
    vm.stopPrank();

    // bot cannot call buyback when paused
    vm.startPrank(bot);
    vm.expectRevert("Pausable: paused");
    buyback.buyback(oneInchRouter, data);
    vm.stopPrank();

    // unpause
    vm.startPrank(admin);
    buyback.togglePause();
    vm.stopPrank();

    // bot can call buyback when not paused
    _swap(data);
  }

  function test_buyback_with_native_token() public {
    bytes
      memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000055d398326f99059ff775485246999027b3197955000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000009702ea135d9d707dd51f530864f2b9220aad87b0000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000001fe70d482aeb5d76590000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000ff0000000000000000000000000000000000000000e10000b300006900001a4041bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095cd0e30db002a000000000000000000000000000000000000000000000001fe70d482aeb5d7659ee63c1e50047a90a2d92a8367a91efa1906bfc8c1e05bf10c4bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c00a0f2fa6b6655d398326f99059ff775485246999027b3197955000000000000000000000000000000000000000000000020398c1f85dba4397c0000000000000000456ccf6ce4c66ecb80a06c4eca2755d398326f99059ff775485246999027b3197955111111125421ca6dc452d289314280a0f8842a6500b3276493";
    _swap(data);
  }

  /**
   * @dev test invalid 1Inch parameters
   */
  function test_invalid_1Inch_parameters() public {
    vm.startPrank(bot);

    vm.expectRevert("Invalid 1Inch router");
    buyback.buyback(bot, "0x");

    vm.expectRevert("Invalid 1Inch function selector");
    buyback.buyback(oneInchRouter, hex"07ed2378");

    bytes
      memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000055d398326f99059ff775485246999027b31979550000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000027878f3ff7799e708c3bda0484e6307ca9172e8c0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000dd7d9c52efdaf9200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000010e0000000000000000000000000000000000000000000000000000000000f051200520451b19ad0bb00ed35ef391086a692cfc74b255d398326f99059ff775485246999027b319795500449908fc8b00000000000000000000000055d398326f99059ff775485246999027b31979550000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000000000000067151c1c000000000000000000000000000000000000b3276493";
    vm.expectRevert("Invalid swap input token");
    buyback.buyback(oneInchRouter, data);

    data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000b0b84d294e0c75a6abe60171b70edeb2efd14a1b000000000000000000000000e0aa23541960bdaf33ac9601a28123b385554e5900000000000000000000000027878f3ff7799e708c3bda0484e6307ca9172e8c0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000005d4a74cf0cd660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002020000000000000000000000000000000000000000000000000001e40001b600a007e5c0d20000000000000000000000000000000000000000000001920000a200006700206ae40711b8000f4240e0aa23541960bdaf33ac9601a28123b385554e59ec303ce1edbebf7e71fc7b350341bb6a6a7a63810000000000000000000000000000000000000000000000000da213c4e908b1b40782b6d8c4551b9760e74c0545a9bcd90bdc41e500a0c028b46d02ec303ce1edbebf7e71fc7b350341bb6a6a7a63810000000000000000000000000000000000000000000000000005f40f55fffde85120f1e604e9a31c3b575f91cf008445b7ce06bf3fefbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c00449908fc8b000000000000000000000000bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c000000000000000000000000b0b84d294e0c75a6abe60171b70edeb2efd14a1b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000000000000067151d180020d6bdbf78b0b84d294e0c75a6abe60171b70edeb2efd14a1b111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000000b3276493";
    vm.expectRevert("Invalid swap output token");
    buyback.buyback(oneInchRouter, data);

    data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b3197955000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b0000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000071bbeab913ea4fb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000004160000000000000000000000000000000000000000000003f80003ca0003b051201111111254eeb25477b68fb85ed929f73a9605820782b6d8c4551b9760e74c0545a9bcd90bdc41e50084e5d7bde600000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000071bbeab913ea4fb000000000000000000000000111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000c9b204353600000000000000000000000055d398326f99059ff775485246999027b31979550000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e50000000000000000000000003b3d5e8116ddbc17a10a41b06e953497da4d56e500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002164bad404db03c5300000000000000000000000000000000000000000000000408ae8a4d4d1ac900000000a4000000a4000000a4000000a400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000a4bf15fcd800000000000000000000000058ce0e6ef670c9a05622f4188faa03a9e12ee2e4000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000242cc2878d0076022c62000000000000003b3d5e8116ddbc17a10a41b06e953497da4d56e5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000401eca3cf430e4c0a321a9813ec8e61b7ce8f45e620fa29f92b7c0199410d51abdca2002ae08323da77904e8d128b796b83c388aad64c39fc254d89aed44c898ab00000000000000000000000000000000000000000000000000000000000000000020d6bdbf780782b6d8c4551b9760e74c0545a9bcd90bdc41e580a06c4eca270782b6d8c4551b9760e74c0545a9bcd90bdc41e52e234dae75c793f67a35089c9d99245e1c58470b00000000000000000000b3276493";
    vm.expectRevert("Invalid receiver");
    buyback.buyback(oneInchRouter, data);

    vm.stopPrank();
  }

  // test change receiver
  function test_change_receiver() public {
    vm.startPrank(manager);
    vm.expectRevert("Invalid receiver");
    buyback.changeReceiver(address(0));

    vm.expectRevert("Receiver is the same");
    buyback.changeReceiver(receiver);

    address receiver2 = makeAddr("receiver2");
    buyback.changeReceiver(receiver2);
    vm.stopPrank();
    assertEq(buyback.receiver(), receiver2);

    // only manager can change receiver
    vm.startPrank(admin);
    vm.expectRevert();
    buyback.changeReceiver(makeAddr("receiver3"));
    vm.stopPrank();
  }

  // test change oneInch router whitelist
  function test_change_oneInch_router_whitelist() public {
    vm.startPrank(manager);
    vm.expectRevert("Invalid 1Inch router");
    buyback.add1InchRouterWhitelist(address(0));

    vm.expectRevert("Already whitelisted");
    buyback.add1InchRouterWhitelist(oneInchRouter);

    address oneInchRouter2 = makeAddr("1InchRouter2");
    buyback.add1InchRouterWhitelist(oneInchRouter2);
    assertTrue(buyback.oneInchRouterWhitelist(oneInchRouter2));

    buyback.remove1InchRouterWhitelist(oneInchRouter2);
    assertFalse(buyback.oneInchRouterWhitelist(oneInchRouter2));
    vm.stopPrank();

    // only manager can change oneInch router whitelist
    vm.startPrank(admin);
    vm.expectRevert();
    buyback.add1InchRouterWhitelist(oneInchRouter2);

    vm.expectRevert();
    buyback.remove1InchRouterWhitelist(oneInchRouter);
    vm.stopPrank();
  }

  // test change swap input token whitelist
  function test_change_token_in_whitelist() public {
    vm.startPrank(manager);
    vm.expectRevert("Invalid token");
    buyback.addTokenInWhitelist(address(0));

    vm.expectRevert("Already whitelisted");
    buyback.addTokenInWhitelist(tokenIn);

    address tokenIn2 = makeAddr("tokenIn2");
    buyback.addTokenInWhitelist(tokenIn2);
    assertTrue(buyback.tokenInWhitelist(tokenIn2));

    buyback.removeTokenInWhitelist(tokenIn2);
    assertFalse(buyback.tokenInWhitelist(tokenIn2));
    vm.stopPrank();

    // only manager can change swap input token whitelist
    vm.startPrank(admin);
    vm.expectRevert();
    buyback.addTokenInWhitelist(tokenIn2);

    vm.expectRevert();
    buyback.removeTokenInWhitelist(tokenIn);
    vm.stopPrank();
  }

  function _emergencyWithdraw(address _token, uint256 _amount) private {
    bool isNativeToken = _token == address(0);
    if (isNativeToken) {
      deal(address(buyback), _amount);
    } else {
      deal(_token, address(buyback), _amount);
    }

    uint256 buybackBalanceBefore = isNativeToken
      ? address(buyback).balance
      : IERC20(tokenIn).balanceOf(address(buyback));
    uint256 adminBalanceBefore = isNativeToken ? admin.balance : IERC20(tokenIn).balanceOf(admin);

    vm.startPrank(admin);
    buyback.emergencyWithdraw(_token, _amount);
    vm.stopPrank();

    uint256 buybackBalanceAfter = isNativeToken
      ? address(buyback).balance
      : IERC20(tokenIn).balanceOf(address(buyback));
    uint256 adminBalanceAfter = isNativeToken ? admin.balance : IERC20(tokenIn).balanceOf(admin);

    assertEq(buybackBalanceAfter, buybackBalanceBefore - _amount);
    assertEq(adminBalanceAfter, adminBalanceBefore + _amount);
  }

  /**
   * @dev test emergency withdraw
   */
  function test_emergency_withdraw() public {
    uint256 amount = 1000 ether;

    // only admin can withdraw
    vm.expectRevert();
    buyback.emergencyWithdraw(tokenIn, amount);

    // withdraw erc20 token
    _emergencyWithdraw(tokenIn, amount);

    // withdraw native token
    _emergencyWithdraw(address(0), amount);
  }

  /**
   * @dev test upgrade
   */
  function test_upgrade() public {
    address proxyAddress = address(buyback);
    address actualOldImpl = getImplementation(proxyAddress);
    assertEq(actualOldImpl, buybackImpl);
    address oldImpl = buybackImpl;
    address newImpl = address(new Buyback());

    // only admin can upgrade
    vm.expectRevert();
    buyback.upgradeTo(newImpl);

    vm.startPrank(admin);
    buyback.upgradeTo(newImpl);
    address actualNewImpl = getImplementation(proxyAddress);
    assertEq(actualNewImpl, newImpl);
    assertFalse(actualNewImpl == oldImpl);
    vm.stopPrank();
  }

  function getImplementation(address proxyAddress) public view returns (address) {
    bytes32 implSlot = vm.load(proxyAddress, IMPLEMENTATION_SLOT);
    return address(uint160(uint256(implSlot)));
  }

  function sliceBytes(bytes memory data, uint start, uint length) public returns (bytes memory) {
    require(start + length <= data.length, "Out of bounds");

    bytes memory result = new bytes(length);
    for (uint i = 0; i < length; i++) {
      result[i] = data[start + i];
    }
    return result;
  }
}
