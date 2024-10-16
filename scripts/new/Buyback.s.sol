// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Buyback } from "../../contracts/new/Buyback.sol";

contract BuybackScript is Script {
  function setUp() public {}

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: %s", deployer);
    address admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);
    address manager = vm.envOr("MANAGER", deployer);
    console.log("Manager: %s", manager);
    address pauser = vm.envOr("PAUSER", deployer);
    console.log("Pauser: %s", pauser);
    address bot = vm.envOr("BUYBACK_BOT", deployer);
    console.log("Bot: %s", bot);

    // 1Inch router
    address oneInchRouter = vm.envAddress("BUYBACK_1INCH_ROUTER");
    require(oneInchRouter != address(0), "1Inch router address cannot be null");
    console.log("1Inch Router: %s", oneInchRouter);

    // swap input tokens
    address[] memory tokenIns = vm.envAddress("BUYBACK_TOKEN_INS", ",");
    for (uint256 i = 0; i < tokenIns.length; i++) {
      require(
        tokenIns[i] != address(0),
        "Swap input token address cannot be null"
      );
      console.log("Swap input token: %s, %s", i, tokenIns[i]);
    }

    // swap output token
    address tokenOut = vm.envAddress("BUYBACK_TOKEN_OUT");
    require(tokenOut != address(0), "Swap output token address cannot be null");
    console.log("Swap output token: %s", oneInchRouter);

    // receiver address
    address receiver = vm.envAddress("BUYBACK_RECEIVER");
    require(receiver != address(0), "Receiver address cannot be null");
    console.log("Receiver: %s", receiver);

    vm.startBroadcast(deployerPrivateKey);
    Buyback buyback = new Buyback();
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(buyback),
      abi.encodeCall(
        buyback.initialize,
        (
          admin,
          manager,
          pauser,
          bot,
          oneInchRouter,
          tokenIns,
          tokenOut,
          receiver
        )
      )
    );
    vm.stopBroadcast();
    console.log("Buyback proxy address: %s", address(proxy));
    console.log("Buyback implementation address: %s", address(buyback));
  }
}
