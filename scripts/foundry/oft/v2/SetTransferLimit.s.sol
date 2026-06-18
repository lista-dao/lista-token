// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { TransferLimiterV2 } from "../../../../contracts/oft/v2/TransferLimiterV2.sol";
import { ListaOFTAdapterV2 } from "../../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { OFTConfig } from "./OFTConfig.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title SetTransferLimit
 * @notice Pushes the transfer-limit configuration (from OFTConfig) to the local
 *         OFT. Must be broadcast by a MANAGER holder.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required, must hold MANAGER)
 *   OAPP (required) local proxy address
 *
 * Usage:
 *   OAPP=0x.. forge script scripts/foundry/oft/v2/SetTransferLimit.s.sol \
 *     --rpc-url bsc --broadcast
 *
 * @dev ListaOFTAdapterV2 is used purely as a typed handle; setTransferLimitConfigs
 *      has the same selector on ListaOFTv2.
 */
contract SetTransferLimit is OFTScriptBase {
  function run() external {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address oapp = vm.envAddress("OAPP");
    OFTConfig.NetworkConfig memory cfg = OFTConfig.getConfig(block.chainid);
    TransferLimiterV2.TransferLimit[] memory limits = _limits(cfg);

    console.log("OApp:", oapp);
    console.log("dstEid:", limits[0].dstEid);

    vm.startBroadcast(pk);
    ListaOFTAdapterV2(oapp).setTransferLimitConfigs(limits);
    vm.stopBroadcast();
    console.log("Transfer limits set");
  }
}
