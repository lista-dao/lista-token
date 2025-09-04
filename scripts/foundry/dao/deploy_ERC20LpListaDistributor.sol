pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ERC20LpListaDistributor } from "../../../contracts/dao/ERC20LpListaDistributor.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";


contract ERC20LpListaDistributorDeploy is Script {
    address listaVault = 0xc72A99939c0067a1fff09E4c23539616F250373c;
    address lpToken = 0x454FcED919Dd25cEe3d17600bB4176c044c9C0a1;
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        ERC20LpListaDistributor impl = new ERC20LpListaDistributor();
        // Deploy implementation
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            abi.encodeWithSelector(
                impl.initialize.selector,
                deployer,
                deployer,
                listaVault,
                lpToken
            )
        );

        console.log("proxy: ", address(proxy));

        vm.stopBroadcast();
    }
}
