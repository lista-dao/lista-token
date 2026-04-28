pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";

import { VeLista } from "../../../contracts/VeLista.sol";

contract VeListaDeploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        VeLista impl = new VeLista();
        console.log("Implementation: ", address(impl));

        vm.stopBroadcast();
    }
}
