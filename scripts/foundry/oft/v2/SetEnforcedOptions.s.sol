// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { ListaOFTAdapterV2 } from "../../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { OFTConfig } from "./OFTConfig.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title SetEnforcedOptions
 * @notice Sets the enforced LayerZero options (a destination lzReceive gas floor)
 *         for the local OFT's SEND message type against its remote peer. Without
 *         an enforced floor, a user who calls send() with empty or insufficient
 *         extraOptions produces a message carrying too little destination gas, so
 *         _credit (mint on the OFT / unlock on the adapter) runs out of gas on the
 *         destination chain and the funds stall in a stuck / retryable state.
 *         Enforced options are additive to whatever the caller supplies, so they
 *         guarantee a minimum lzReceive gas regardless of the caller's options.
 *         Must be broadcast by a MANAGER holder.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required, must hold MANAGER)
 *   OAPP           (required) local proxy address
 *   DST_EID        (optional) remote endpoint id; defaults to the config's dstEid
 *   LZ_RECEIVE_GAS (optional) enforced executor lzReceive gas; default 300000
 *
 * Usage:
 *   OAPP=0x.. forge script scripts/foundry/oft/v2/SetEnforcedOptions.s.sol \
 *     --rpc-url bsc --broadcast
 *
 * @dev ListaOFTAdapterV2 is used purely as a typed handle; setEnforcedOptions has
 *      the same selector on ListaOFTv2.
 */
contract SetEnforcedOptions is OFTScriptBase {
  using OptionsBuilder for bytes;

  // LayerZero OFT message type for a plain send (no compose).
  uint16 internal constant MSG_TYPE_SEND = 1;

  function run() external {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address oapp = vm.envAddress("OAPP");
    OFTConfig.NetworkConfig memory cfg = OFTConfig.getConfig(block.chainid);
    uint32 dstEid = uint32(vm.envOr("DST_EID", uint256(cfg.dstEid)));
    uint128 lzReceiveGas = uint128(vm.envOr("LZ_RECEIVE_GAS", uint256(300_000)));

    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(lzReceiveGas, 0);
    EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
    params[0] = EnforcedOptionParam({ eid: dstEid, msgType: MSG_TYPE_SEND, options: options });

    console.log("OApp:", oapp);
    console.log("Dst eid:", dstEid);
    console.log("lzReceive gas:", lzReceiveGas);

    vm.startBroadcast(pk);
    ListaOFTAdapterV2(oapp).setEnforcedOptions(params);
    vm.stopBroadcast();
    console.log("Enforced options set");
  }
}
