// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/dao/PreIPODistributor.sol";
import "../../contracts/mock/MockERC20.sol";

contract PreIPODistributorTest is Test {
    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    address bot = makeAddr("bot");
    address treasury = makeAddr("treasury");
    address outsider = makeAddr("outsider");

    address alice;
    address bob;
    address carol; // not whitelisted

    PreIPODistributor distributor;
    MockERC20 usdt;

    // whitelist tree over {alice, bob}
    bytes32 rootWL;
    bytes32 leafAlice;
    bytes32 leafBob;

    uint256 constant MIN_DEPOSIT = 100e18;
    uint8 constant XKLSH = 1; // TRANCHE_UNLOCKED
    uint8 constant PKLSH = 2; // TRANCHE_LOCKED

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        usdt = new MockERC20(admin, "Mock USDT", "USDT");

        PreIPODistributor impl = new PreIPODistributor();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(PreIPODistributor.initialize.selector, admin, manager, bot)
        );
        distributor = PreIPODistributor(address(proxy));

        // build whitelist merkle tree (leaf = keccak256(abi.encode(chainid, account)))
        leafAlice = keccak256(abi.encode(block.chainid, alice));
        leafBob = keccak256(abi.encode(block.chainid, bob));
        rootWL = _hashPair(leafAlice, leafBob);

        deal(address(usdt), alice, 1_000_000e18);
        deal(address(usdt), bob, 1_000_000e18);
        deal(address(usdt), carol, 1_000_000e18);
    }

    // ---- helpers ----

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _proofFor(bytes32 sibling) internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = sibling;
    }

    function _createDefaultSale() internal returns (uint64 saleId) {
        vm.prank(manager);
        saleId = distributor.createSale(
            address(usdt),
            rootWL,
            block.timestamp + 100,
            block.timestamp + 1000,
            MIN_DEPOSIT
        );
    }

    // open a public round after WL end (WL end is start(+100)+... => endTime = created+1000)
    function _openPublicRound(uint64 saleId) internal {
        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        vm.prank(manager);
        distributor.setPublicRound(saleId, s.endTime + 10, s.endTime + 1000);
    }

    function _deposit(address who, uint64 saleId, uint8 tranche, bytes32[] memory proof, uint256 amount) internal {
        vm.startPrank(who);
        usdt.approve(address(distributor), amount);
        distributor.depositWhitelist(saleId, tranche, proof, amount);
        vm.stopPrank();
    }

    function _depositPublic(address who, uint64 saleId, uint8 tranche, uint256 amount) internal {
        vm.startPrank(who);
        usdt.approve(address(distributor), amount);
        distributor.depositPublic(saleId, tranche, amount);
        vm.stopPrank();
    }

    // ---- setup / roles ----

    function test_setUp() public view {
        assertEq(distributor.nextSaleId(), 0);
        assertTrue(distributor.hasRole(distributor.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(distributor.hasRole(distributor.MANAGER(), manager));
        assertTrue(distributor.hasRole(distributor.BOT(), bot));
        assertEq(distributor.getRoleAdmin(distributor.BOT()), distributor.MANAGER());
        assertEq(distributor.TRANCHE_UNLOCKED(), XKLSH);
        assertEq(distributor.TRANCHE_LOCKED(), PKLSH);
    }

    function test_managerGrantsBot() public {
        address newBot = makeAddr("newBot");
        bytes32 botRole = distributor.BOT();
        // MANAGER is BOT's role admin, so manager (not the default admin) can grant BOT
        vm.prank(manager);
        distributor.grantRole(botRole, newBot);
        assertTrue(distributor.hasRole(botRole, newBot));
    }

    function test_defaultAdminCannotGrantBot() public {
        address newBot = makeAddr("newBot");
        bytes32 botRole = distributor.BOT();
        vm.prank(admin);
        vm.expectRevert();
        distributor.grantRole(botRole, newBot);
    }

    function test_createSale_ok() public {
        uint64 saleId = _createDefaultSale();
        assertEq(saleId, 0);
        assertEq(distributor.nextSaleId(), 1);

        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        assertEq(s.depositToken, address(usdt));
        assertEq(s.whitelistRoot, rootWL);
        assertEq(s.startTime, block.timestamp + 100);
        assertEq(s.endTime, block.timestamp + 1000);
        assertEq(s.minDeposit, MIN_DEPOSIT);
        assertEq(s.totalDeposits, 0);
        assertEq(s.pubStartTime, 0);
        assertFalse(s.paused);
    }

    function test_createSale_acl() public {
        vm.prank(outsider);
        vm.expectRevert();
        distributor.createSale(address(usdt), rootWL, block.timestamp + 100, block.timestamp + 1000, MIN_DEPOSIT);
    }

    function test_createSale_invalidParams() public {
        vm.startPrank(manager);

        vm.expectRevert("Invalid deposit token");
        distributor.createSale(address(0), rootWL, block.timestamp + 100, block.timestamp + 1000, MIN_DEPOSIT);

        vm.expectRevert("Invalid merkle root");
        distributor.createSale(address(usdt), bytes32(0), block.timestamp + 100, block.timestamp + 1000, MIN_DEPOSIT);

        vm.expectRevert("Invalid start time");
        distributor.createSale(address(usdt), rootWL, block.timestamp, block.timestamp + 1000, MIN_DEPOSIT);

        vm.expectRevert("Invalid end time");
        distributor.createSale(address(usdt), rootWL, block.timestamp + 100, block.timestamp + 100, MIN_DEPOSIT);

        vm.expectRevert("Invalid min deposit");
        distributor.createSale(address(usdt), rootWL, block.timestamp + 100, block.timestamp + 1000, 0);

        vm.stopPrank();
    }

    function test_updateSale_ok() public {
        uint64 saleId = _createDefaultSale();

        bytes32 newRoot = keccak256("new");
        vm.prank(manager);
        distributor.updateSale(saleId, address(usdt), newRoot, block.timestamp + 200, block.timestamp + 2000, 50e18);

        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        assertEq(s.whitelistRoot, newRoot);
        assertEq(s.startTime, block.timestamp + 200);
        assertEq(s.endTime, block.timestamp + 2000);
        assertEq(s.minDeposit, 50e18);
    }

    function test_updateSale_afterStart_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 150); // past start
        vm.prank(manager);
        vm.expectRevert("Sale already started");
        distributor.updateSale(saleId, address(usdt), rootWL, block.timestamp + 200, block.timestamp + 2000, 50e18);
    }

    // ---- whitelist deposit ----

    function test_deposit_ok() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);

        _deposit(alice, saleId, XKLSH, _proofFor(leafBob), 200e18);

        assertEq(distributor.deposits(saleId, alice), 200e18);
        assertEq(distributor.userTranche(saleId, alice), XKLSH);
        assertEq(distributor.getSale(saleId).totalDeposits, 200e18);
        assertEq(usdt.balanceOf(address(distributor)), 200e18);
    }

    function test_deposit_topUp_skipsProof_inheritsTranche() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);

        _deposit(alice, saleId, PKLSH, _proofFor(leafBob), 200e18);
        // top-up with empty proof, passing same tranche
        _deposit(alice, saleId, PKLSH, new bytes32[](0), 300e18);

        assertEq(distributor.deposits(saleId, alice), 500e18);
        assertEq(distributor.userTranche(saleId, alice), PKLSH);
        assertEq(distributor.getSale(saleId).totalDeposits, 500e18);
    }

    function test_deposit_changingTranche_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);

        _deposit(alice, saleId, XKLSH, _proofFor(leafBob), 200e18);

        vm.startPrank(alice);
        usdt.approve(address(distributor), 100e18);
        vm.expectRevert("Tranche locked");
        distributor.depositWhitelist(saleId, PKLSH, new bytes32[](0), 100e18);
        vm.stopPrank();
    }

    function test_deposit_invalidTranche_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);

        vm.startPrank(alice);
        usdt.approve(address(distributor), 200e18);
        vm.expectRevert("Invalid tranche");
        distributor.depositWhitelist(saleId, 0, _proofFor(leafBob), 200e18);
        vm.expectRevert("Invalid tranche");
        distributor.depositWhitelist(saleId, 3, _proofFor(leafBob), 200e18);
        vm.stopPrank();
    }

    function test_deposit_notWhitelisted_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);

        vm.startPrank(carol);
        usdt.approve(address(distributor), 200e18);
        vm.expectRevert("Invalid proof");
        distributor.depositWhitelist(saleId, XKLSH, _proofFor(leafBob), 200e18);
        vm.stopPrank();
    }

    function test_deposit_belowMin_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);

        vm.startPrank(alice);
        usdt.approve(address(distributor), 99e18);
        vm.expectRevert("Below min deposit");
        distributor.depositWhitelist(saleId, XKLSH, _proofFor(leafBob), 99e18);
        vm.stopPrank();
    }

    function test_deposit_beforeStart_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.startPrank(alice);
        usdt.approve(address(distributor), 200e18);
        vm.expectRevert("WL round not active");
        distributor.depositWhitelist(saleId, XKLSH, _proofFor(leafBob), 200e18);
        vm.stopPrank();
    }

    function test_deposit_afterEnd_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 1001);
        vm.startPrank(alice);
        usdt.approve(address(distributor), 200e18);
        vm.expectRevert("WL round not active");
        distributor.depositWhitelist(saleId, XKLSH, _proofFor(leafBob), 200e18);
        vm.stopPrank();
    }

    function test_deposit_whenPaused_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.prank(manager);
        distributor.setPaused(saleId, true);

        vm.warp(block.timestamp + 100);
        vm.startPrank(alice);
        usdt.approve(address(distributor), 200e18);
        vm.expectRevert("Sale paused");
        distributor.depositWhitelist(saleId, XKLSH, _proofFor(leafBob), 200e18);
        vm.stopPrank();
    }

    function test_deposit_invalidSaleId_reverts() public {
        vm.warp(block.timestamp + 100);
        vm.startPrank(alice);
        usdt.approve(address(distributor), 200e18);
        vm.expectRevert("Invalid saleId");
        distributor.depositWhitelist(0, XKLSH, _proofFor(leafBob), 200e18);
        vm.stopPrank();
    }

    // ---- public round ----

    function test_setPublicRound_ok() public {
        uint64 saleId = _createDefaultSale();
        _openPublicRound(saleId);
        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        assertEq(s.pubStartTime, s.endTime + 10);
        assertEq(s.pubEndTime, s.endTime + 1000);
    }

    function test_setPublicRound_mustFollowWL_reverts() public {
        uint64 saleId = _createDefaultSale();
        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        vm.prank(manager);
        vm.expectRevert("Public must follow WL");
        distributor.setPublicRound(saleId, s.endTime, s.endTime + 100); // not strictly after WL end
    }

    function test_setPublicRound_acl() public {
        uint64 saleId = _createDefaultSale();
        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        vm.prank(outsider);
        vm.expectRevert();
        distributor.setPublicRound(saleId, s.endTime + 10, s.endTime + 100);
    }

    function test_depositPublic_ok_openToAll() public {
        uint64 saleId = _createDefaultSale();
        _openPublicRound(saleId);
        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        vm.warp(s.pubStartTime);

        // carol is NOT whitelisted, but public round is open to everyone
        _depositPublic(carol, saleId, XKLSH, 250e18);

        assertEq(distributor.pubDeposits(saleId, carol), 250e18);
        assertEq(distributor.userTranche(saleId, carol), XKLSH);
        assertEq(distributor.getSale(saleId).pubTotalDeposits, 250e18);
        assertEq(distributor.getSale(saleId).totalDeposits, 0); // WL pool untouched
    }

    function test_depositPublic_beforeSet_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.startPrank(carol);
        usdt.approve(address(distributor), 250e18);
        vm.expectRevert("Public round not set");
        distributor.depositPublic(saleId, XKLSH, 250e18);
        vm.stopPrank();
    }

    function test_depositPublic_outsideWindow_reverts() public {
        uint64 saleId = _createDefaultSale();
        _openPublicRound(saleId);
        // still in WL window, public not started
        vm.startPrank(carol);
        usdt.approve(address(distributor), 250e18);
        vm.expectRevert("Public round not active");
        distributor.depositPublic(saleId, XKLSH, 250e18);
        vm.stopPrank();
    }

    function test_tranche_lockedAcrossRounds() public {
        uint64 saleId = _createDefaultSale();
        _openPublicRound(saleId);

        // WL round: alice picks PKLSH
        vm.warp(block.timestamp + 100);
        _deposit(alice, saleId, PKLSH, _proofFor(leafBob), 200e18);

        // Public round: alice tries XKLSH -> must inherit PKLSH
        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        vm.warp(s.pubStartTime);
        vm.startPrank(alice);
        usdt.approve(address(distributor), 100e18);
        vm.expectRevert("Tranche locked");
        distributor.depositPublic(saleId, XKLSH, 100e18);
        // same tranche works
        distributor.depositPublic(saleId, PKLSH, 100e18);
        vm.stopPrank();

        assertEq(distributor.pubDeposits(saleId, alice), 100e18);
        assertEq(distributor.deposits(saleId, alice), 200e18);
        assertEq(distributor.userTranche(saleId, alice), PKLSH);
    }

    // ---- emergency withdraw ----

    function test_emergencyWithdraw_ok() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);
        _deposit(alice, saleId, XKLSH, _proofFor(leafBob), 200e18);

        vm.prank(manager);
        distributor.emergencyWithdraw(address(usdt), treasury, 200e18);
        assertEq(usdt.balanceOf(treasury), 200e18);
        assertEq(usdt.balanceOf(address(distributor)), 0);
    }

    function test_emergencyWithdraw_acl() public {
        vm.prank(outsider);
        vm.expectRevert();
        distributor.emergencyWithdraw(address(usdt), treasury, 1e18);
    }

    // ---- upgrade ----

    function test_upgrade_onlyAdmin() public {
        PreIPODistributor newImpl = new PreIPODistributor();

        vm.prank(outsider);
        vm.expectRevert();
        distributor.upgradeTo(address(newImpl));

        vm.prank(admin);
        distributor.upgradeTo(address(newImpl));
    }
}
