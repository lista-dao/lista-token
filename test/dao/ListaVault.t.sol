// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/VeLista.sol";
import "../../contracts/ListaToken.sol";
import "../../contracts/dao/ListaVault.sol";
import "../../contracts/dao/EmissionVoting.sol";
import "../../contracts/dao/interfaces/IDistributor.sol";

contract MockDistributor is IDistributor {
    uint16 public registeredId;
    function vaultClaimReward(address) external pure returns (uint256) { return 0; }
    function vaultClaimStakingReward(address) external pure returns (uint256) { return 0; }
    function notifyRegisteredId(uint16 _emissionId) external returns (bool) {
        registeredId = _emissionId;
        return true;
    }
    function claimableReward(address) external pure returns (uint256) { return 0; }
    function notifyStakingReward(uint256) external {}
    function lpToken() external pure returns (address) { return address(0); }
}

contract ListaVaultTest is Test {
    ListaVault public vault = ListaVault(0x307d13267f360f78005f476Fa913F8848F30292A);
    ListaToken public listaToken = ListaToken(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46);
    VeLista public veLista = VeLista(0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3);
    ProxyAdmin public vaultProxyAdmin = ProxyAdmin(0xd6cd036133cbf6a275B7700fF7B41887A9d5FCAe);

    address timelock = 0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253;
    address vaultAdmin = 0x8d388136d578dCD791D081c6042284CED6d9B0c6; // MANAGER
    address operator = makeAddr("operator");
    address attacker = makeAddr("attacker");

    MockDistributor public d1;
    MockDistributor public d2;
    uint16 public id1;
    uint16 public id2;

    function setUp() public {
        vm.createSelectFork("https://bsc-dataseed.binance.org");

        // upgrade vault to local impl with blacklist
        ListaVault impl = new ListaVault();
        vm.prank(timelock);
        vaultProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(vault)),
            address(impl),
            bytes("")
        );

        // grant OPERATOR + register two fresh distributors
        vm.startPrank(vaultAdmin);
        vault.grantRole(vault.OPERATOR(), operator);
        d1 = new MockDistributor();
        d2 = new MockDistributor();
        id1 = vault.registerDistributor(address(d1));
        id2 = vault.registerDistributor(address(d2));

        // fund weekly emissions for next week so getDistributorWeeklyEmissions has a non-zero pool
        uint16 nextWeek = veLista.getCurrentWeek() + 1;
        deal(address(listaToken), vaultAdmin, 1000e18);
        listaToken.approve(address(vault), type(uint256).max);
        vault.depositRewards(1000e18, nextWeek);
        vm.stopPrank();
    }

    // ---------- access control ----------

    function test_setDistributorBlacklist_revertsForNonManager() public {
        vm.prank(attacker);
        vm.expectRevert(); // AccessControl reverts with role-specific message
        vault.setDistributorBlacklist(id1, true);
    }

    function test_setDistributorBlacklist_managerCanSet() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit ListaVault.DistributorBlacklistUpdated(id1, true);

        vm.prank(vaultAdmin);
        vault.setDistributorBlacklist(id1, true);

        assertTrue(vault.distributorBlacklist(id1));
    }

    function test_setDistributorBlacklist_canUnblacklist() public {
        vm.startPrank(vaultAdmin);
        vault.setDistributorBlacklist(id1, true);
        vault.setDistributorBlacklist(id1, false);
        vm.stopPrank();

        assertFalse(vault.distributorBlacklist(id1));
    }

    // ---------- validation ----------

    function test_setDistributorBlacklist_revertsOnUnregisteredId() public {
        uint16 unregisteredId = vault.distributorId() + 1;
        vm.prank(vaultAdmin);
        vm.expectRevert("distributor not registered");
        vault.setDistributorBlacklist(unregisteredId, true);
    }

    function test_setDistributorBlacklist_revertsWhenStateUnchanged() public {
        vm.startPrank(vaultAdmin);
        vm.expectRevert("blacklist state unchanged");
        vault.setDistributorBlacklist(id1, false); // already false

        vault.setDistributorBlacklist(id1, true);
        vm.expectRevert("blacklist state unchanged");
        vault.setDistributorBlacklist(id1, true); // already true
        vm.stopPrank();
    }

    // ---------- gate: setWeeklyDistributorPercent ----------

    function test_setWeeklyDistributorPercent_revertsForBlacklistedId() public {
        vm.prank(vaultAdmin);
        vault.setDistributorBlacklist(id1, true);

        uint16 nextWeek = veLista.getCurrentWeek() + 1;
        uint16[] memory ids = new uint16[](1);
        uint256[] memory pct = new uint256[](1);
        ids[0] = id1;
        pct[0] = 5e17;

        vm.prank(operator);
        vm.expectRevert("distributor blacklisted");
        vault.setWeeklyDistributorPercent(nextWeek, ids, pct);
    }

    function test_setWeeklyDistributorPercent_succeedsAfterUnblacklist() public {
        vm.startPrank(vaultAdmin);
        vault.setDistributorBlacklist(id1, true);
        vault.setDistributorBlacklist(id1, false);
        vm.stopPrank();

        uint16 nextWeek = veLista.getCurrentWeek() + 1;
        uint16[] memory ids = new uint16[](1);
        uint256[] memory pct = new uint256[](1);
        ids[0] = id1;
        pct[0] = 5e17;

        vm.prank(operator);
        vault.setWeeklyDistributorPercent(nextWeek, ids, pct);

        assertEq(vault.weeklyDistributorPercent(nextWeek, id1), 5e17);
    }

    // ---------- gate: getDistributorWeeklyEmissions ----------

    function test_getDistributorWeeklyEmissions_zeroForBlacklistedInPercentPath() public {
        // operator sets percents, then admin blacklists d1 — emission must be zero
        uint16 nextWeek = veLista.getCurrentWeek() + 1;
        uint16[] memory ids = new uint16[](2);
        uint256[] memory pct = new uint256[](2);
        ids[0] = id1; pct[0] = 4e17;
        ids[1] = id2; pct[1] = 6e17;

        vm.prank(operator);
        vault.setWeeklyDistributorPercent(nextWeek, ids, pct);

        // sanity: before blacklist d1 has nonzero allocation
        assertGt(vault.getDistributorWeeklyEmissions(id1, nextWeek), 0);

        vm.prank(vaultAdmin);
        vault.setDistributorBlacklist(id1, true);

        assertEq(vault.getDistributorWeeklyEmissions(id1, nextWeek), 0);
        // d2 still gets its share
        assertGt(vault.getDistributorWeeklyEmissions(id2, nextWeek), 0);
    }

    // ---------- gate: allocateNewEmissions ----------

    function test_allocateNewEmissions_zeroForBlacklisted() public {
        // set d1 percent for next week, advance to that week, then blacklist before allocate
        uint16 nextWeek = veLista.getCurrentWeek() + 1;
        uint16[] memory ids = new uint16[](1);
        uint256[] memory pct = new uint256[](1);
        ids[0] = id1; pct[0] = 1e18;

        vm.prank(operator);
        vault.setWeeklyDistributorPercent(nextWeek, ids, pct);

        // jump past nextWeek so allocation has something to credit
        vm.warp(block.timestamp + 8 days);

        vm.prank(vaultAdmin);
        vault.setDistributorBlacklist(id1, true);

        // d1 calls allocate; should receive 0
        vm.prank(address(d1));
        uint256 got = vault.allocateNewEmissions(id1);
        assertEq(got, 0);
        assertEq(vault.allocated(address(d1)), 0);
    }

    function test_allocateNewEmissions_nonzeroForNonBlacklisted() public {
        uint16 nextWeek = veLista.getCurrentWeek() + 1;
        uint16[] memory ids = new uint16[](1);
        uint256[] memory pct = new uint256[](1);
        ids[0] = id1; pct[0] = 1e18;

        vm.prank(operator);
        vault.setWeeklyDistributorPercent(nextWeek, ids, pct);

        vm.warp(block.timestamp + 8 days);

        // 100% allocation → distributor receives the full weeklyEmissions pool for that week
        uint256 expected = vault.weeklyEmissions(nextWeek);
        assertGt(expected, 0, "weeklyEmissions sanity");

        vm.prank(address(d1));
        uint256 got = vault.allocateNewEmissions(id1);
        assertEq(got, expected);
        assertEq(vault.allocated(address(d1)), expected);
    }
}
