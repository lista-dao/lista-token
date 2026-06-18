// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { OFTConfig } from "./OFTConfig.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

struct SetConfigParam {
  uint32 eid;
  uint32 configType;
  bytes config;
}

interface ILayerZeroEndpointV2Config {
  function setSendLibrary(address oapp, uint32 eid, address newLib) external;

  function setReceiveLibrary(address oapp, uint32 eid, address newLib, uint256 gracePeriod) external;

  function setConfig(address oapp, address lib, SetConfigParam[] calldata params) external;
}

/**
 * @title SetDVNConfig
 * @notice Configures the LayerZero send/receive libraries and the ULN (DVN) +
 *         executor settings for the local OFT against its remote peer.
 *
 * DVN policy comes from OFTConfig: requiredDVNs must ALL verify; an additional
 * `optionalDVNThreshold` of the optionalDVNs must verify. Mainnet uses
 * LayerZero Labs + Nethermind + Google (required) and USDT0 (optional).
 *
 * Must be broadcast by the OApp delegate (MANAGER) — endpoint config setters are
 * delegate-gated.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required, must be the OApp delegate / MANAGER)
 *   OAPP (required) local proxy address
 *
 * Usage:
 *   OAPP=0x.. forge script scripts/foundry/oft/v2/SetDVNConfig.s.sol \
 *     --rpc-url bsc --broadcast
 */
contract SetDVNConfig is OFTScriptBase {
  uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
  uint32 internal constant CONFIG_TYPE_ULN = 2;
  uint32 internal constant MAX_MESSAGE_SIZE = 10000;

  // mirror of the LayerZero ULN config layout
  struct UlnConfig {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
  }

  struct ExecutorConfig {
    uint32 maxMessageSize;
    address executor;
  }

  function run() external {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address oapp = vm.envAddress("OAPP");
    OFTConfig.NetworkConfig memory cfg = OFTConfig.getConfig(block.chainid);

    address[] memory required = _sorted(cfg.requiredDVNs);
    address[] memory optional = _sorted(cfg.optionalDVNs);

    bytes memory ulnBytes = abi.encode(
      UlnConfig({
        confirmations: cfg.confirmations,
        requiredDVNCount: uint8(required.length),
        optionalDVNCount: uint8(optional.length),
        optionalDVNThreshold: cfg.optionalDVNThreshold,
        requiredDVNs: required,
        optionalDVNs: optional
      })
    );
    bytes memory execBytes = abi.encode(
      ExecutorConfig({ maxMessageSize: MAX_MESSAGE_SIZE, executor: cfg.executor })
    );

    SetConfigParam[] memory sendParams = new SetConfigParam[](2);
    sendParams[0] = SetConfigParam(cfg.dstEid, CONFIG_TYPE_EXECUTOR, execBytes);
    sendParams[1] = SetConfigParam(cfg.dstEid, CONFIG_TYPE_ULN, ulnBytes);

    SetConfigParam[] memory recvParams = new SetConfigParam[](1);
    recvParams[0] = SetConfigParam(cfg.dstEid, CONFIG_TYPE_ULN, ulnBytes);

    console.log("OApp:", oapp);
    console.log("Endpoint:", cfg.lzEndpoint);
    console.log("dstEid:", cfg.dstEid);
    console.log("requiredDVNs:", required.length);
    console.log("optionalDVNs:", optional.length);

    ILayerZeroEndpointV2Config endpoint = ILayerZeroEndpointV2Config(cfg.lzEndpoint);

    vm.startBroadcast(pk);
    // outbound: send library + executor + uln
    endpoint.setSendLibrary(oapp, cfg.dstEid, cfg.sendLib);
    endpoint.setConfig(oapp, cfg.sendLib, sendParams);
    // inbound: receive library + uln
    endpoint.setReceiveLibrary(oapp, cfg.dstEid, cfg.receiveLib, 0);
    endpoint.setConfig(oapp, cfg.receiveLib, recvParams);
    vm.stopBroadcast();
    console.log("DVN / library config set");
  }
}
