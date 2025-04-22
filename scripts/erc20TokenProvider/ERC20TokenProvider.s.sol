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
        address lpToken = 0x4b30fcAA7945fE9fDEFD2895aae539ba102Ed6F6;
        // slisBNB/BNB LP
        address token = 0x3685502Ea3EA4175FB5cBB5344F74D2138A96708;
        // Thena slisBNB/WBNB correlated
        address lpProvidableDistributor = 0xFf5ed1E64aCA62c822B178FFa5C36B40c112Eb00;
        // LP Reserve Address
        address lpReserveAddress = 0xD57E5321e67607Fab38347D96394e0E58509C506;
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
