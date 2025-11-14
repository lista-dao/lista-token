pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { MockERC20 } from "../../../contracts/mock/MockERC20.sol";


contract MockERC20Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mockERC20 = new MockERC20(deployer, "MOCK LP", "ML");
        console.log("MockERC20 deployed at: ", address(mockERC20));

        vm.stopBroadcast();
    }
}
