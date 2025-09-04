pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { MockThenaERC20LpToken } from "../../../contracts/mock/MockThenaERC20LpToken.sol";


contract MockThenaERC20LpTokenDeploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        MockThenaERC20LpToken token = new MockThenaERC20LpToken(deployer, "Thena lisUSD/USDT", "Lista lisUSD/USDT");
        console.log("token: ", address(token));

        vm.stopBroadcast();
    }
}
