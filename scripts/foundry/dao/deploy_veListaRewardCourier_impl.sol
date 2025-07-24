pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { VeListaRewardsCourier } from "../../../contracts/VeListaRewardsCourier.sol";

contract VeListaRewardCourierDeploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        VeListaRewardsCourier impl = new VeListaRewardsCourier();
        console.log("Implementation: ", address(impl));

        vm.stopBroadcast();
    }
}
