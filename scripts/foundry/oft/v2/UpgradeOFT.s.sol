// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { ListaOFTAdapterV2 } from "../../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { ListaOFTv2 } from "../../../../contracts/oft/v2/ListaOFTv2.sol";
import { OFTConfig } from "./OFTConfig.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title UpgradeOFT
 * @notice Deploys a fresh implementation for the local OFT UUPS proxy (the
 *         lock/unlock adapter on BSC, the mint/burn OFT on the remote chain) and
 *         upgrades the proxy to it. The implementation immutables (token /
 *         lzEndpoint) are taken from OFTConfig for the current chain, so they are
 *         reused unchanged across the upgrade. Must be broadcast by a
 *         DEFAULT_ADMIN_ROLE holder (UUPS _authorizeUpgrade is admin-gated).
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required, must hold DEFAULT_ADMIN_ROLE on OAPP)
 *   OAPP (required) local proxy address to upgrade
 *
 * Usage:
 *   OAPP=0x.. forge script scripts/foundry/oft/v2/UpgradeOFT.s.sol --rpc-url bsc-test --broadcast
 *
 * @dev Storage layout is unchanged by the audit-remediation impls (the six
 *      TransferLimiterV2 mappings keep their slots; only trailing empty gap space
 *      is resized), so a plain upgradeTo without a reinitializer is safe.
 */
contract UpgradeOFT is OFTScriptBase {
  function run() external {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address oapp = vm.envAddress("OAPP");
    OFTConfig.NetworkConfig memory cfg = OFTConfig.getConfig(block.chainid);

    vm.startBroadcast(pk);
    address newImpl;
    if (cfg.isAdapter) {
      newImpl = address(new ListaOFTAdapterV2(cfg.token, cfg.lzEndpoint));
      ListaOFTAdapterV2(oapp).upgradeTo(newImpl);
    } else {
      newImpl = address(new ListaOFTv2(cfg.lzEndpoint));
      ListaOFTv2(oapp).upgradeTo(newImpl);
    }
    vm.stopBroadcast();

    console.log("Proxy:", oapp);
    console.log("isAdapter:", cfg.isAdapter);
    console.log("New implementation:", newImpl);
  }
}
