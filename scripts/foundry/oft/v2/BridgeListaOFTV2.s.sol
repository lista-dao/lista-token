// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title BridgeListaOFTV2
 * @notice Sends LISTA through the deployed OFT v2 route.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required)
 *   OFT                (required) local ListaOFTAdapterV2 or ListaOFTv2 proxy
 *   DST_EID            (required) remote endpoint id
 *   AMOUNT             (optional) amount in wei; default 1e18
 *   MIN_AMOUNT         (optional) min amount in wei; default AMOUNT
 *   RECEIVER           (optional) recipient; default broadcaster
 *   LZ_RECEIVE_GAS     (optional) executor gas; default 300000
 */
contract BridgeListaOFTV2 is OFTScriptBase {
  using OptionsBuilder for bytes;

  function run() external {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address sender = vm.addr(pk);
    address oftAddress = vm.envAddress("OFT");
    uint32 dstEid = uint32(vm.envUint("DST_EID"));
    uint256 amount = vm.envOr("AMOUNT", uint256(1 ether));
    uint256 minAmount = vm.envOr("MIN_AMOUNT", amount);
    IOFT oft = IOFT(oftAddress);
    SendParam memory sendParam = SendParam(
      dstEid,
      bytes32(uint256(uint160(vm.envOr("RECEIVER", sender)))),
      amount,
      minAmount,
      OptionsBuilder.newOptions().addExecutorLzReceiveOption(uint128(vm.envOr("LZ_RECEIVE_GAS", uint256(300_000))), 0),
      "",
      ""
    );

    MessagingFee memory fee = oft.quoteSend(sendParam, false);

    console.log("Sender:", sender);
    console.log("OFT:", oftAddress);
    console.log("Dst eid:", dstEid);
    console.log("Amount:", amount);
    console.log("Native fee:", fee.nativeFee);

    vm.startBroadcast(pk);
    if (oft.approvalRequired()) {
      IERC20(oft.token()).approve(oftAddress, amount);
    }
    oft.send{ value: fee.nativeFee }(sendParam, fee, sender);
    vm.stopBroadcast();
    console.log("Bridge send submitted");
  }
}
