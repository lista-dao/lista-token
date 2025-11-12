pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BatchManagementUtils } from "../../../contracts/utils/BatchManagementUtils.sol";

contract BatchManagementUtilsDeploy is Script {
    address admin = 0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253;
    address manager = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;
    address distributor1 = 0x81a62B329CC8939494d8613F614171a9955A46e8;
    address distributor2 = 0x8b7d334d243b74D63C4b963893267A0F5240F990;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        BatchManagementUtils impl = new BatchManagementUtils();
        console.log("Implementation: ", address(impl));

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(impl.initialize.selector, deployer, deployer)
        );

        console.log("Proxy: ", address(proxy));

        BatchManagementUtils batchManagementUtils = BatchManagementUtils(address(proxy));

        batchManagementUtils.setDistributor(distributor1, true);
        batchManagementUtils.setDistributor(distributor2, true);

        batchManagementUtils.grantRole(batchManagementUtils.DEFAULT_ADMIN_ROLE(), admin);
        batchManagementUtils.grantRole(batchManagementUtils.MANAGER(), manager);

        batchManagementUtils.revokeRole(batchManagementUtils.MANAGER(), deployer);
        batchManagementUtils.grantRole(batchManagementUtils.DEFAULT_ADMIN_ROLE(), deployer);

        console.log("Deployment and setup complete.");
        vm.stopBroadcast();
    }
}
