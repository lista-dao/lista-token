// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import "forge-std/console.sol";

import { ListaOFTAdapterV2 } from "../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { TransferLimiterV2 } from "../../../contracts/oft/v2/TransferLimiterV2.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev Test-only harness exposing the internal OFT debit/credit hooks so the
 *      lock/unlock custody mechanics can be driven deterministically against the
 *      real LISTA token on a BSC fork (the full LayerZero message routing is
 *      already covered end-to-end in test/oft/v2/local.t.sol).
 */
contract ListaOFTAdapterV2Harness is ListaOFTAdapterV2 {
  constructor(address _token, address _lzEndpoint) ListaOFTAdapterV2(_token, _lzEndpoint) {}

  function debitPublic(
    address _from,
    uint256 _amountLD,
    uint32 _dstEid
  ) external returns (uint256 sent, uint256 received) {
    return _debit(_from, _amountLD, _amountLD, _dstEid);
  }

  function creditPublic(address _to, uint256 _amountLD, uint32 _srcEid) external returns (uint256) {
    return _credit(_to, _amountLD, _srcEid);
  }
}

/**
 * @title ListaOFTV2ForkTest
 * @notice Forks BNB Chain mainnet and exercises ListaOFTAdapterV2 against the
 *         REAL canonical LISTA token and the REAL LayerZero V2 endpoint:
 *           - initialize() succeeds (endpoint.setDelegate on the live endpoint)
 *           - locking real LISTA on debit, unlocking on credit
 *           - transfer limiter + pause guard apply to the real token
 *           - DEFAULT_ADMIN_ROLE-gated UUPS upgrade
 *
 *         Self-forks via the `bsc` rpc alias; skips if no fork is available.
 */
contract ListaOFTV2ForkTest is Test {
  // Mainnet canonical LISTA on BNB Chain
  address constant LISTA_BSC = 0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46;
  // Mainnet LayerZero V2 endpoint on BNB Chain
  address constant LZ_ENDPOINT_BSC = 0x1a44076050125825900e736c501f859c50fE728c;
  // Mainnet ETH destination eid
  uint32 constant ETH_EID = 30101;

  IERC20Metadata lista;
  ListaOFTAdapterV2Harness adapter;

  address admin = address(this);
  address manager = address(this);
  address pauser = address(0x9111);
  address userA = address(0xA11CE);

  bool forked;

  function setUp() public {
    try this.fork() {
      forked = LISTA_BSC.code.length > 0 && LZ_ENDPOINT_BSC.code.length > 0;
    } catch {
      forked = false;
    }
    if (!forked) return;

    lista = IERC20Metadata(LISTA_BSC);

    TransferLimiterV2.TransferLimit[] memory tl = new TransferLimiterV2.TransferLimit[](1);
    tl[0] = TransferLimiterV2.TransferLimit(ETH_EID, 100000 ether, 10000 ether, 0.1 ether, 20000 ether, 10);

    ListaOFTAdapterV2Harness impl = new ListaOFTAdapterV2Harness(LISTA_BSC, LZ_ENDPOINT_BSC);
    adapter = ListaOFTAdapterV2Harness(
      address(
        new ERC1967Proxy(
          address(impl),
          abi.encodeCall(ListaOFTAdapterV2.initialize, (admin, manager, pauser, tl))
        )
      )
    );
  }

  function fork() external {
    vm.createSelectFork("bsc");
  }

  modifier onlyForked() {
    if (!forked) {
      console.log("SKIP: no BSC fork (configure the `bsc` rpc endpoint)");
      return;
    }
    _;
  }

  function test_fork_initialize_realEndpoint() public onlyForked {
    assertEq(adapter.token(), LISTA_BSC);
    assertEq(lista.decimals(), 18);
    assertEq(adapter.owner(), admin);
    assertTrue(adapter.hasRole(adapter.MANAGER_ROLE(), manager));
    assertTrue(adapter.hasRole(adapter.PAUSER_ROLE(), pauser));
    assertTrue(adapter.approvalRequired());
    console.log("Real LISTA symbol:", lista.symbol());
  }

  // @dev lock real LISTA on debit, then unlock on credit
  function test_fork_lock_and_unlock_realToken() public onlyForked {
    uint256 amount = 100 ether;
    deal(LISTA_BSC, userA, amount, true);
    assertEq(lista.balanceOf(userA), amount);

    // user approves + adapter locks (debit) the real token
    vm.prank(userA);
    lista.approve(address(adapter), amount);
    adapter.debitPublic(userA, amount, ETH_EID);

    assertEq(lista.balanceOf(userA), 0);
    assertEq(lista.balanceOf(address(adapter)), amount);

    // adapter unlocks (credit) the real token back
    adapter.creditPublic(userA, amount, ETH_EID);
    assertEq(lista.balanceOf(userA), amount);
    assertEq(lista.balanceOf(address(adapter)), 0);
    console.log("Fork lock+unlock OK on real LISTA:", amount);
  }

  function test_fork_transferLimiter_realToken() public onlyForked {
    deal(LISTA_BSC, userA, 1_000_000 ether, true);
    vm.prank(userA);
    lista.approve(address(adapter), type(uint256).max);

    // above single-transfer upper limit (10,000) reverts
    vm.expectRevert(TransferLimiterV2.TransferLimitExceeded.selector);
    adapter.debitPublic(userA, 10001 ether, ETH_EID);

    // below single-transfer lower limit (0.1) reverts
    vm.expectRevert(TransferLimiterV2.TransferLimitExceeded.selector);
    adapter.debitPublic(userA, 0.001 ether, ETH_EID);
  }

  function test_fork_pause_blocksLock() public onlyForked {
    deal(LISTA_BSC, userA, 100 ether, true);
    vm.prank(userA);
    lista.approve(address(adapter), type(uint256).max);

    vm.prank(pauser);
    adapter.pause();

    vm.expectRevert(bytes("Pausable: paused"));
    adapter.debitPublic(userA, 1 ether, ETH_EID);

    adapter.unpause(); // manager == this
    adapter.debitPublic(userA, 1 ether, ETH_EID); // succeeds after unpause
    assertEq(lista.balanceOf(address(adapter)), 1 ether);
  }

  function test_fork_upgrade_onlyAdmin() public onlyForked {
    ListaOFTAdapterV2Harness newImpl = new ListaOFTAdapterV2Harness(LISTA_BSC, LZ_ENDPOINT_BSC);
    vm.prank(userA);
    vm.expectRevert();
    adapter.upgradeTo(address(newImpl));
    adapter.upgradeTo(address(newImpl)); // admin == this
  }
}
