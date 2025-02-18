// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../contracts/dao/VeListaInterestRebater.sol";

contract VeListaInterestRebaterTest is Test {
  ERC20 lisUSD;
  VeListaInterestRebater rebater;

  address admin = makeAddr("admin");
  address bot = makeAddr("bot");
  address manager = makeAddr("manager");
  address pauser = makeAddr("pauser");

  function setUp() public {
    lisUSD = new ERC20("lisUSD", "lisUSD");

    VeListaInterestRebater rebaterImpl = new VeListaInterestRebater();

    ERC1967Proxy proxy_ = new ERC1967Proxy(
      address(rebaterImpl),
      abi.encodeWithSelector(VeListaInterestRebater.initialize.selector, admin, manager, bot, pauser, address(lisUSD))
    );

    rebater = VeListaInterestRebater(address(proxy_));

    assertEq(address(lisUSD), rebater.lisUSD());
    assertEq(type(uint256).max, rebater.lastSetTime());
    assertEq(1 days, rebater.waitingPeriod());

    assertEq(bytes32(0), rebater.merkleRoot());
    assertEq(bytes32(0), rebater.pendingMerkleRoot());
  }

  function test_pendingMerkleRoot() public {
    bytes32 _merkleRoot = bytes32(0x0000000000000000000000000000000000000000000000000000000000000001);

    vm.startPrank(bot);
    vm.expectRevert("Invalid pending merkle root");
    rebater.acceptMerkleRoot();

    rebater.setPendingMerkleRoot(_merkleRoot); // success

    vm.expectRevert("Invalid new merkle root");
    rebater.setPendingMerkleRoot(_merkleRoot);

    assertEq(_merkleRoot, rebater.pendingMerkleRoot());
    assertEq(block.timestamp, rebater.lastSetTime());
    assertEq(bytes32(0), rebater.merkleRoot());

    vm.expectRevert("Not ready to accept");
    rebater.acceptMerkleRoot();

    skip(1 days);
    rebater.acceptMerkleRoot(); // success

    assertEq(bytes32(0), rebater.pendingMerkleRoot());
    assertEq(type(uint).max, rebater.lastSetTime());
    assertEq(_merkleRoot, rebater.merkleRoot());

    vm.expectRevert("Invalid pending merkle root");
    rebater.acceptMerkleRoot();
  }
}
