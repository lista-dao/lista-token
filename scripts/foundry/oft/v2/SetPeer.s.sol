// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { ListaOFTAdapterV2 } from "../../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { OFTConfig } from "./OFTConfig.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title SetPeer
 * @notice Wires the trusted peer from the local OFT to its remote counterpart.
 *         Must be broadcast by a MANAGER holder.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required, must hold MANAGER)
 *   OAPP    (required) local proxy address
 *   PEER    (required) remote proxy address
 *   DST_EID (optional) remote endpoint id; defaults to the config's dstEid
 *
 * Usage:
 *   OAPP=0x.. PEER=0x.. forge script scripts/foundry/oft/v2/SetPeer.s.sol \
 *     --rpc-url bsc --broadcast
 *
 * @dev ListaOFTAdapterV2 is used purely as a typed handle; setPeer has the same
 *      selector on ListaOFTv2.
 */
contract SetPeer is OFTScriptBase {
  function run() external {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address oapp = vm.envAddress("OAPP");
    address peer = vm.envAddress("PEER");
    OFTConfig.NetworkConfig memory cfg = OFTConfig.getConfig(block.chainid);
    uint32 dstEid = uint32(vm.envOr("DST_EID", uint256(cfg.dstEid)));

    console.log("OApp:", oapp);
    console.log("Peer:", peer);
    console.log("Dst eid:", dstEid);

    vm.startBroadcast(pk);
    ListaOFTAdapterV2(oapp).setPeer(dstEid, bytes32(uint256(uint160(peer))));
    vm.stopBroadcast();
    console.log("Peer set");
  }
}
