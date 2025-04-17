// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20LpTokenProvider } from "../../contracts/dao/erc20LpProvider/ERC20LpTokenProvider.sol";

contract DeployERC20LpTokenProviderScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: %s", deployer);
        address admin = vm.envOr("ADMIN", deployer);
        console.log("Admin: %s", admin);
        address manager = vm.envOr("MANAGER", deployer);
        console.log("Manager: %s", manager);
        address pauser = vm.envOr("PAUSER", deployer);
        console.log("Pauser: %s", pauser);

        // clisBNB
        address lpToken = 0x3dC5a40119B85d5f2b06eEC86a6d36852bd9aB52;
        // slisBNB/BNB LP
        address token = 0xbf6e4489C2242466533EACb42b584B1C02033148;
        address lpProvidableDistributor = 0xca42be4dc67F7FF14CD5116DF807872a2E5A814F;
        address lpReserveAddress = deployer;
        uint128 exchangeRate = 930000000000000000; // 0.93
        uint128 userLpRate = 900000000000000000; // 0.9

        vm.startBroadcast(deployerPrivateKey);
        ERC20LpTokenProvider providerImpl = new ERC20LpTokenProvider();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(providerImpl),
            abi.encodeCall(providerImpl.initialize, (
                admin,
                manager,
                pauser,
                lpToken,
                token,
                lpProvidableDistributor,
                lpReserveAddress,
                exchangeRate,
                userLpRate
            ))
        );

        ERC20LpTokenProvider provider = ERC20LpTokenProvider(address(proxy));

        vm.stopBroadcast();
        console.log("ThenaERC20LpTokenProvider proxy address: %s", address(proxy));
        console.log("ThenaERC20LpTokenProvider implementation address: %s", address(providerImpl));
    }
}
