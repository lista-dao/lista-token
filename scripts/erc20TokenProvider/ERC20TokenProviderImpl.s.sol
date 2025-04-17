// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20LpTokenProvider } from "../../contracts/dao/erc20LpProvider/ERC20LpTokenProvider.sol";

contract DeployERC20LpTokenProviderImplScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: %s", deployer);
        vm.startBroadcast(deployerPrivateKey);
        ERC20LpTokenProvider providerImpl = new ERC20LpTokenProvider();
        vm.stopBroadcast();
        console.log("ERC20LpTokenProvider implementation address: %s", address(providerImpl));
    }
}
