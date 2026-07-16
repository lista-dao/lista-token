pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { ListaRevenueDistributor } from "../../../contracts/dao/ListaRevenueDistributor.sol";

contract ListaRevenueDistributorImplDeploy is Script {
  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: ", deployer);
    vm.startBroadcast(deployerPrivateKey);

    // Deploy implementation only (no proxy, no upgrade)
    ListaRevenueDistributor impl = new ListaRevenueDistributor();
    console.log("ListaRevenueDistributor implementation: ", address(impl));

    vm.stopBroadcast();
  }
}
