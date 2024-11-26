// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { VotingIncentive } from "contracts/dao/VotingIncentive.sol";
import { ListaVault } from "contracts/dao/ListaVault.sol";
import { EmissionVoting } from "contracts/dao/EmissionVoting.sol";

contract VotingIncentiveTest is Test {
  VotingIncentive votingIncentive;

  ListaVault vault;
  EmissionVoting emissionVoting;
  ERC20 asset1;

  address feeReceiver = makeAddr("feeReceiver");
  address admin = makeAddr("admin");
  address bot = makeAddr("bot");
  address user1 = makeAddr("user1");
  address user2 = makeAddr("user2");
  address proxyAdminOwner = makeAddr("proxyAdminOwner");
  address adminVoter = makeAddr("adminVoter");
  address manager = makeAddr("manager");
  address pauser = makeAddr("pauser");

  function setUp() public {
    VotingIncentive votingIncentiveImpl = new VotingIncentive();

    vault = new ListaVault();
    emissionVoting = new EmissionVoting();
    vm.mockCall(address(emissionVoting), abi.encodeWithSignature("hasRole(bytes32,address)"), abi.encode(true));
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(1)),
      abi.encode(uint256(1)) // week 1
    );

    vm.startPrank(admin);

    bytes memory data = abi.encodeWithSignature(
      "initialize(address,address,address,address,address,address)",
      address(vault),
      address(emissionVoting),
      adminVoter,
      admin,
      manager,
      pauser
    );

    address proxy = address(new ERC1967Proxy(address(votingIncentiveImpl), data));
    votingIncentive = VotingIncentive(proxy);
    vm.stopPrank();

    asset1 = new ERC20("asset1", "asset1");
  }

  function test_whitelistAsset() public {
    vm.startPrank(manager);
    votingIncentive.whitelistAsset(address(asset1), true);
    assertTrue(votingIncentive.assetWhitelist(address(asset1)));
    vm.stopPrank();
  }
  function testRevert_addIncentivesBnb_disbaled_distributor() public {
    vm.mockCall(address(vault), abi.encodeWithSignature("distributorId()"), abi.encode(uint256(1000)));
    vm.mockCall(address(emissionVoting), abi.encodeWithSignature("disabledDistributors(uint16)"), abi.encode(true));

    address bnbAsset = address(0);

    vm.startPrank(manager);
    votingIncentive.whitelistAsset(bnbAsset, true);
    assertTrue(votingIncentive.assetWhitelist(bnbAsset));

    vm.expectRevert("Distributor is disabled");
    vm.deal(user1, 2 ether);
    vm.startPrank(user1);
    votingIncentive.addIncentivesBnb{ value: 1 ether }(1, 2, 3);
    vm.stopPrank();
  }

  function test_addIncentivesBnb() public {
    vm.mockCall(address(vault), abi.encodeWithSignature("distributorId()"), abi.encode(uint256(1000)));

    vm.expectRevert("Asset not whitelisted");
    address bnbAsset = address(0);
    votingIncentive.addIncentives(1, 2, 3, bnbAsset, 100);

    vm.startPrank(manager);
    votingIncentive.whitelistAsset(bnbAsset, true);
    assertTrue(votingIncentive.assetWhitelist(bnbAsset));

    vm.deal(user1, 2 ether);
    vm.startPrank(user1);
    votingIncentive.addIncentivesBnb{ value: 1 ether }(1, 2, 3);
    vm.stopPrank();

    assertEq(votingIncentive.weeklyIncentives(1, 2, bnbAsset), 0.5 ether);
    assertEq(votingIncentive.weeklyIncentives(1, 3, bnbAsset), 0.5 ether);
    assertEq(votingIncentive.weeklyIncentives(1, 4, bnbAsset), 0);
  }

  function test_addIncentives() public {
    vm.mockCall(address(vault), abi.encodeWithSignature("distributorId()"), abi.encode(uint256(1000)));

    vm.expectRevert("Asset not whitelisted");
    votingIncentive.addIncentives(1, 2, 3, makeAddr("asset2"), 100);

    vm.startPrank(manager);
    votingIncentive.whitelistAsset(address(asset1), true);
    assertTrue(votingIncentive.assetWhitelist(address(asset1)));

    deal(address(asset1), user1, 100 ether);
    vm.startPrank(user1);
    asset1.approve(address(votingIncentive), 1 ether);
    votingIncentive.addIncentives(1, 2, 3, address(asset1), 1 ether);
    vm.stopPrank();

    assertEq(votingIncentive.weeklyIncentives(1, 2, address(asset1)), 0.5 ether);
    assertEq(votingIncentive.weeklyIncentives(1, 3, address(asset1)), 0.5 ether);
    assertEq(votingIncentive.weeklyIncentives(1, 4, address(asset1)), 0);
  }

  function test_claim_zero_admin_weight() public {
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("distributorId()"),
      abi.encode(uint256(1000)) // max distributor id 1000
    );
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(1)),
      abi.encode(uint256(1)) // set current week = 1
    );
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("getDistributorWeeklyTotalWeight(uint16,uint16)", uint16(1), uint16(2)), // week 2, distributor 1
      abi.encode(uint256(100)) // pool weight 100 for week 2 distributor 1
    );
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("getDistributorWeeklyTotalWeight(uint16,uint16)", uint16(2), uint16(2)), // week 2, distributor 2
      abi.encode(uint256(100)) // pool weight 100 for week 2 distributor 2
    );

    vm.startPrank(manager);
    votingIncentive.whitelistAsset(address(asset1), true);
    assertTrue(votingIncentive.assetWhitelist(address(asset1)));

    deal(address(asset1), user1, 100 ether);
    vm.startPrank(user1);
    asset1.approve(address(votingIncentive), 2 ether);
    votingIncentive.addIncentives(1, 2, 3, address(asset1), 1 ether); // start week 2, end week 3, distributor 1
    votingIncentive.addIncentives(2, 2, 3, address(asset1), 1 ether); // start week 2, end week 3, distributor 2
    vm.stopPrank();

    // ----------------- Mock user2's vote -------------------- //
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("userVotedDistributorIndex(address,uint16,uint16)", address(user2), uint16(2), uint16(1)), // week 2, distributor 1
      abi.encode(uint256(1)) // index = 0
    );
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("userVotedDistributorIndex(address,uint16,uint16)", address(user2), uint16(2), uint16(2)), // week 2, distributor 2
      abi.encode(uint256(2)) // index = 1
    );

    EmissionVoting.Vote[] memory user2Votes = new EmissionVoting.Vote[](2);
    user2Votes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 1 }); // weight 1
    user2Votes[1] = EmissionVoting.Vote({ distributorId: 2, weight: 10 }); // weight 10
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(user2), uint16(2)), // week 2
      abi.encode(user2Votes)
    );

    // ------------------- user2 claim ---------------------- //
    skip(1 weeks);
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(604801)),
      abi.encode(uint256(2)) // currnet week = 2
    );

    vm.startPrank(user2);
    uint256 balanceBefore = asset1.balanceOf(user2);
    votingIncentive.claim(user2, 1, 2, address(asset1)); // week 2, distributor 1
    vm.stopPrank();
    assertEq(asset1.balanceOf(user2) - balanceBefore, 0.005 ether); // 0.5 * 1 / 100

    // ------------------- user2 batch claim ---------------------- //
    VotingIncentive.ClaimParams[] memory claimParams = new VotingIncentive.ClaimParams[](2);
    address[] memory assets = new address[](1);
    assets[0] = address(asset1);
    claimParams[0] = VotingIncentive.ClaimParams({ distributorId: 1, week: 2, assets: assets });
    claimParams[1] = VotingIncentive.ClaimParams({ distributorId: 2, week: 2, assets: assets });
    vm.startPrank(user2);
    uint256 _balanceBefore = asset1.balanceOf(user2);
    votingIncentive.batchClaim(claimParams);
    vm.stopPrank();

    assertEq(asset1.balanceOf(user2) - _balanceBefore, 0.05 ether); // 0.5 * 10 / 100
  }

  function test_claim_bnb_with_zero_admin_weight() public {
    address bnbAsset = address(0);
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("distributorId()"),
      abi.encode(uint256(1000)) // set max distributor id to 1000
    );
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(1)),
      abi.encode(uint256(1)) // set currnet week = 1
    );
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("getDistributorWeeklyTotalWeight(uint16,uint16)", uint16(1), uint16(2)), // week 2
      abi.encode(uint256(100)) // pool weight 100 for week 2 distributor 1
    );

    vm.startPrank(manager);
    votingIncentive.whitelistAsset(bnbAsset, true);
    assertTrue(votingIncentive.assetWhitelist(bnbAsset));

    vm.deal(user1, 100 ether);
    vm.startPrank(user1);
    asset1.approve(address(votingIncentive), 1 ether);
    votingIncentive.addIncentivesBnb{ value: 1 ether }(1, 2, 3);
    vm.stopPrank();

    // ----------------- Mock user2's vote -------------------- //
    // user2 has voted for distributor 1 on week 2
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("userVotedDistributorIndex(address,uint16,uint16)", address(user2), uint16(2), uint16(1)), // week 2, distributor 1
      abi.encode(uint256(1)) // user2 has voted for distributor 1 on week 2, index = 1
    );
    EmissionVoting.Vote[] memory user2Votes = new EmissionVoting.Vote[](1); // length = 1; since `index -= 1`
    user2Votes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 1 });
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(user2), uint16(2)), // week 2
      abi.encode(user2Votes)
    );

    // ------------------- user2 claim ---------------------- //
    skip(1 weeks);
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(604801)),
      abi.encode(uint256(2)) // currnet week = 2
    );

    vm.startPrank(user2);
    uint256 balanceBefore = user2.balance;
    votingIncentive.claim(user2, 1, 2, bnbAsset); // week 2, distributor 1
    vm.stopPrank();
    assertEq(user2.balance - balanceBefore, 0.005 ether); // 0.5 * 1 / 100
  }

  function test_claim_nonZero_admin_weight() public {
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("distributorId()"),
      abi.encode(uint256(1000)) // max distributor id 1000
    );
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(1)),
      abi.encode(uint256(1)) // set currnet week = 1
    );
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("getDistributorWeeklyTotalWeight(uint16,uint16)", uint16(1), uint16(2)), // week 2
      abi.encode(uint256(100)) // pool weight 100 for week 2 distributor 1
    );

    vm.startPrank(manager);
    votingIncentive.whitelistAsset(address(asset1), true);
    assertTrue(votingIncentive.assetWhitelist(address(asset1)));

    deal(address(asset1), user1, 100 ether);
    vm.startPrank(user1);
    asset1.approve(address(votingIncentive), 1 ether);
    votingIncentive.addIncentives(1, 2, 3, address(asset1), 1 ether); // start week 2, end week 3
    vm.stopPrank();

    // ------------------- Mock user2 vote ---------------------- //
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("userVotedDistributorIndex(address,uint16,uint16)", address(user2), uint16(2), uint16(1)), // week 2, distributor 1
      abi.encode(uint256(1)) // User2's index = 1
    );
    EmissionVoting.Vote[] memory user2Votes = new EmissionVoting.Vote[](1);
    user2Votes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 1 });
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(user2), uint16(2)), // week 2
      abi.encode(user2Votes) // mock user2's weight to be 1
    );

    // ------------------- Mock adminVoter vote ---------------------- //
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature(
        "userVotedDistributorIndex(address,uint16,uint16)",
        address(adminVoter),
        uint16(2), // week 2
        uint16(1) // distributor 1
      ),
      abi.encode(uint256(1)) // adminVoter's index = 1
    );
    EmissionVoting.Vote[] memory adminVotes = new EmissionVoting.Vote[](1);
    adminVotes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 50 });
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(adminVoter), uint16(2)), // week 2
      abi.encode(adminVotes) // mock adminVoter's weight to be 50
    );

    // ------------------- user2 claim ---------------------- //
    skip(1 weeks);
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(604801)),
      abi.encode(uint256(2)) // currnet week = 2
    );

    VotingIncentive.ClaimParams[] memory _input = new VotingIncentive.ClaimParams[](1);
    address[] memory assets = new address[](1);
    assets[0] = address(makeAddr("asset333"));
    _input[0] = VotingIncentive.ClaimParams({ distributorId: 1, week: 2, assets: assets });
    VotingIncentive.ClaimableAmount[] memory claimableAmounts = votingIncentive.getClaimableAmount(user2, _input);
    assertEq(claimableAmounts[0].distributorId, 1);
    assertEq(claimableAmounts[0].week, 2);
    assertEq(claimableAmounts[0].incentives.length, 1);
    VotingIncentive.Incentive memory incentives = claimableAmounts[0].incentives[0];
    assertEq(incentives.asset, address(makeAddr("asset333")));
    assertEq(incentives.amount, 0); // no incentives

    vm.startPrank(user2);
    uint256 balanceBefore = asset1.balanceOf(user2);
    votingIncentive.claim(user2, 1, 2, address(asset1));
    vm.stopPrank();
    assertEq(asset1.balanceOf(user2) - balanceBefore, 0.01 ether); // 0.5 * 1 / (100 - 50)
  }


  function test_getClaimableAmount() public {
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("distributorId()"),
      abi.encode(uint256(1000)) // max distributor id 1000
    );
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(1)),
      abi.encode(uint256(1)) // set currnet week = 1
    );
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("getDistributorWeeklyTotalWeight(uint16,uint16)", uint16(1), uint16(2)), // week 2
      abi.encode(uint256(100)) // pool weight 100 for week 2 distributor 1
    );

    vm.startPrank(manager);
    votingIncentive.whitelistAsset(address(asset1), true);
    assertTrue(votingIncentive.assetWhitelist(address(asset1)));

    deal(address(asset1), user1, 100 ether);
    vm.startPrank(user1);
    asset1.approve(address(votingIncentive), 1 ether);
    votingIncentive.addIncentives(1, 2, 3, address(asset1), 1 ether); // start week 2, end week 3
    vm.stopPrank();

    // ------------------- Mock adminVoter vote ---------------------- //
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature(
        "userVotedDistributorIndex(address,uint16,uint16)",
        address(adminVoter),
        uint16(2), // week 2
        uint16(1) // distributor 1
      ),
      abi.encode(uint256(1)) // adminVoter's index = 1
    );
    EmissionVoting.Vote[] memory adminVotes = new EmissionVoting.Vote[](1);
    adminVotes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 100 });
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(adminVoter), uint16(2)), // week 2
      abi.encode(adminVotes) // mock adminVoter's weight to be **100**
    );


    VotingIncentive.ClaimParams[] memory _input = new VotingIncentive.ClaimParams[](1);
    address[] memory assets = new address[](1);
    assets[0] = address(asset1);
    _input[0] = VotingIncentive.ClaimParams({ distributorId: 1, week: 2, assets: assets });
    VotingIncentive.ClaimableAmount[] memory claimableAmounts = votingIncentive.getClaimableAmount(user2, _input);
    assertEq(claimableAmounts[0].distributorId, 1);
    assertEq(claimableAmounts[0].week, 2);
    assertEq(claimableAmounts[0].incentives.length, 1);
    VotingIncentive.Incentive memory incentives = claimableAmounts[0].incentives[0];
    assertEq(incentives.asset, address(asset1));
    assertEq(incentives.amount, 0); // no incentives
  }



  function test_setAdminVoter() public {
    vm.startPrank(admin);

    vm.expectRevert();
    votingIncentive.setAdminVoter(address(0));
    vm.expectRevert();
    votingIncentive.setAdminVoter(adminVoter);

    address newAdminVoter = makeAddr("newAdminVoter");
    address newAdminVoter2 = makeAddr("newAdminVoter2");

    vm.recordLogs();
    votingIncentive.setAdminVoter(newAdminVoter);
    Vm.Log[] memory entries = vm.getRecordedLogs();
    assertEq(entries.length, 1);

    vm.clearMockedCalls();
    vm.mockCall(address(emissionVoting), abi.encodeWithSignature("hasRole(bytes32,address)"), abi.encode(false));
    vm.expectRevert("_adminVoter is not granted role");
    votingIncentive.setAdminVoter(newAdminVoter2);
    vm.stopPrank();
  }

  function test_pause() public {
    vm.startPrank(pauser);
    votingIncentive.pause();
    assertEq(votingIncentive.paused(), true);
    vm.expectRevert(
      "AccessControl: account 0x1733d2304bfd07ad9b29053845b904ffbd99f9fb is missing role 0xaf290d8680820aad922855f39b306097b20e28774d6c1ad35a20325630c3a02c"
    );
    votingIncentive.unpause();
    vm.stopPrank();

    vm.startPrank(manager);
    votingIncentive.unpause();
    vm.stopPrank();
    assertEq(votingIncentive.paused(), false);
  }
}
