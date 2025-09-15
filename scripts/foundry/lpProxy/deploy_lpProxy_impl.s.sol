pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { LpProxy } from "../../../contracts/dao/LpProxy.sol";

contract LpProxyDeploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        LpProxy impl = new LpProxy();
        console.log("LpProxy Implementation: ", address(impl));

        vm.stopBroadcast();
    }
}
