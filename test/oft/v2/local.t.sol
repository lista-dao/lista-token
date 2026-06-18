// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Mock imports
import { ERC20Mock } from "../tools/mocks/ERC20Mock.sol";

// v2 contracts under test
import { ListaOFTAdapterV2 } from "../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { ListaOFTv2 } from "../../../contracts/oft/v2/ListaOFTv2.sol";
import { TransferLimiterV2 } from "../../../contracts/oft/v2/TransferLimiterV2.sol";

// OApp / OFT imports (v2 oft-evm types — must match the contracts' send() signature)
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

// OZ imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Forge imports
import "forge-std/console.sol";

// DevTools imports
import { TestHelperOz5 } from "../tools/TestHelperOz5.sol";

/**
 * @title ListaOFTV2LocalTest
 * @notice End-to-end local simulation of the upgradeable Lista OFT mesh using
 *         two mock LayerZero endpoints:
 *           Chain A (eid 1): canonical LISTA (ERC20Mock) + ListaOFTAdapterV2 (lock/unlock)
 *           Chain B (eid 2): ListaOFTv2 (mint/burn)
 *         Mirrors the BSC <> ETH bridge behaviour.
 */
contract ListaOFTV2LocalTest is TestHelperOz5, TransferLimiterV2 {
  using OptionsBuilder for bytes;

  uint32 aEid = 1;
  uint32 bEid = 2;

  // Chain A
  ERC20Mock aToken;
  ListaOFTAdapterV2 oftAdapter;
  // Chain B
  ListaOFTv2 bToken;

  // roles
  address public admin = address(this);
  address public manager = address(this);
  address public pauser = address(0x9111);

  address public userA = address(0x1);
  address public userB = address(0x2);
  uint256 public initialBalance = 10000000 ether;

  bytes32 public constant PAUSER = keccak256("PAUSER");
  bytes32 public constant MANAGER = keccak256("MANAGER");

  function setUp() public virtual override {
    vm.deal(userA, 1000 ether);
    vm.deal(userB, 1000 ether);

    super.setUp();
    setUpEndpoints(2, LibraryType.UltraLightNode);

    aToken = new ERC20Mock("Lista DAO", "LISTA");
    aToken.mint(userA, initialBalance);

    /**
      Max. amt. transferable per day                : 100,000
      Max. amt. per transfer                        : 10,000
      Min. amt. per transfer                        : 0.1
      Max. daily amt. per address                   : 20,000
      Max. transfer attempts per address per day    : 10
    */
    TransferLimit[] memory tla = new TransferLimit[](1);
    tla[0] = TransferLimit(bEid, 100000 ether, 10000 ether, 0.1 ether, 20000 ether, 10);
    TransferLimit[] memory tlb = new TransferLimit[](1);
    tlb[0] = TransferLimit(aEid, 100000 ether, 10000 ether, 0.1 ether, 20000 ether, 10);

    // deploy adapter behind a UUPS proxy on chain A
    ListaOFTAdapterV2 adapterImpl = new ListaOFTAdapterV2(address(aToken), address(endpoints[aEid]));
    oftAdapter = ListaOFTAdapterV2(
      address(
        new ERC1967Proxy(
          address(adapterImpl),
          abi.encodeCall(ListaOFTAdapterV2.initialize, (admin, manager, pauser, tla))
        )
      )
    );

    // deploy oft behind a UUPS proxy on chain B
    ListaOFTv2 oftImpl = new ListaOFTv2(address(endpoints[bEid]));
    bToken = ListaOFTv2(
      address(
        new ERC1967Proxy(
          address(oftImpl),
          abi.encodeCall(ListaOFTv2.initialize, ("Lista DAO", "LISTA", admin, manager, pauser, tlb))
        )
      )
    );

    // wire peers (manager == this)
    oftAdapter.setPeer(bEid, addressToBytes32(address(bToken)));
    bToken.setPeer(aEid, addressToBytes32(address(oftAdapter)));
  }

  // ----------------------------------------------------------------------
  // basic wiring
  // ----------------------------------------------------------------------
  function test_constructor() public {
    assertEq(oftAdapter.owner(), admin);
    assertEq(bToken.owner(), admin);
    assertEq(oftAdapter.token(), address(aToken));
    assertEq(bToken.token(), address(bToken));
    assertTrue(oftAdapter.hasRole(MANAGER, manager));
    assertTrue(oftAdapter.hasRole(PAUSER, pauser));
    assertTrue(oftAdapter.approvalRequired());
    assertFalse(bToken.approvalRequired());
    assertEq(aToken.balanceOf(userA), initialBalance);
    assertEq(bToken.balanceOf(userB), 0);
  }

  // ----------------------------------------------------------------------
  // bridge: lock @ A -> mint @ B -> burn @ B -> unlock @ A
  // ----------------------------------------------------------------------
  function test_send_back_and_forth() public {
    uint256 tokensToSend = 1 ether;

    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory aSendParam = SendParam(
      bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", ""
    );
    MessagingFee memory aFee = oftAdapter.quoteSend(aSendParam, false);

    vm.startPrank(userA);
    aToken.approve(address(oftAdapter), tokensToSend);
    oftAdapter.send{ value: aFee.nativeFee }(aSendParam, aFee, payable(address(this)));
    vm.stopPrank();
    verifyPackets(bEid, addressToBytes32(address(bToken)));

    // locked on A, minted on B
    assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
    assertEq(aToken.balanceOf(address(oftAdapter)), tokensToSend);
    assertEq(bToken.balanceOf(userB), tokensToSend);

    // send back B -> A
    bytes memory bOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory bSendParam = SendParam(
      aEid, addressToBytes32(userA), tokensToSend, tokensToSend, bOptions, "", ""
    );
    MessagingFee memory bFee = bToken.quoteSend(bSendParam, false);

    vm.prank(userB);
    bToken.send{ value: bFee.nativeFee }(bSendParam, bFee, payable(address(this)));
    verifyPackets(aEid, addressToBytes32(address(oftAdapter)));

    // burned on B, unlocked on A
    assertEq(bToken.balanceOf(userB), 0);
    assertEq(aToken.balanceOf(userA), initialBalance);
    assertEq(aToken.balanceOf(address(oftAdapter)), 0);
  }

  // ----------------------------------------------------------------------
  // transfer limiter
  // ----------------------------------------------------------------------
  function test_outbound_upper_and_lower_limit() public {
    vm.expectRevert(TransferLimiterV2.TransferLimitExceeded.selector);
    this.send_from_a_to_b(userA, 0.001 ether);
    vm.expectRevert(TransferLimiterV2.TransferLimitExceeded.selector);
    this.send_from_a_to_b(userA, 10001 ether);
  }

  function test_exceeded_daily_user_transfer_limit() public {
    this.send_from_a_to_b(userA, 10000 ether);
    vm.expectRevert(TransferLimiterV2.TransferLimitExceeded.selector);
    this.send_from_a_to_b(userA, 10001 ether); // would push user over 20,000/day
    vm.warp(vm.getBlockTimestamp() + 86401);
    this.send_from_a_to_b(userA, 10 ether); // resets after a day
  }

  function test_setTransferLimitConfigs_onlyManager() public {
    TransferLimit[] memory t = new TransferLimit[](1);
    t[0] = TransferLimit(bEid, 1 ether, 0.5 ether, 0.01 ether, 0.6 ether, 5);
    vm.prank(userA);
    vm.expectRevert();
    oftAdapter.setTransferLimitConfigs(t);
    // manager can
    oftAdapter.setTransferLimitConfigs(t);
  }

  // ----------------------------------------------------------------------
  // pause control
  // ----------------------------------------------------------------------
  function test_pausable() public {
    // only PAUSER can pause
    vm.prank(userA);
    vm.expectRevert();
    oftAdapter.pause();

    vm.prank(pauser);
    oftAdapter.pause();
    assertTrue(oftAdapter.paused());

    // transfer reverts while paused
    bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory sp = SendParam(bEid, addressToBytes32(userA), 1 ether, 1 ether, opts, "", "");
    MessagingFee memory fee = oftAdapter.quoteSend(sp, false);
    vm.startPrank(userA);
    aToken.approve(address(oftAdapter), 1 ether);
    vm.expectRevert(bytes("Pausable: paused"));
    oftAdapter.send{ value: fee.nativeFee }(sp, fee, payable(address(this)));
    vm.stopPrank();

    // PAUSER cannot unpause; MANAGER can
    vm.prank(pauser);
    vm.expectRevert();
    oftAdapter.unpause();
    oftAdapter.unpause(); // manager == this
    assertFalse(oftAdapter.paused());

    this.send_from_a_to_b(userA, 100 ether);
  }

  // ----------------------------------------------------------------------
  // OApp config gated to MANAGER
  // ----------------------------------------------------------------------
  function test_setPeer_onlyManager() public {
    vm.prank(userA);
    vm.expectRevert();
    oftAdapter.setPeer(bEid, addressToBytes32(address(0xdead)));
    // manager can
    oftAdapter.setPeer(99, addressToBytes32(address(0xbeef)));
    assertEq(oftAdapter.peers(99), addressToBytes32(address(0xbeef)));
  }

  // ----------------------------------------------------------------------
  // upgrade gated to DEFAULT_ADMIN_ROLE
  // ----------------------------------------------------------------------
  function test_upgrade_onlyAdmin() public {
    ListaOFTAdapterV2 newImpl = new ListaOFTAdapterV2(address(aToken), address(endpoints[aEid]));
    // non-admin cannot upgrade
    vm.prank(userA);
    vm.expectRevert();
    oftAdapter.upgradeTo(address(newImpl));
    // admin (this) can
    oftAdapter.upgradeTo(address(newImpl));
  }

  // ----------------------------------------------------------------------
  // EIP-2612 permit on the OFT
  // ----------------------------------------------------------------------
  function test_permit() public {
    uint256 pk = 0xA11CE;
    address owner = vm.addr(pk);
    // mint by bridging in
    this.send_from_a_to_b_to(userA, owner, 100 ether);

    uint256 value = 10 ether;
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 structHash = keccak256(
      abi.encode(
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
        owner, userB, value, bToken.nonces(owner), deadline
      )
    );
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", bToken.DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
    bToken.permit(owner, userB, value, deadline, v, r, s);
    assertEq(bToken.allowance(owner, userB), value);
  }

  // ---- helpers ----
  function send_from_a_to_b(address from, uint256 amt) public {
    send_from_a_to_b_to(from, from, amt);
  }

  function send_from_a_to_b_to(address from, address to, uint256 amt) public {
    aToken.mint(from, amt);
    vm.startPrank(from);
    bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory sendParam = SendParam(bEid, addressToBytes32(to), amt, amt, opts, "", "");
    MessagingFee memory fee = oftAdapter.quoteSend(sendParam, false);
    aToken.approve(address(oftAdapter), amt);
    oftAdapter.send{ value: fee.nativeFee }(sendParam, fee, payable(from));
    vm.stopPrank();
    verifyPackets(bEid, addressToBytes32(address(bToken)));
  }
}
