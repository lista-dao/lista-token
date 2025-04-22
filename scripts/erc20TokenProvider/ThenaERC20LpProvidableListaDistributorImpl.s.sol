// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ThenaERC20LpProvidableListaDistributor } from "../../contracts/dao/erc20LpProvider/ThenaERC20LpProvidableListaDistributor.sol";

contract DeployThenaERC20LpProvidableDistributorImplScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: %s", deployer);
        vm.startBroadcast(deployerPrivateKey);
        ThenaERC20LpProvidableListaDistributor providerImpl = new ThenaERC20LpProvidableListaDistributor();
        vm.stopBroadcast();
        console.log("ThenaERC20LpProvidableListaDistributor implementation address: %s", address(providerImpl));
    }
}
