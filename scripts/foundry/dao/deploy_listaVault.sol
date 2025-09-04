pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ListaVault } from "../../../contracts/dao/ListaVault.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";


contract ListaVaultDeploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        ListaVault impl = ListaVault(0x41A8D41E39D2390A6D2645c2f2c73e9eec21DAdC);
        // Deploy implementation
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            0x41A8D41E39D2390A6D2645c2f2c73e9eec21DAdC,
            address(proxyAdmin),
            abi.encodeWithSelector(
                impl.initialize.selector,
                deployer,
                deployer,
                0x90b94D605E069569Adf33C0e73E26a83637c94B1, // lista
                0x51075B00313292db08f3450f91fCA53Db6Bd0D11 // veLista
            )
        );


        vm.stopBroadcast();
    }
}
