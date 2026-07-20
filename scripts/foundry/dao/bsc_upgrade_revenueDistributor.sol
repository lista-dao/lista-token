pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { Upgrades, Options } from "@openzeppelin/foundry-upgrades/src/LegacyUpgrades.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ListaRevenueDistributor } from "../../../contracts/dao/ListaRevenueDistributor.sol";

/// @notice BSC Testnet: Deploy new RevenueDistributor impl + upgrade via ProxyAdmin.
///   Satisfies checklist items 1.9–1.12 for BSC RevenueDistributor.
///
///   Requires two env vars:
///     PRIVATE_KEY_TESTNET     - deployer (0x6616...) deploys impl
///     PRIVATE_KEY_PROXY_ADMIN - ProxyAdmin owner (0x05E3...) calls upgradeAndCall
///
///   Usage:
///     source .env && forge script scripts/foundry/dao/bsc_upgrade_revenueDistributor.sol \
///       --rpc-url $BSC_TESTNET_RPC --broadcast -vvvv
contract BscUpgradeRevenueDistributor is Script {
  address listaRevenueDistributorImpl;
  address listaRevenueDistributorProxy = 0xe36857af784fB2B8cFA22481b51Fa0c99D13fF20;

  uint256 deployerKey;
  uint256 proxyAdminKey;
  address proxyAdminOwner;
  address proxyAdmin = 0x529D1D9eB9D2D664148be1AE15281521c5d498F3;
  
  function setUp() public virtual {
    // ─── Step 0: Fetch Keys & Setup ───
    deployerKey = vm.envUint("PRIVATE_KEY_TESTNET");
    address deployer = vm.addr(deployerKey);
    console.log("Deployer:", deployer);

    proxyAdminKey = vm.envUint("PRIVATE_KEY_PROXY_ADMIN");
    proxyAdminOwner = vm.addr(proxyAdminKey);
    console.log("ProxyAdmin owner:", proxyAdminOwner);
  }

  function run() public {
    // ─── Step 1: Deploy new impl with deployer key ───
    // OpenZeppelin Upgrades will:
    //  1. Validate that ListaRevenueDistributor is upgrade-safe and compatible with the existing proxy storage.
    //  2. Deploy the new implementation contract automatically.
    vm.startBroadcast(deployerKey);
    Options memory deployOpts;
    deployOpts.referenceContract = "contracts/dao/historical/ListaRevenueDistributorOld.sol:ListaRevenueDistributorOld";
    listaRevenueDistributorImpl = Upgrades.prepareUpgrade(
      "contracts/dao/ListaRevenueDistributor.sol:ListaRevenueDistributor",
      deployOpts
    );
    vm.stopBroadcast();
    console.log("  New implemtation validated successfully.");

    // ─── Step 2: Upgrade ───
    vm.startBroadcast(proxyAdminKey);
    ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(listaRevenueDistributorProxy), listaRevenueDistributorImpl);
    vm.stopBroadcast();
    console.log("  Proxy upgrade executed.");

    // ─── Step 3: Verify ───
    // Check EMERGENCY_WITHDRAWER role hash exists (new feature from PR#111)
    (bool ok2, bytes memory data) = listaRevenueDistributorProxy.staticcall(abi.encodeWithSignature("EMERGENCY_WITHDRAWER()"));
    require(ok2 && data.length == 32, "EMERGENCY_WITHDRAWER not accessible");
    console.log("  [PASS] EMERGENCY_WITHDRAWER role available");

    // Fetch the new implementation address 
    listaRevenueDistributorImpl = Upgrades.getImplementationAddress(listaRevenueDistributorProxy);
    console.log("  Current Active Implementation Address:", listaRevenueDistributorImpl);

    console.log("");
    console.log("=== BSC TESTNET RevenueDistributor VERIFICATION COMPLETE ===");
    console.log("  [1.10] Storage: Validated by OZ Upgrades Plugin");
    console.log("  [1.11] Library: NONE");
    console.log("  [1.12] Upgrade: PASSED");
  }
}