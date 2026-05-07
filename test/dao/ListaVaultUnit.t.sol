// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/dao/ListaVault.sol";
import "../../contracts/dao/interfaces/IDistributor.sol";

contract MockVeListaForVault {
    uint16 public currentWeek;
    function getCurrentWeek() external view returns (uint16) { return currentWeek; }
    function startTime() external pure returns (uint256) { return 1; }
    function getWeek(uint256) external view returns (uint16) { return currentWeek; }
    function setCurrentWeek(uint16 _w) external { currentWeek = _w; }
}

contract MockEmissionVoting {
    mapping(uint16 => uint256) public weeklyTotalWeight;
    mapping(uint16 => mapping(uint16 => uint256)) public distributorWeight;
    function getWeeklyTotalWeight(uint16 week) external view returns (uint256) {
        return weeklyTotalWeight[week];
    }
    function getDistributorWeeklyTotalWeight(uint16 id, uint16 week) external view returns (uint256) {
        return distributorWeight[id][week];
    }
    function setWeights(uint16 week, uint256 total, uint16 id1, uint256 w1, uint16 id2, uint256 w2) external {
        weeklyTotalWeight[week] = total;
        distributorWeight[id1][week] = w1;
        distributorWeight[id2][week] = w2;
    }
}

contract MockUnitDistributor is IDistributor {
    function vaultClaimReward(address) external pure returns (uint256) { return 0; }
    function vaultClaimStakingReward(address) external pure returns (uint256) { return 0; }
    function notifyRegisteredId(uint16) external pure returns (bool) { return true; }
    function claimableReward(address) external pure returns (uint256) { return 0; }
    function notifyStakingReward(uint256) external {}
    function lpToken() external pure returns (address) { return address(0); }
}

// Minimal ERC20 with public mint — avoids the existing MockERC20's onlyMinter gate.
contract TestToken {
    string public name = "TestLISTA";
    string public symbol = "TLISTA";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external { balanceOf[to] += amt; totalSupply += amt; }
    function approve(address sp, uint256 amt) external returns (bool) { allowance[msg.sender][sp] = amt; return true; }
    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt; balanceOf[to] += amt; return true;
    }
    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amt;
        balanceOf[from] -= amt; balanceOf[to] += amt; return true;
    }
}

