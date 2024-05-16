pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {IOFT, SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {IOAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAdapter is IOAppCore, IOFT {}

contract SendOFTScript is Script {
  using OptionsBuilder for bytes;

  uint32 constant BSC_TESTNET_ENDPOINT_ID = 40102;
  address constant LISTA_OFT_ADDRESS = 0x6698f6a4B537284ECAD1071C8868186f7ECC8bCb;
  address constant BSC_TESTNET_ADAPTER_ADDRESS = 0x6F8956d9b26D307f7b9742416E7a4D3AFe08DfDB;

  function run() external {
    uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    vm.startBroadcast(privateKey);
    address signer = vm.addr(privateKey);

    // Get the Adapter contract instance
    IOFT listaOFT = IOFT(LISTA_OFT_ADDRESS);

    // Define the send parameters
    uint256 tokensToSend = 0.0001 ether; // 0.0001 $ListaOFT

    bytes memory options = OptionsBuilder
      .newOptions()
      .addExecutorLzReceiveOption(200000, 0);

    SendParam memory sendParam = SendParam(
      BSC_TESTNET_ENDPOINT_ID,
      bytes32(uint256(uint160(signer))),
      tokensToSend,
      tokensToSend,
      options,
      "",
      ""
    );

    // Quote the send fee
    MessagingFee memory fee = listaOFT.quoteSend(sendParam, false);
    console.log("Native fee: %d", fee.nativeFee);

    // Approve the OFT contract to spend UNI tokens
    IERC20(LISTA_OFT_ADDRESS).approve(
      LISTA_OFT_ADDRESS,
      tokensToSend
    );

    // Send the tokens
    listaOFT.send{value: fee.nativeFee}(sendParam, fee, signer);

    console.log("Tokens bridged successfully!");
  }
}
