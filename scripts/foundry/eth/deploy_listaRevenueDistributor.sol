pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ListaRevenueDistributor } from "../../../contracts/dao/ListaRevenueDistributor.sol";

/**
 * @dev ETH mainnet deployment script for ListaRevenueDistributor
 *
 * Fee flow: Moolah → LendingFeeRecipient(0xd10a024602E042dcb9C19e21682c3b896c8B0d30) → ListaRevenueDistributor (this contract)
 * Revenue accumulates here, MANAGER calls emergencyWithdraw() for cross-chain bridging to BSC
 *
 * After deployment:
 * 1. Record this proxy address
 * 2. Fill it into MarketFactory deploy script (listaRevenueDistributor param)
 * 3. Call LendingFeeRecipient(0xd10a024602E042dcb9C19e21682c3b896c8B0d30).setMarketFeeRecipient(this proxy address)
 *
 * Run:
 *   forge script scripts/foundry/eth/deploy_listaRevenueDistributor.sol --rpc-url eth --broadcast --verify
 */
contract ListaRevenueDistributorDeploy is Script {
  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: ", deployer);

    // ETH mainnet addresses
    address manager = 0x8d388136d578dCD791D081c6042284CED6d9B0c6; // Manager Safe
    address listaAddress = 0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46; // TODO: replace with real LISTA token address on ETH mainnet
    address autoBuybackAddress = address(0); // not used on ETH
    address revenueWalletAddress = address(0); // not used on ETH
    address listaDistributeToAddress = address(0); // not used on ETH
    uint128 distributeRate = 700000000000000000; // 70%

    vm.startBroadcast(deployerPrivateKey);

    // Deploy implementation
    ListaRevenueDistributor impl = new ListaRevenueDistributor();
    console.log("Implementation: ", address(impl));

    // Deploy proxy
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(impl),
      abi.encodeWithSelector(
        impl.initialize.selector,
        deployer, // admin (will transfer later)
        manager,
        listaAddress,
        autoBuybackAddress,
        revenueWalletAddress,
        listaDistributeToAddress,
        distributeRate
      )
    );
    console.log("ListaRevenueDistributor proxy: ", address(proxy));

    vm.stopBroadcast();
  }
}
