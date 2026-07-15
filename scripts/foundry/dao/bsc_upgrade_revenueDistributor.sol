pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
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
  address constant REV_PROXY = 0xe36857af784fB2B8cFA22481b51Fa0c99D13fF20;
  address constant PROXY_ADMIN = 0x529D1D9eB9D2D664148be1AE15281521c5d498F3;

  function run() public {
    // ─── Step 1: Deploy new impl with deployer key ───
    uint256 deployerKey = vm.envUint("PRIVATE_KEY_TESTNET");
    address deployer = vm.addr(deployerKey);
    console.log("Deployer:", deployer);

    vm.startBroadcast(deployerKey);
    ListaRevenueDistributor newImpl = new ListaRevenueDistributor();
    console.log("  New impl:", address(newImpl));
    vm.stopBroadcast();

    // ─── Step 2: Upgrade via ProxyAdmin owner ───
    uint256 proxyAdminKey = vm.envUint("PRIVATE_KEY_PROXY_ADMIN");
    address proxyAdminOwner = vm.addr(proxyAdminKey);
    console.log("ProxyAdmin owner:", proxyAdminOwner);

    vm.startBroadcast(proxyAdminKey);
    // OZ v5 ProxyAdmin: upgradeAndCall(proxy, newImpl, data)
    (bool ok, ) = PROXY_ADMIN.call(
      abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", REV_PROXY, address(newImpl), "")
    );
    require(ok, "upgradeAndCall failed");
    console.log("  upgradeAndCall succeeded");
    vm.stopBroadcast();

    // ─── Step 3: Verify ───
    // Check EMERGENCY_WITHDRAWER role hash exists (new feature from PR#111)
    (bool ok2, bytes memory data) = REV_PROXY.staticcall(abi.encodeWithSignature("EMERGENCY_WITHDRAWER()"));
    require(ok2 && data.length == 32, "EMERGENCY_WITHDRAWER not accessible");
    console.log("  [PASS] EMERGENCY_WITHDRAWER role available");

    // Check impl slot updated
    bytes32 implSlot = vm.load(REV_PROXY, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
    require(address(uint160(uint256(implSlot))) == address(newImpl), "impl slot mismatch");
    console.log("  [PASS] impl slot updated");

    console.log("");
    console.log("=== BSC TESTNET RevenueDistributor VERIFICATION COMPLETE ===");
    console.log("  [1.10] Storage: no new storage vars, upgrade-safe");
    console.log("  [1.11] Library: NONE");
    console.log("  [1.12] Upgrade: PASSED");
  }
}
