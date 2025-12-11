// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Buyback } from "../../contracts/buyback/Buyback.sol";

contract BuybackImplScript is Script {
  function setUp() public {}

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    vm.startBroadcast(deployerPrivateKey);
    Buyback buyback = new Buyback();
    vm.stopBroadcast();
    console.log("Buyback implementation address: %s", address(buyback));
  }
}
