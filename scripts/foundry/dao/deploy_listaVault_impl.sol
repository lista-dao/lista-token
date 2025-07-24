pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ListaVault } from "../../../contracts/dao/ListaVault.sol";

contract ListaVaultDeploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        ListaVault impl = new ListaVault();
        console.log("Implementation: ", address(impl));

        vm.stopBroadcast();
    }
}
