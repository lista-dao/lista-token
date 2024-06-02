// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {IOFT, SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {IOAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAdapter is IOAppCore, IOFT {}

contract TransferScript is Script {
  using OptionsBuilder for bytes;

  bool internal FROM_SOURCE_CHAIN = vm.envBool("FROM_SOURCE_CHAIN");
  uint32 internal DST_EID = uint32(vm.envUint("DST_EID"));
  address internal OFT_ADDRESS = vm.envAddress("OFT_ADDRESS");
  address internal OFT_ADAPTER_ADDRESS = vm.envAddress("OFT_ADAPTER_ADDRESS");

  function run() external {

    // get signer
    uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(privateKey);
    address signer = vm.addr(privateKey);

    // how much to be sent
    uint256 tokensToSend = 88 ether;
    bytes memory options = OptionsBuilder
      .newOptions()
      .addExecutorLzReceiveOption(300000, 0);
    // construct options
    SendParam memory sendParam = SendParam(
      DST_EID,
      bytes32(uint256(uint160(signer))), // receiver address
      tokensToSend,
      tokensToSend,
      options,
      "",
      ""
    );
    // transferring from source chain
    if (FROM_SOURCE_CHAIN) {
      console.log("Using OFTAdapter");
      IAdapter listaOFTAdapter = IAdapter(OFT_ADAPTER_ADDRESS);
      // Quote the send fee
      MessagingFee memory fee = listaOFTAdapter.quoteSend(sendParam, false);
      console.log("Native fee: %d", fee.nativeFee);
      // Approve the OFT contract to spend tokens
      IERC20(OFT_ADDRESS).approve(OFT_ADAPTER_ADDRESS, tokensToSend);
      // Send the tokens
      listaOFTAdapter.send{value: fee.nativeFee}(sendParam, fee, signer);
    } else {
      console.log("Using OFT");
      // Get the OFT contract instance
      IOFT listaOFT = IOFT(OFT_ADDRESS);
      // Quote the send fee
      MessagingFee memory fee = listaOFT.quoteSend(sendParam, false);
      console.log("Native fee: %d", fee.nativeFee);
      // Approve the OFT contract to spend tokens
      IERC20(OFT_ADDRESS).approve(OFT_ADDRESS, tokensToSend);
      // Send the tokens
      listaOFT.send{value: fee.nativeFee}(sendParam, fee, signer);
    }
    console.log("Tokens bridged successfully!");
  }
}
