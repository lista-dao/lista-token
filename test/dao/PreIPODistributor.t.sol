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
        // settlement/claim state (mirrors the post-upgrade initializeV2 call)
        distributor.initializeV2();

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
        assertEq(distributor.waitingPeriod(), 6 hours);
    }

    function test_initializeV2_onlyOnce() public {
        vm.expectRevert("Initializable: contract is already initialized");
        distributor.initializeV2();
    }

    function test_managerGrantsBot() public {
        address newBot = makeAddr("newBot");
        bytes32 botRole = distributor.BOT();
        // MANAGER is BOT's role admin, so manager (not default admin) can grant BOT
        vm.prank(manager);
        distributor.grantRole(botRole, newBot);
        assertTrue(distributor.hasRole(botRole, newBot));

        vm.prank(manager);
        distributor.revokeRole(botRole, newBot);
        assertFalse(distributor.hasRole(botRole, newBot));
    }

    function test_defaultAdminCannotGrantBot() public {
        address newBot = makeAddr("newBot");
        bytes32 botRole = distributor.BOT();
        // BOT's admin is MANAGER, so the default admin can no longer grant it
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

    function test_updateSale_afterPublicSet_overlap_reverts() public {
        uint64 saleId = _createDefaultSale(); // WL end = now+1000
        _openPublicRound(saleId);             // pub start = end+10 = now+1010
        // extending WL end past the public start must revert
        vm.prank(manager);
        vm.expectRevert("WL end must precede public");
        distributor.updateSale(saleId, address(usdt), rootWL, block.timestamp + 100, block.timestamp + 1500, 50e18);
    }

    function test_updateSale_afterPublicSet_noOverlap_ok() public {
        uint64 saleId = _createDefaultSale();
        _openPublicRound(saleId); // pub start = now+1010
        // new WL end still before public start -> ok
        vm.prank(manager);
        distributor.updateSale(saleId, address(usdt), rootWL, block.timestamp + 100, block.timestamp + 1005, 50e18);
        assertEq(distributor.getSale(saleId).endTime, block.timestamp + 1005);
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

    // ---- settlement: set / finalize ----

    // create a sale, deposit in WL round, return saleId (totalDeposits = 200e18)
    function _saleWithDeposit() internal returns (uint64 saleId) {
        saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);
        _deposit(alice, saleId, XKLSH, _proofFor(leafBob), 200e18);
        _closeWindows(saleId); // settlement is only allowed once deposit windows close
    }

    function test_setSettlementRoot_ok() public {
        uint64 saleId = _saleWithDeposit();
        bytes32 root = keccak256("settle");

        vm.prank(bot);
        distributor.setSettlementRoot(saleId, root, 50e18);

        // tuple: root, pendingRoot, pendingTotalRefund, totalRefund, lastSetTime, refunded
        (bytes32 fRoot, bytes32 pRoot, uint256 pRefund,, uint256 setTime,) = distributor.settlements(saleId);
        assertEq(fRoot, bytes32(0));
        assertEq(pRoot, root);
        assertEq(pRefund, 50e18);
        assertEq(setTime, block.timestamp);
    }

    function test_setSettlementRoot_refundExceedsDeposits_reverts() public {
        uint64 saleId = _saleWithDeposit(); // 200e18 deposited
        vm.prank(bot);
        vm.expectRevert("Refund exceeds deposits");
        distributor.setSettlementRoot(saleId, keccak256("settle"), 200e18 + 1);
    }

    function test_setSettlementRoot_pendingInFlight_reverts() public {
        uint64 saleId = _saleWithDeposit();
        vm.startPrank(bot);
        distributor.setSettlementRoot(saleId, keccak256("a"), 10e18);
        vm.expectRevert("Pending root in flight");
        distributor.setSettlementRoot(saleId, keccak256("b"), 10e18);
        vm.stopPrank();
    }

    function test_setSettlementRoot_acl() public {
        uint64 saleId = _saleWithDeposit();
        vm.prank(outsider);
        vm.expectRevert();
        distributor.setSettlementRoot(saleId, keccak256("settle"), 10e18);
    }

    function test_finalizeSettlement_beforeWindow_reverts() public {
        uint64 saleId = _saleWithDeposit();
        vm.startPrank(bot);
        distributor.setSettlementRoot(saleId, keccak256("settle"), 50e18);
        vm.expectRevert("Review window not passed");
        distributor.finalizeSettlement(saleId);
        vm.stopPrank();
    }

    function test_finalizeSettlement_ok_after6h() public {
        uint64 saleId = _saleWithDeposit();
        bytes32 root = keccak256("settle");
        vm.prank(bot);
        distributor.setSettlementRoot(saleId, root, 50e18);

        vm.warp(block.timestamp + 6 hours);
        vm.prank(bot);
        distributor.finalizeSettlement(saleId);

        (bytes32 fRoot, bytes32 pRoot, uint256 pRefund, uint256 tRefund,,) = distributor.settlements(saleId);
        assertEq(fRoot, root);
        assertEq(pRoot, bytes32(0));
        assertEq(pRefund, 0);
        assertEq(tRefund, 50e18);
    }

    function test_finalizeSettlement_noPending_reverts() public {
        uint64 saleId = _saleWithDeposit();
        vm.prank(bot);
        vm.expectRevert("No pending root");
        distributor.finalizeSettlement(saleId);
    }

    function test_revokeSettlementRoot_ok() public {
        uint64 saleId = _saleWithDeposit();
        vm.prank(bot);
        distributor.setSettlementRoot(saleId, keccak256("settle"), 50e18);
        vm.prank(manager); // revoke is a MANAGER action
        distributor.revokeSettlementRoot(saleId);
        // can set a fresh one again after revoke
        vm.prank(bot);
        distributor.setSettlementRoot(saleId, keccak256("settle2"), 60e18);

        (, bytes32 pRoot, uint256 pRefund,,,) = distributor.settlements(saleId);
        assertEq(pRoot, keccak256("settle2"));
        assertEq(pRefund, 60e18);
    }

    function test_setWaitingPeriod_min6h() public {
        vm.startPrank(manager);
        vm.expectRevert("Waiting period too short");
        distributor.setWaitingPeriod(6 hours - 1);
        distributor.setWaitingPeriod(12 hours);
        vm.stopPrank();
        assertEq(distributor.waitingPeriod(), 12 hours);
    }

    // settlement must wait until deposit windows close
    function test_setSettlementRoot_beforeWLClose_reverts() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100); // WL open
        _deposit(alice, saleId, XKLSH, _proofFor(leafBob), 200e18);
        vm.prank(bot);
        vm.expectRevert("WL round not ended");
        distributor.setSettlementRoot(saleId, keccak256("r"), 50e18);
    }

    function test_setSettlementRoot_beforePublicClose_reverts() public {
        uint64 saleId = _createDefaultSale();
        _openPublicRound(saleId); // pub [end+10, end+1000]
        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        vm.warp(s.endTime + 1); // WL closed, public not ended
        vm.prank(bot);
        vm.expectRevert("Public round not ended");
        distributor.setSettlementRoot(saleId, keccak256("r"), 0);
    }

    // an active (finalized) root cannot be replaced
    function test_setSettlementRoot_afterFinalize_reverts() public {
        uint64 saleId = _saleWithDeposit();
        _settleAndFinalize(saleId, keccak256("r1"), 50e18);
        vm.prank(bot);
        vm.expectRevert("Already finalized");
        distributor.setSettlementRoot(saleId, keccak256("r2"), 50e18);
    }

    // M02: cannot open a public round once settlement is pending or finalized
    function test_setPublicRound_afterSettlementPending_reverts() public {
        uint64 saleId = _saleWithDeposit(); // WL-only, windows closed
        vm.prank(bot);
        distributor.setSettlementRoot(saleId, keccak256("r"), 50e18);
        uint256 endTime = distributor.getSale(saleId).endTime;
        vm.prank(manager);
        vm.expectRevert("Settlement started");
        distributor.setPublicRound(saleId, endTime + 100, endTime + 200);
    }

    function test_setPublicRound_afterFinalize_reverts() public {
        uint64 saleId = _saleWithDeposit();
        _settleAndFinalize(saleId, keccak256("r"), 50e18);
        uint256 endTime = distributor.getSale(saleId).endTime;
        vm.prank(manager);
        vm.expectRevert("Settlement started");
        distributor.setPublicRound(saleId, endTime + 100, endTime + 200);
    }

    // I03: pause is a real circuit breaker over settlement and claim
    function test_paused_blocksSettlement() public {
        uint64 saleId = _saleWithDeposit();
        vm.prank(manager);
        distributor.setPaused(saleId, true);
        vm.prank(bot);
        vm.expectRevert("Sale paused");
        distributor.setSettlementRoot(saleId, keccak256("r"), 50e18);
    }

    function test_paused_blocksClaim() public {
        uint64 saleId = _saleWithDeposit(); // alice unlocked, 200e18
        MockERC20 share = new MockERC20(admin, "Share", "xKLSH");
        deal(address(share), address(distributor), 10e18);
        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(share), 10e18);
        _settleAndFinalize(saleId, root, 50e18); // finalize while not paused
        vm.prank(manager);
        distributor.setPaused(saleId, true);
        vm.expectRevert("Sale paused");
        distributor.claim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
    }

    // ---- claim ----

    // warp past the deposit window(s) so settlement is allowed
    function _closeWindows(uint64 saleId) internal {
        PreIPODistributor.Sale memory s = distributor.getSale(saleId);
        uint256 closeTime = s.pubStartTime == 0 ? s.endTime : s.pubEndTime;
        if (block.timestamp <= closeTime) vm.warp(closeTime + 1);
    }

    function _settleAndFinalize(uint64 saleId, bytes32 root, uint256 totalRefund) internal {
        _closeWindows(saleId);
        vm.prank(bot);
        distributor.setSettlementRoot(saleId, root, totalRefund);
        vm.warp(block.timestamp + 6 hours);
        vm.prank(bot);
        distributor.finalizeSettlement(saleId);
    }

    // single-leaf settlement tree: root == leaf, proof == []
    function _settleLeaf(uint64 saleId, address account, uint256 refund, address share, uint256 tokenAmount)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(block.chainid, saleId, account, refund, share, tokenAmount));
    }

    function test_claim_unlocked_transfersRefundAndShares() public {
        uint64 saleId = _saleWithDeposit(); // alice: WL 200e18, XKLSH
        MockERC20 share = new MockERC20(admin, "Share", "xKLSH");
        deal(address(share), address(distributor), 10e18);

        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(share), 10e18);
        _settleAndFinalize(saleId, root, 50e18);

        uint256 beforeUsdt = usdt.balanceOf(alice);
        distributor.claim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));

        assertEq(usdt.balanceOf(alice), beforeUsdt + 50e18);
        assertEq(share.balanceOf(alice), 10e18);
        assertTrue(distributor.claimed(saleId, alice));

        // refunded accumulates; outstanding = totalRefund - refunded
        (,,, uint256 tRefund,, uint256 refunded) = distributor.settlements(saleId);
        assertEq(tRefund, 50e18);
        assertEq(refunded, 50e18);
        assertEq(tRefund - refunded, 0);
    }

    function test_claim_locked_registersOnly() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);
        _deposit(alice, saleId, PKLSH, _proofFor(leafBob), 200e18); // alice LOCKED
        MockERC20 share = new MockERC20(admin, "Share", "xKLSH");
        deal(address(share), address(distributor), 10e18);

        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(share), 10e18);
        _settleAndFinalize(saleId, root, 50e18);

        uint256 beforeUsdt = usdt.balanceOf(alice);
        distributor.claim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));

        assertEq(usdt.balanceOf(alice), beforeUsdt + 50e18); // refund paid
        assertEq(share.balanceOf(alice), 0); // shares NOT transferred, only recorded
        assertEq(share.balanceOf(address(distributor)), 10e18);
        assertTrue(distributor.claimed(saleId, alice));
    }

    function test_claim_unlocked_zeroShareToken_reverts() public {
        uint64 saleId = _saleWithDeposit(); // alice XKLSH (unlocked)
        // leaf carries a zero share token for an unlocked user -> invalid
        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(0), 10e18);
        _settleAndFinalize(saleId, root, 50e18);

        vm.expectRevert("Share token required");
        distributor.claim(saleId, alice, 50e18, address(0), 10e18, new bytes32[](0));
    }

    function test_claim_locked_zeroShareToken_ok() public {
        uint64 saleId = _createDefaultSale();
        vm.warp(block.timestamp + 100);
        _deposit(alice, saleId, PKLSH, _proofFor(leafBob), 200e18); // alice LOCKED
        // locked tranche: zero share token is fine (no transfer, only recorded)
        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(0), 10e18);
        _settleAndFinalize(saleId, root, 50e18);

        uint256 beforeUsdt = usdt.balanceOf(alice);
        distributor.claim(saleId, alice, 50e18, address(0), 10e18, new bytes32[](0));
        assertEq(usdt.balanceOf(alice), beforeUsdt + 50e18);
        assertTrue(distributor.claimed(saleId, alice));
    }

    // aggregate refunds cannot exceed the committed total
    function test_claim_refundOverTotal_reverts() public {
        uint64 saleId = _saleWithDeposit();
        MockERC20 share = new MockERC20(admin, "Share", "xKLSH");
        deal(address(share), address(distributor), 10e18);
        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(share), 10e18);
        _settleAndFinalize(saleId, root, 40e18); // totalRefund (40e18) < leaf refund (50e18)
        vm.expectRevert("Refund over total");
        distributor.claim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
    }

    // I13: previewClaim mirrors claim validation/routing without state change
    function test_previewClaim() public {
        uint64 saleId = _saleWithDeposit(); // alice unlocked, 200e18
        MockERC20 share = new MockERC20(admin, "Share", "xKLSH");
        deal(address(share), address(distributor), 10e18);
        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(share), 10e18);

        // before finalize: not valid
        (bool valid0,,,) = distributor.previewClaim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
        assertFalse(valid0);

        _settleAndFinalize(saleId, root, 50e18);

        // valid, not yet claimed, unlocked tranche -> will deliver shares
        (bool valid, bool claimed_, uint8 tranche, bool willDeliver) =
            distributor.previewClaim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
        assertTrue(valid);
        assertFalse(claimed_);
        assertEq(tranche, XKLSH);
        assertTrue(willDeliver);

        // wrong amount -> invalid proof
        (bool validBad,,,) = distributor.previewClaim(saleId, alice, 51e18, address(share), 10e18, new bytes32[](0));
        assertFalse(validBad);

        // after claiming -> alreadyClaimed true
        distributor.claim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
        (, bool claimedAfter,,) = distributor.previewClaim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
        assertTrue(claimedAfter);
    }

    function test_claim_alreadyClaimed_reverts() public {
        uint64 saleId = _saleWithDeposit();
        MockERC20 share = new MockERC20(admin, "Share", "xKLSH");
        deal(address(share), address(distributor), 10e18);
        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(share), 10e18);
        _settleAndFinalize(saleId, root, 50e18);

        distributor.claim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
        vm.expectRevert("Already claimed");
        distributor.claim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
    }

    function test_claim_notFinalized_reverts() public {
        uint64 saleId = _saleWithDeposit();
        MockERC20 share = new MockERC20(admin, "Share", "xKLSH");
        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(share), 10e18);
        vm.prank(bot);
        distributor.setSettlementRoot(saleId, root, 50e18); // pending, not finalized
        vm.expectRevert("Not finalized");
        distributor.claim(saleId, alice, 50e18, address(share), 10e18, new bytes32[](0));
    }

    function test_claim_invalidProof_reverts() public {
        uint64 saleId = _saleWithDeposit();
        MockERC20 share = new MockERC20(admin, "Share", "xKLSH");
        deal(address(share), address(distributor), 10e18);
        bytes32 root = _settleLeaf(saleId, alice, 50e18, address(share), 10e18);
        _settleAndFinalize(saleId, root, 50e18);
        // wrong refund amount -> leaf mismatch
        vm.expectRevert("Invalid proof");
        distributor.claim(saleId, alice, 51e18, address(share), 10e18, new bytes32[](0));
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
