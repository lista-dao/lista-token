// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Mock imports
import { ERC20Mock } from "./tools/mocks/ERC20Mock.sol";
import { OFTComposerMock } from "./tools/mocks/OFTComposerMock.sol";
import { ListaOFTAdapter } from "../../contracts/oft/ListaOFTAdapter.sol";
import { ListaOFT } from "../../contracts/oft/ListaOFT.sol";
import { TransferLimiter } from "../../contracts/oft/TransferLimiter.sol";

// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import { OFTMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

// OZ imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Forge imports
import "forge-std/console.sol";

// DevTools imports
import { TestHelperOz5 } from "./tools/TestHelperOz5.sol";

contract MyOFTTest is TestHelperOz5, TransferLimiter {
  using OptionsBuilder for bytes;

  uint32 aEid = 1;
  uint32 bEid = 2;

  ERC20Mock aToken;
  ListaOFTAdapter oftAdapter;
  ListaOFT bToken;

  address public userA = address(0x1);
  address public userB = address(0x2);
  uint256 public initialBalance = 10000000 ether;

  function setUp() public virtual override {
    vm.deal(userA, 1000 ether);
    vm.deal(userB, 1000 ether);

    super.setUp();
    // init 2 endpoints
    setUpEndpoints(2, LibraryType.UltraLightNode);

    // deploy erc20 token
    aToken = ERC20Mock(
      _deployOApp(type(ERC20Mock).creationCode, abi.encode("aToken", "aToken"))
    );
    // mint tokens to userA
    aToken.mint(userA, initialBalance);

    // Set Transfer Limit to both Chain A <> Chain B
    /**
      Max. amt. can be transferred per day          : 100,000
      Max. amt. per transfer                        : 10,000
      Min. amt. per transfer                        : 0.1
      Max. daily amt. per address                   : 20,000
      Max. transfer can be made per address per day : 10
    */
    TransferLimit[] memory tla = new TransferLimit[](1);
    tla[0] = TransferLimit(
      bEid,
      100000000000000000000000,
      10000000000000000000000,
      100000000000000000,
      20000000000000000000000,
      10
    );
    TransferLimit[] memory tlb = new TransferLimit[](1);
    tlb[0] = TransferLimit(
      aEid,
      100000000000000000000000,
      10000000000000000000000,
      100000000000000000,
      20000000000000000000000,
      10
    );

    // deploy oft adapter
    oftAdapter = new ListaOFTAdapter(
      tla,
      address(aToken),
      address(endpoints[aEid]),
      address(this)
    );
    // deploy oft
    bToken = new ListaOFT(
      "bToken",
      "bToken",
      tlb,
      address(endpoints[bEid]),
      address(this)
    );

    // config and wire the ofts
    address[] memory ofts = new address[](2);
    ofts[0] = address(oftAdapter);
    ofts[1] = address(bToken);
    this.wireOApps(ofts);
  }

  function test_constructor() public {
    assertEq(oftAdapter.owner(), address(this));
    assertEq(bToken.owner(), address(this));

    assertEq(aToken.balanceOf(userA), initialBalance);
    assertEq(bToken.balanceOf(userB), 0);

    assertEq(oftAdapter.token(), address(aToken));
    assertEq(bToken.token(), address(bToken));
  }

  // @dev Lock aToken at 1, mint bToken at 2
  function test_send_oft() public {
    uint256 tokensToSend = 0.1 ether;

    /** ---------------------------------
     ----- Send OFT from EID 1 to 2 -----
     ------------------------------------ */
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory aSendParam = SendParam(
      bEid,
      addressToBytes32(userB),
      tokensToSend,
      tokensToSend,
      options,
      "",
      ""
    );
    MessagingFee memory aFee = oftAdapter.quoteSend(aSendParam, false);

    assertEq(aToken.balanceOf(userA), initialBalance);
    assertEq(bToken.balanceOf(userB), 0);

    vm.startPrank(userA);
    aToken.approve(address(oftAdapter), tokensToSend);
    oftAdapter.send{ value: aFee.nativeFee }(aSendParam, aFee, payable(address(this)));
    vm.stopPrank();
    verifyPackets(bEid, addressToBytes32(address(bToken)));

    assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
    assertEq(bToken.balanceOf(userB), tokensToSend);

    /** ---------------------------------
     ----- Send OFT from EID 2 to 1 -----
     ------------------------------------ */
    bytes memory bOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory bSendParam = SendParam(
      aEid,
      addressToBytes32(userA),
      tokensToSend,
      tokensToSend,
      bOptions,
      "",
      ""
    );
    MessagingFee memory bFee = bToken.quoteSend(bSendParam, false);

    vm.startPrank(userB);
    bToken.approve(address(bToken), tokensToSend);
    bToken.send{ value: bFee.nativeFee }(bSendParam, bFee, payable(address(this)));
    vm.stopPrank();
    verifyPackets(aEid, addressToBytes32(address(oftAdapter)));

    assertEq(aToken.balanceOf(userA), initialBalance);
    assertEq(bToken.balanceOf(userB), 0);
  }

  // Verify msg integrity
  function test_send_oft_compose_msg() public {
    uint256 tokensToSend = 1 ether;

    OFTComposerMock composer = new OFTComposerMock();

    bytes memory options = OptionsBuilder
      .newOptions()
      .addExecutorLzReceiveOption(200000, 0)
      .addExecutorLzComposeOption(0, 500000, 0);
    bytes memory composeMsg = hex"1234";
    SendParam memory sendParam = SendParam(
      bEid,
      addressToBytes32(address(composer)),
      tokensToSend,
      tokensToSend,
      options,
      composeMsg,
      ""
    );
    MessagingFee memory fee = oftAdapter.quoteSend(sendParam, false);

    assertEq(aToken.balanceOf(userA), initialBalance);
    assertEq(bToken.balanceOf(address(composer)), 0);

    vm.startPrank(userA);
    aToken.approve(address(oftAdapter), tokensToSend);
    (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) = oftAdapter.send{ value: fee.nativeFee }(
      sendParam,
      fee,
      payable(address(this))
    );
    vm.stopPrank();
    verifyPackets(bEid, addressToBytes32(address(bToken)));

    // lzCompose params
    uint32 dstEid_ = bEid;
    address from_ = address(bToken);
    bytes memory options_ = options;
    bytes32 guid_ = msgReceipt.guid;
    address to_ = address(composer);
    bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
      msgReceipt.nonce,
      aEid,
      oftReceipt.amountReceivedLD,
      abi.encodePacked(addressToBytes32(userA), composeMsg)
    );
    this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

    assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
    assertEq(bToken.balanceOf(address(composer)), tokensToSend);

    assertEq(composer.from(), from_);
    assertEq(composer.guid(), guid_);
    assertEq(composer.message(), composerMsg_);
    assertEq(composer.executor(), address(this));
    assertEq(composer.extraData(), composerMsg_); // default to setting the extraData to the message as well to test
  }

}
