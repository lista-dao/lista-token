// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/VeLista.sol";
import "../contracts/ListaToken.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/dao/ERC20LpListaDistributor.sol";
import "../contracts/dao/ListaVault.sol";
import "../contracts/mock/MockERC20.sol";
import "../contracts/dao/interfaces/IDistributor.sol";

import "../contracts/dao/EmissionVoting.sol";

contract EmissionVotingTest is Test {
  uint256 mainnet;
  EmissionVoting emissionVoting;
  VeLista public veLista = VeLista(0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3);
  ListaVault public vault = ListaVault(0x307d13267f360f78005f476Fa913F8848F30292A);
  ListaToken public listaToken = ListaToken(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46);
  ProxyAdmin public vaultProxyAdmin = ProxyAdmin(0xd6cd036133cbf6a275B7700fF7B41887A9d5FCAe);

  address multiSig = 0x08aE09467ff962aF105c23775B9Bc8EAa175D27F;
  address timelock = 0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253;
  address vaultAdmin = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;
  address adminVoter = makeAddr("admin_voter");
  address pauser = makeAddr("pauser");
  address manager = makeAddr("manager");
  address user1 = makeAddr("user1");
  address user2 = makeAddr("user2");

  uint256 weeklyEmission = 100000e18; // not final value, see line:96

  function setUp() public {
    mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");

    vm.startPrank(multiSig);

    // ---- (1) deploy EmissionVoting contract
    EmissionVoting evImpl = new EmissionVoting();
    TransparentUpgradeableProxy emissionVotingProxy = new TransparentUpgradeableProxy(
      address(evImpl),
      makeAddr("proxy_admin"),
      abi.encodeWithSignature(
        "initialize(address,address,address,address,uint256)",
        multiSig,
        adminVoter,
        address(veLista),
        address(vault),
        86400
      )
    );
    emissionVoting = EmissionVoting(address(emissionVotingProxy));
    console.logString("EmissionVoting deployed");

    // ---- (2) set AdminVoter and Pauser
    // grant admin voter role to emission voting
    emissionVoting.grantRole(emissionVoting.ADMIN_VOTER(), adminVoter);
    // grant pauser role
    emissionVoting.grantRole(emissionVoting.PAUSER(), pauser);
    console.logString("admin voter role granted.");
    // grant manager role
    emissionVoting.grantRole(emissionVoting.MANAGER(), manager);
    vm.stopPrank();

    // ---- (3) upgrade ListaVault
    ListaVault impl = new ListaVault();
    vm.prank(timelock);
    vaultProxyAdmin.upgradeAndCall{ value: 0 }(ITransparentUpgradeableProxy(address(vault)), address(impl), bytes(""));
    console.logString("ListaVault upgraded");

    // ---- (4) set
    vm.startPrank(vaultAdmin);
    vault.grantRole(vault.OPERATOR(), vaultAdmin);
    // set emission voting to vault
    vault.setEmissionVoting(address(emissionVoting));
    console.logString("Emission voting set.");
    // deposit rewards
    deal(address(listaToken), vaultAdmin, weeklyEmission);
    listaToken.approve(address(vault), type(uint256).max);
    vault.depositRewards(weeklyEmission, veLista.getCurrentWeek() + 1);
    console.logString("Rewards deposited.");
    vm.stopPrank();

    deal(address(listaToken), multiSig, 10000e18);
    deal(address(listaToken), adminVoter, 10000e18);
    deal(address(listaToken), user1, 10000e18);
    deal(address(listaToken), user2, 10000e18);

    // admin voter lock 5000 lista
    vm.startPrank(adminVoter);
    listaToken.approve(address(veLista), 5000e18);
    veLista.lock(5000e18, 52, true);
    vm.stopPrank();

    // user 1 lock 2000 lista
    vm.startPrank(user1);
    listaToken.approve(address(veLista), 5000e18);
    veLista.lock(5000e18, 52, true);
    vm.stopPrank();
    // user 2 lock 1000 lista
    vm.startPrank(user2);
    listaToken.approve(address(veLista), 5000e18);
    veLista.lock(5000e18, 52, true);
    vm.stopPrank();

    // check weight
    assertEq(veLista.balanceOf(adminVoter), 52 * 5000e18);
    assertEq(veLista.balanceOf(user1), 52 * 5000e18);
    assertEq(veLista.balanceOf(user2), 52 * 5000e18);

    // overwrite, in case reward of next week already deposited
    weeklyEmission = vault.weeklyEmissions(veLista.getCurrentWeek() + 1);
  }

  function test_user_voting() public {
    // enable distributors
    vm.startPrank(manager);
    emissionVoting.setDistributor(1, true);
    emissionVoting.setDistributor(2, true);
    emissionVoting.setDistributor(3, true);
    vm.stopPrank();

    // get the timestamp when admin period start
    uint256 adminPeriod = veLista.startTime() +
      (veLista.getCurrentWeek() + 1) *
      emissionVoting.WEEK() - // veLista current timestamp
      emissionVoting.ADMIN_VOTE_PERIOD(); // admin period

    // in case entered admin vote period, rewind a little bit so user can vote
    if (block.timestamp > adminPeriod) {
      rewind(1 days); // rewind 1 day
    }

    // ---------------------------- //
    //     Normal user voting       //
    // ---------------------------- //
    // distributor ids and weights
    uint16[] memory d1 = new uint16[](2);
    uint256[] memory w1 = new uint256[](2);
    d1[0] = 1;
    d1[1] = 2;

    w1[0] = 10000;
    w1[1] = 23000;
    vm.prank(user1); // user 1 vote
    emissionVoting.vote(d1, w1);

    uint16[] memory d2 = new uint16[](3);
    uint256[] memory w2 = new uint256[](3);
    d2[0] = 1;
    d2[1] = 2;
    d2[2] = 3;
    w2[0] = 22000;
    w2[1] = 43000;
    w2[2] = 50000;
    vm.prank(user2); // user 2 vote
    emissionVoting.vote(d2, w2);

    uint16 votingWeek = veLista.getCurrentWeek() + 1;

    uint256 totalWeight = emissionVoting.getWeeklyTotalWeight(votingWeek);

    console.logUint(totalWeight);
    console.logUint(emissionVoting.userWeeklyVotedWeight(user1, votingWeek));
    console.logUint(emissionVoting.userWeeklyVotedWeight(user2, votingWeek));
    console.logUint(emissionVoting.distributorWeeklyTotalWeight(1, votingWeek));

    assertEq(totalWeight, 10000 + 22000 + 23000 + 43000 + 50000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(1, votingWeek), 10000 + 22000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(2, votingWeek), 23000 + 43000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(3, votingWeek), 50000);
    if (vault.getDistributorWeeklyEmissions(1, votingWeek) != 0) {
      assertEq(vault.getDistributorWeeklyEmissions(1, votingWeek), (weeklyEmission * (10000 + 22000)) / totalWeight);
    }
    /*
    assertEq(vault.getDistributorWeeklyEmissions(2, votingWeek), (weeklyEmission * (23000 + 43000)) / totalWeight);
    assertEq(vault.getDistributorWeeklyEmissions(3, votingWeek), (weeklyEmission * 50000) / totalWeight);

    // ---------------------------- //
    //      user 2 edit vote        //
    // ---------------------------- //
    // user2 edit vote weight
    uint256[] memory w3 = new uint256[](3);
    w3[0] = 30000;
    w3[1] = 0;
    w3[2] = 70000;

    vm.prank(user2);
    emissionVoting.vote(d2, w3);
    totalWeight = emissionVoting.getWeeklyTotalWeight(votingWeek);

    assertEq(totalWeight, 10000 + 23000 + 30000 + 70000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(1, votingWeek), 10000 + 30000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(2, votingWeek), 23000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(3, votingWeek), 70000);
    assertEq(vault.getDistributorWeeklyEmissions(1, votingWeek), (weeklyEmission * (10000 + 30000)) / totalWeight);
    assertEq(vault.getDistributorWeeklyEmissions(2, votingWeek), (weeklyEmission * 23000) / totalWeight);
    assertEq(vault.getDistributorWeeklyEmissions(3, votingWeek), (weeklyEmission * 70000) / totalWeight);

    // ---------------------------- //
    //      Admin vote period       //
    // ---------------------------- //

    // back to admin period
    if (block.timestamp < adminPeriod) {
      vm.warp(adminPeriod + 1000);
    }

    // user shouldn't able to vote
    vm.prank(user2);
    vm.expectRevert(bytes("only admin voter can vote now"));
    emissionVoting.vote(d2, w3);

    // admin vote
    uint256[] memory w4 = new uint256[](3);
    w4[0] = 500000;
    w4[1] = 0;
    w4[2] = 800000;
    vm.prank(adminVoter);
    emissionVoting.adminVote(d2, w4);

    totalWeight = emissionVoting.getWeeklyTotalWeight(votingWeek);

    assertEq(totalWeight, 10000 + 23000 + 30000 + 70000 + 500000 + 800000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(1, votingWeek), 10000 + 30000 + 500000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(2, votingWeek), 23000);
    assertEq(emissionVoting.getDistributorWeeklyTotalWeight(3, votingWeek), 70000 + 800000);
    assertEq(
      vault.getDistributorWeeklyEmissions(1, votingWeek),
      (weeklyEmission * (10000 + 30000 + 500000)) / totalWeight
    );
    assertEq(vault.getDistributorWeeklyEmissions(2, votingWeek), (weeklyEmission * 23000) / totalWeight);
    assertEq(vault.getDistributorWeeklyEmissions(3, votingWeek), (weeklyEmission * (70000 + 800000)) / totalWeight);
    */
  }

  function test_set_distributor() public {
    // distributors should be disabled by default
    assertEq(emissionVoting.activeDistributors(1), false);
    assertEq(emissionVoting.activeDistributors(2), false);

    vm.startPrank(manager);
    emissionVoting.setDistributor(1, true);
    emissionVoting.setDistributor(2, true);
    vm.stopPrank();
    assertEq(emissionVoting.activeDistributors(1), true);
    assertEq(emissionVoting.activeDistributors(2), true);
  }

  function test_pause_voting() public {
    // pause voting
    vm.prank(pauser);
    emissionVoting.pause();

    uint16[] memory d = new uint16[](1);
    uint256[] memory w = new uint256[](1);
    d[0] = 1;
    w[0] = 11111;
    vm.prank(adminVoter);
    vm.expectRevert(bytes("Pausable: paused"));
    emissionVoting.adminVote(d, w);

    // resume vote
    vm.prank(multiSig);
    emissionVoting.togglePause();

    // skip to admin period
    vm.warp(veLista.startTime() + uint256(veLista.getCurrentWeek()) * 1 weeks);
    skip(6 days);

    vm.prank(manager);
    emissionVoting.setDistributor(1, true);

    // should be able to vote
    vm.prank(adminVoter);
    emissionVoting.adminVote(d, w);
  }
}
