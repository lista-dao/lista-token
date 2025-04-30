// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import { ListaOFT } from "../../contracts/oft/ListaOFT.sol";

contract TargetChainOFTDeploymentImplScript is Script {

  uint256 deployerPK;
  address deployer;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    // get private key
    deployerPK = vm.envUint("DEPLOYER_PRIVATE_KEY");
    deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    // --- endpoints
    address oftLzEndpoint = vm.envAddress("TARGET_LZ_ENDPOINT");

    vm.startBroadcast(deployerPK);
    // deploy impl.
    ListaOFT slisBnbOFTImpl = new ListaOFT(oftLzEndpoint);
    console.log("slisBnbOFTImpl: %s", address(slisBnbOFTImpl));
    vm.stopBroadcast();
  }

}
