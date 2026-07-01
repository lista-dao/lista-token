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

  function getSendLibrary(address sender, uint32 eid) external view returns (address lib);

  function isDefaultSendLibrary(address sender, uint32 eid) external view returns (bool);

  function setReceiveLibrary(address oapp, uint32 eid, address newLib, uint256 gracePeriod) external;

  function getReceiveLibrary(address receiver, uint32 eid) external view returns (address lib, bool isDefault);

  function setConfig(address oapp, address lib, SetConfigParam[] calldata params) external;
}

/**
 * @title SetDVNConfig
 * @notice Configures the LayerZero send/receive libraries and the ULN (DVN) +
 *         executor settings for the local OFT against its remote peer.
 *
 * DVN policy comes from OFTConfig: requiredDVNs must ALL verify; an
 * `optionalDVNThreshold` of the optionalDVNs must verify. Mainnet requires one
 * mandatory DVN plus a 2-of-3 optional threshold. Testnet requires one mandatory
 * DVN plus a 1-of-1 optional.
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
  uint8 internal constant NIL_DVN_COUNT = type(uint8).max;

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
        requiredDVNCount: _dvnCount(required),
        optionalDVNCount: _dvnCount(optional),
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
    address currentSendLib = endpoint.getSendLibrary(oapp, cfg.dstEid);
    bool isDefaultSendLib = endpoint.isDefaultSendLibrary(oapp, cfg.dstEid);
    if (currentSendLib != cfg.sendLib || isDefaultSendLib) {
      endpoint.setSendLibrary(oapp, cfg.dstEid, cfg.sendLib);
    } else {
      console.log("send library already set");
    }
    endpoint.setConfig(oapp, cfg.sendLib, sendParams);
    // inbound: receive library + uln
    (address currentReceiveLib, bool isDefaultReceiveLib) = endpoint.getReceiveLibrary(oapp, cfg.dstEid);
    if (currentReceiveLib != cfg.receiveLib || isDefaultReceiveLib) {
      endpoint.setReceiveLibrary(oapp, cfg.dstEid, cfg.receiveLib, 0);
    } else {
      console.log("receive library already set");
    }
    endpoint.setConfig(oapp, cfg.receiveLib, recvParams);
    vm.stopBroadcast();
    console.log("DVN / library config set");
  }

  function _dvnCount(address[] memory dvns) internal pure returns (uint8) {
    return dvns.length == 0 ? NIL_DVN_COUNT : uint8(dvns.length);
  }
}
