pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { VaultDistributor } from "../../../contracts/dao/VaultDistributor.sol";

contract ListaVaultDeploy is Script {
    address lpToken = 0x60A471B7187C13D3dE02aA1a9B62d7F948cF7483;
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        VaultDistributor impl = new VaultDistributor();
        console.log("Implementation: ", address(impl));

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                impl.initialize.selector,
                deployer,
                deployer,
                lpToken
            )
        );

        console.log("Proxy: ", address(proxy));
        vm.stopBroadcast();
    }
}
