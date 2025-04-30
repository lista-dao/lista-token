// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Forge imports
import "forge-std/console.sol";
import "forge-std/Script.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

struct SendParam {
  uint32 dstEid; // Destination endpoint ID.
  bytes32 to; // Recipient address.
  uint256 amountLD; // Amount to send in local decimals.
  uint256 minAmountLD; // Minimum amount to send in local decimals.
  bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
  bytes composeMsg; // The composed message for the send() operation.
  bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
}

interface IOFT {
    function send(
        SendParam memory sendParam,
        MessagingFee memory fee,
        address payable refundAddress
    ) external payable;

    function quoteSend(SendParam memory sendParam, bool isOFTAdapter)
        external
        view
        returns (MessagingFee memory);

}

contract slisBnbOftTestnetScript is Script {
  using OptionsBuilder for bytes;

  uint256 public userPK;
  address public user;
  address public receiver;

  IERC20 public slisBnb;
  IOFT public slisBnbOFT;
  IOFT public slisBnbOFTAdapter;

  uint32 public toChainEid;

  // Change this for sending from target chain to src chain
  bool public sendFromSourceChain = false;

  function setUp() public {
    address _slisBnb = vm.envAddress("SLISBNB_ADDRESS");
    address _slisBnbOFTAdapter = vm.envAddress("OFT_ADAPTER");
    address _slisBnbOFT = vm.envAddress("OFT");

    slisBnb = IERC20(_slisBnb);
    slisBnbOFTAdapter = IOFT(_slisBnbOFTAdapter);
    slisBnbOFT = IOFT(_slisBnbOFT);

    userPK = vm.envUint("DEPLOYER_PRIVATE_KEY");
    user = vm.addr(userPK);
    receiver = user; // or change to any address u want
    console.log("User: %s", user);
    console.log("Receiver: %s", receiver);

    toChainEid = uint32(vm.envUint(
      sendFromSourceChain ? "TARGET_CHAIN_EID" : "SOURCE_CHAIN_EID"
    ));
  }

  function run() public {
    // amount of token to send
    uint256 tokensToSend = 0.1 ether;
    // build cross chain option
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory sendParam = SendParam(toChainEid, bytes32(uint256(uint160(receiver))), tokensToSend, tokensToSend, options, "", "");
    MessagingFee memory fee;
    // start to broadcast tx
    vm.startBroadcast(userPK);
    // send from BSC
    if (sendFromSourceChain) {
      slisBnb.approve(address(slisBnbOFTAdapter), tokensToSend);
      fee = slisBnbOFTAdapter.quoteSend(sendParam, false);
      slisBnbOFTAdapter.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    } else {
      fee = slisBnbOFT.quoteSend(sendParam, false);
      slisBnbOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    }
    vm.stopBroadcast();
  }
}
