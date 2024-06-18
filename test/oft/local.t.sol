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

contract OFTTest is TestHelperOz5, TransferLimiter {
  using OptionsBuilder for bytes;

  uint32 aEid = 1;
  uint32 bEid = 2;

  // @dev note as chain A
  ERC20Mock aToken;
  ListaOFTAdapter oftAdapter;
  // @dev note as chain B
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
  function test_send_back_and_forth() public {
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

  // @dev simulate we transfer more than 100,000 tokens per day
  function test_exceeded_daily_global_limit() public {
    uint256 tokensToSend = 10000 ether;
    address[11] memory users = [
            address(0x3), address(0x4), address(0x5), address(0x6), address(0x7), address(0x8),
            address(0x9), address(0x11), address(0x12), address(0x13), address(0x14)
      ];
    // transfer 10000 with 11 different user
    // 110,000 tokens will exceed the global transfer limit
    for (uint i = 0; i < users.length; ++i) {
      address user = users[i];
      vm.deal(user, 1000 ether);
      try this.send_from_a_to_b(user, user, tokensToSend) {
      } catch (bytes memory reason) {
        console.log("test_exceeded_daily_global_limit(): Error caught: TransferLimitExceeded()");
        bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
        bytes4 receivedSelector = bytes4(reason);
        assertEq(desiredSelector, receivedSelector);
      }
    }
    // after 1 day, the global transfer limit will be reset
    vm.warp(vm.getBlockTimestamp() + 86401);
    vm.deal(address(0x1234), 1000 ether);
    send_from_a_to_b(address(0x1234), address(0x1234), 10000 ether);
    console.log("test_exceeded_daily_global_limit(): succeeded after 1 day");
  }

  // @dev simulate an user transfer more than 20,000 tokens per day
  function test_exceeded_daily_user_transfer_limit() public {
    for (uint i = 0; i < 2; ++i) {
      try this.send_from_a_to_b(userA, userA, 10000 ether) {
      } catch (bytes memory reason) {
        console.log("test_exceeded_daily_user_transfer_limit(): Error caught: TransferLimitExceeded()");
        bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
        bytes4 receivedSelector = bytes4(reason);
        assertEq(desiredSelector, receivedSelector);
      }
    }
    // after 1 day, the user transfer limit will be reset
    vm.warp(vm.getBlockTimestamp() + 86401);
    send_from_a_to_b(userA, userA, 10 ether);
    console.log("test_exceeded_daily_user_transfer_limit(): succeeded after 1 day");
  }

  // @dev simulate an user transfer more than 10 times per day
  function test_exceeded_daily_user_transfer_attempts() public {
    for (uint i = 0; i < 11; ++i) {
      try this.send_from_a_to_b(userA, userA, 1 ether) {
      } catch (bytes memory reason) {
        console.log("test_exceeded_daily_user_transfer_attempts(): Error caught: TransferLimitExceeded()");
        bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
        bytes4 receivedSelector = bytes4(reason);
        assertEq(desiredSelector, receivedSelector);
      }
    }
    // after 1 day, the user transfer attempt will be reset
    vm.warp(vm.getBlockTimestamp() + 86401);
    send_from_a_to_b(userA, userA, 10 ether);
    console.log("test_exceeded_daily_user_transfer_attempts(): succeeded after 1 day");
  }

  // @dev simulate an user transfer token with an outbound amount that is too small or too large
  function test_outbound_upper_and_lower_limit() public {
    // amount too small
    try this.send_from_a_to_b(userA, userA, 0.001 ether) {
    } catch (bytes memory reason) {
      console.log("test_outbound_upper_and_lower_limit(): Error caught: TransferLimitExceeded(): Amount too small");
      bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
      bytes4 receivedSelector = bytes4(reason);
      assertEq(desiredSelector, receivedSelector);
    }
    // amount too large
    try this.send_from_a_to_b(userA, userA, 10001 ether) {
    } catch (bytes memory reason) {
      console.log("test_outbound_upper_and_lower_limit(): Error caught: TransferLimitExceeded(): amount too large");
      bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
      bytes4 receivedSelector = bytes4(reason);
      assertEq(desiredSelector, receivedSelector);
    }
  }

  // @dev simulate an user couldn't transfer if the OFT is paused
  function test_pausable() public {
    // 1. not paused initially
    assertEq(oftAdapter.paused(), false);
    // 2. pause it without a multiSig address
    vm.expectRevert("PausableAlt: multiSig not set");
    oftAdapter.pause();
    // 3. set multiSig address
    oftAdapter.setMultiSig(address(0x4321));
    assertEq(oftAdapter.multiSig(), address(0x4321));
    // 4. non multiSig wallet try to pause
    vm.startPrank(address(0x1234));
    vm.expectRevert("PausableAlt: not multiSig");
    oftAdapter.pause();
    vm.stopPrank();
    // 5. only owner can unpause
    vm.startPrank(address(0x1234));
    vm.expectRevert("Ownable: caller is not the owner");
    oftAdapter.unpause();
    vm.stopPrank();
    // 6. pause it
    vm.startPrank(address(0x4321));
    oftAdapter.pause();
    assertEq(oftAdapter.paused(), true);
    vm.stopPrank();
    // 7. transfer revert when paused
    vm.startPrank(userA);
    bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory sendParam = SendParam(bEid, addressToBytes32(userA), 1 ether, 1 ether, opts, "", "");
    MessagingFee memory fee = oftAdapter.quoteSend(sendParam, false);
    aToken.approve(address(oftAdapter), 1 ether);
    vm.expectRevert("Pausable: paused"); // expect "revert: Pausable: paused"
    oftAdapter.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    vm.stopPrank();
    console.log("test_pausable(): transfer revert when paused");
    // 8. transfer success after unpause()
    oftAdapter.unpause();
    assertEq(oftAdapter.paused(), false);
    send_from_a_to_b(userA, userA, 100 ether);
    console.log("test_pausable(): transfer success after unpause()");
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

  // ---- helper functions ----
  function send_from_a_to_b(address from, address to, uint256 amt) public {
    aToken.mint(from, amt);
    vm.startPrank(from);
    bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory sendParam = SendParam(
      bEid,
      addressToBytes32(to),
      amt,
      amt,
      opts,
      "",
      ""
    );
    MessagingFee memory fee = oftAdapter.quoteSend(sendParam, false);
    aToken.approve(address(oftAdapter), amt);
    oftAdapter.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    verifyPackets(bEid, addressToBytes32(address(oftAdapter)));
    vm.stopPrank();
  }

}