contract ListaVaultUnitTest is Test {
    ListaVault vault;
    TestToken lista;
    MockVeListaForVault veLista;
    MockEmissionVoting emissionVoting;
    MockUnitDistributor d1;
    MockUnitDistributor d2;

    address admin    = makeAddr("admin");
    address manager  = makeAddr("manager");
    address operator = makeAddr("operator");
    address attacker = makeAddr("attacker");

    uint16 id1;
    uint16 id2;

    uint16 constant CURRENT_WEEK = 10;
    uint16 constant NEXT_WEEK = 11;

    function setUp() public {
        lista = new TestToken();
        veLista = new MockVeListaForVault();
        veLista.setCurrentWeek(CURRENT_WEEK);
        emissionVoting = new MockEmissionVoting();

        ListaVault impl = new ListaVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(ListaVault.initialize, (admin, manager, address(lista), address(veLista)))
        );
        vault = ListaVault(address(proxy));

        vm.startPrank(admin);
        vault.grantRole(vault.OPERATOR(), operator);
        vm.stopPrank();

        d1 = new MockUnitDistributor();
        d2 = new MockUnitDistributor();
        vm.startPrank(manager);
        id1 = vault.registerDistributor(address(d1));
        id2 = vault.registerDistributor(address(d2));
        vm.stopPrank();

        // fund 1000 LISTA emissions for NEXT_WEEK
        lista.mint(operator, 1000e18);
        vm.startPrank(operator);
        lista.approve(address(vault), type(uint256).max);
        vault.depositRewards(1000e18, NEXT_WEEK);
        vm.stopPrank();
    }

    // ---------- access control ----------

    function test_batchSetDistributorBlacklist_revertsForNonManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.batchSetDistributorBlacklist(_one(id1), true);
    }

    function test_batchSetDistributorBlacklist_revertsForAdminWithoutManager() public {
        // admin has DEFAULT_ADMIN_ROLE only, not MANAGER
        vm.prank(admin);
        vm.expectRevert();
        vault.batchSetDistributorBlacklist(_one(id1), true);
    }

    function test_batchSetDistributorBlacklist_managerSucceeds() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit ListaVault.DistributorBlacklistUpdated(id1, true);
        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);
        assertTrue(vault.distributorBlacklist(id1));
    }

    function test_batchSetDistributorBlacklist_appliesToAllIds() public {
        uint16[] memory ids = new uint16[](2);
        ids[0] = id1;
        ids[1] = id2;
        vm.prank(manager);
        vault.batchSetDistributorBlacklist(ids, true);
        assertTrue(vault.distributorBlacklist(id1));
        assertTrue(vault.distributorBlacklist(id2));
    }

    function test_batchSetDistributorBlacklist_partialNoOpEmitsOnlyForChanged() public {
        // pre-blacklist id1 → only id2 should change in the next batch
        vm.startPrank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);

        uint16[] memory ids = new uint16[](2);
        ids[0] = id1; // already true → silent
        ids[1] = id2; // false → true → event

        vm.recordLogs();
        vault.batchSetDistributorBlacklist(ids, true);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // exactly one DistributorBlacklistUpdated event in this call
        bytes32 sig = keccak256("DistributorBlacklistUpdated(uint16,bool)");
        uint256 hits;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) hits++;
        }
        assertEq(hits, 1, "expected exactly 1 event for the changed id");
        assertTrue(vault.distributorBlacklist(id1));
        assertTrue(vault.distributorBlacklist(id2));
    }

    // ---------- validation ----------

    function test_batchSetDistributorBlacklist_revertsOnEmptyArray() public {
        uint16[] memory ids = new uint16[](0);
        vm.prank(manager);
        vm.expectRevert("ids is empty");
        vault.batchSetDistributorBlacklist(ids, true);
    }

    function test_batchSetDistributorBlacklist_revertsOnUnregisteredId() public {
        uint16 unregistered = vault.distributorId() + 1;
        vm.prank(manager);
        vm.expectRevert("distributor not registered");
        vault.batchSetDistributorBlacklist(_one(unregistered), true);
    }

    function test_batchSetDistributorBlacklist_revertsOnZeroId() public {
        vm.prank(manager);
        vm.expectRevert("distributor not registered");
        vault.batchSetDistributorBlacklist(_one(0), true);
    }

    function test_batchSetDistributorBlacklist_skipsNoOpsSilently() public {
        // ids already in target state are skipped — no revert
        vm.startPrank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), false); // already false → silent
        assertFalse(vault.distributorBlacklist(id1));

        vault.batchSetDistributorBlacklist(_one(id1), true);
        vault.batchSetDistributorBlacklist(_one(id1), true);  // already true → silent
        assertTrue(vault.distributorBlacklist(id1));
        vm.stopPrank();
    }

    function test_batchSetDistributorBlacklist_toggleEmitsEachStateChange() public {
        vm.startPrank(manager);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ListaVault.DistributorBlacklistUpdated(id1, true);
        vault.batchSetDistributorBlacklist(_one(id1), true);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ListaVault.DistributorBlacklistUpdated(id1, false);
        vault.batchSetDistributorBlacklist(_one(id1), false);

        vm.stopPrank();
        assertFalse(vault.distributorBlacklist(id1));
    }

    // ---------- gate: setWeeklyDistributorPercent ----------

    function test_setWeeklyDistributorPercent_revertsIfAnyIdBlacklisted() public {
        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id2), true);

        uint16[] memory ids = new uint16[](2);
        uint256[] memory pct = new uint256[](2);
        ids[0] = id1; pct[0] = 4e17;
        ids[1] = id2; pct[1] = 6e17;

        vm.prank(operator);
        vm.expectRevert("distributor blacklisted");
        vault.setWeeklyDistributorPercent(NEXT_WEEK, ids, pct);
    }

    function test_setWeeklyDistributorPercent_revertsOnFirstBlacklisted() public {
        // blacklist id1 — first iteration must revert before id2 is checked
        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);

        uint16[] memory ids = new uint16[](2);
        uint256[] memory pct = new uint256[](2);
        ids[0] = id1; pct[0] = 4e17;
        ids[1] = id2; pct[1] = 6e17;

        vm.prank(operator);
        vm.expectRevert("distributor blacklisted");
        vault.setWeeklyDistributorPercent(NEXT_WEEK, ids, pct);
    }

    function test_setWeeklyDistributorPercent_succeedsAfterUnblacklist() public {
        vm.startPrank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);
        vault.batchSetDistributorBlacklist(_one(id1), false);
        vm.stopPrank();

        uint16[] memory ids = new uint16[](1);
        uint256[] memory pct = new uint256[](1);
        ids[0] = id1; pct[0] = 5e17;

        vm.prank(operator);
        vault.setWeeklyDistributorPercent(NEXT_WEEK, ids, pct);
        assertEq(vault.weeklyDistributorPercent(NEXT_WEEK, id1), 5e17);
    }

    // ---------- gate: getDistributorWeeklyEmissions, no emissionVoting ----------

    function test_getDistributorWeeklyEmissions_zeroForBlacklistedNoVoting() public {
        _setPercents(id1, 4e17, id2, 6e17);

        // sanity before blacklist
        assertEq(vault.getDistributorWeeklyEmissions(id1, NEXT_WEEK), 400e18);
        assertEq(vault.getDistributorWeeklyEmissions(id2, NEXT_WEEK), 600e18);

        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);

        assertEq(vault.getDistributorWeeklyEmissions(id1, NEXT_WEEK), 0);
        // d2's share is unchanged — leftover stays in vault
        assertEq(vault.getDistributorWeeklyEmissions(id2, NEXT_WEEK), 600e18);
    }

    // ---------- gate: getDistributorWeeklyEmissions, voting set + percent override ----------

    function test_getDistributorWeeklyEmissions_zeroForBlacklistedWithPercentOverride() public {
        // emissionVoting set, but operator also set percents — override path
        vm.prank(admin);
        vault.setEmissionVoting(address(emissionVoting));
        _setPercents(id1, 4e17, id2, 6e17);
        // weights set so we can prove blacklist takes priority over voting too
        emissionVoting.setWeights(NEXT_WEEK, 1000, id1, 500, id2, 500);

        // override path active (weeklyDistributorPercent[NEXT_WEEK][0] == 1)
        // d1 should still receive percent-based amount
        assertEq(vault.getDistributorWeeklyEmissions(id1, NEXT_WEEK), 400e18);

        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);

        assertEq(vault.getDistributorWeeklyEmissions(id1, NEXT_WEEK), 0);
    }

    // ---------- gate: getDistributorWeeklyEmissions, voting path ----------

    function test_getDistributorWeeklyEmissions_zeroForBlacklistedInVotingPath() public {
        vm.prank(admin);
        vault.setEmissionVoting(address(emissionVoting));
        // do NOT call setWeeklyDistributorPercent — voting path is active
        emissionVoting.setWeights(NEXT_WEEK, 1000, id1, 400, id2, 600);

        // sanity: voting path returns weight-proportional amount
        assertEq(vault.getDistributorWeeklyEmissions(id1, NEXT_WEEK), 400e18);
        assertEq(vault.getDistributorWeeklyEmissions(id2, NEXT_WEEK), 600e18);

        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);

        assertEq(vault.getDistributorWeeklyEmissions(id1, NEXT_WEEK), 0);
        assertEq(vault.getDistributorWeeklyEmissions(id2, NEXT_WEEK), 600e18);
    }

    // ---------- downstream: allocateNewEmissions ----------

    function test_allocateNewEmissions_zeroForBlacklisted() public {
        _setPercents(id1, 1e18, id2, 0); // d1 gets 100%

        // advance to NEXT_WEEK so allocate has something to credit
        veLista.setCurrentWeek(NEXT_WEEK);

        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);

        vm.prank(address(d1));
        uint256 got = vault.allocateNewEmissions(id1);
        assertEq(got, 0);
        assertEq(vault.allocated(address(d1)), 0);
    }

    function test_allocateNewEmissions_unblacklistRestoresFutureFlow() public {
        _setPercents(id1, 1e18, id2, 0);

        // week W+1: blacklist active; advance and allocate → 0
        veLista.setCurrentWeek(NEXT_WEEK);
        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), true);
        vm.prank(address(d1));
        assertEq(vault.allocateNewEmissions(id1), 0);

        // unblacklist — but distributorUpdatedWeek already moved to NEXT_WEEK, so
        // already-skipped emissions stay skipped (intended: blacklist at allocate
        // time wins). Future weeks would flow normally; this test just confirms
        // the state machine doesn't double-credit retroactively.
        vm.prank(manager);
        vault.batchSetDistributorBlacklist(_one(id1), false);
        vm.prank(address(d1));
        assertEq(vault.allocateNewEmissions(id1), 0); // same week, nothing new

        // fund + allocate for a later week to confirm flow restored
        lista.mint(operator, 500e18);
        vm.startPrank(operator);
        vault.depositRewards(500e18, NEXT_WEEK + 1);
        uint16[] memory ids = new uint16[](1);
        uint256[] memory pct = new uint256[](1);
        ids[0] = id1; pct[0] = 1e18;
        vault.setWeeklyDistributorPercent(NEXT_WEEK + 1, ids, pct);
        vm.stopPrank();

        veLista.setCurrentWeek(NEXT_WEEK + 1);
        vm.prank(address(d1));
        assertEq(vault.allocateNewEmissions(id1), 500e18);
    }

    // ---------- helper ----------

    function _setPercents(uint16 _id1, uint256 p1, uint16 _id2, uint256 p2) internal {
        uint256 n;
        if (p1 > 0) n++;
        if (p2 > 0) n++;
        uint16[] memory ids = new uint16[](n);
        uint256[] memory pct = new uint256[](n);
        uint256 j;
        if (p1 > 0) { ids[j] = _id1; pct[j] = p1; j++; }
        if (p2 > 0) { ids[j] = _id2; pct[j] = p2; j++; }
        vm.prank(operator);
        vault.setWeeklyDistributorPercent(NEXT_WEEK, ids, pct);
    }

    function _one(uint16 id) internal pure returns (uint16[] memory a) {
        a = new uint16[](1);
        a[0] = id;
    }
}
