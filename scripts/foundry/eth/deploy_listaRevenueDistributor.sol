pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ListaRevenueDistributor } from "../../../contracts/dao/ListaRevenueDistributor.sol";

/**
 * @dev Deployment script for ListaRevenueDistributor (ETH / Sepolia)
 *
 * Run (Sepolia):
 *   source .env && forge script scripts/foundry/eth/deploy_listaRevenueDistributor.sol \
 *     --rpc-url $SEPOLIA_RPC --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
 *
 * Run (ETH mainnet):
 *   source .env && forge script scripts/foundry/eth/deploy_listaRevenueDistributor.sol \
 *     --rpc-url $ETHEREUM_RPC --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
 */
contract ListaRevenueDistributorDeploy is Script {
  function _deployerKey() internal view returns (uint256) {
    if (block.chainid == 11155111) return vm.envUint("PRIVATE_KEY_TESTNET"); // Sepolia
    return vm.envUint("PRIVATE_KEY"); // Ethereum mainnet
  }

  function run() public {
    uint256 deployerPrivateKey = _deployerKey();
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: ", deployer);

    // Addresses based on chain
    address manager;
    address listaAddress;
    address autoBuybackAddress = address(0); // not used on ETH
    address revenueWalletAddress = address(0); // not used on ETH
    address listaDistributeToAddress = address(0); // not used on ETH
    uint128 distributeRate = 700000000000000000; // 70%

    if (block.chainid == 11155111) {
      // Sepolia testnet
      manager = deployer;
      listaAddress = 0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46; // placeholder (non-zero required by initialize)
    } else {
      // ETH mainnet
      manager = 0x8d388136d578dCD791D081c6042284CED6d9B0c6; // Manager Safe
      listaAddress = 0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46; // TODO: replace with real LISTA token address on ETH mainnet
    }

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
