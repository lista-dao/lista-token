// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
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

  function setUp() public {
    VotingIncentive votingIncentiveImpl = new VotingIncentive();

    vault = new ListaVault();
    emissionVoting = new EmissionVoting();

    vm.startPrank(admin);
    vm.expectRevert("Invalid adminVoter");
    TransparentUpgradeableProxy _votingIncentiveProxy = new TransparentUpgradeableProxy(
      address(votingIncentiveImpl),
      proxyAdminOwner,
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        address(vault),
        address(emissionVoting),
        adminVoter,
        admin
      )
    );
    vm.mockCall(address(emissionVoting), abi.encodeWithSignature("hasRole(bytes32,address)"), abi.encode(true));
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(1)),
      abi.encode(uint256(1)) // week 1
    );

    TransparentUpgradeableProxy votingIncentiveProxy = new TransparentUpgradeableProxy(
      address(votingIncentiveImpl),
      proxyAdminOwner,
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        address(vault),
        address(emissionVoting),
        adminVoter,
        admin
      )
    );

    votingIncentive = VotingIncentive(address(votingIncentiveProxy));
    vm.stopPrank();

    asset1 = new ERC20("asset1", "asset1");
  }

  function test_whitelistAsset() public {
    vm.startPrank(admin);
    votingIncentive.whitelistAsset(address(asset1), true);
    assertTrue(votingIncentive.assetWhitelist(address(asset1)));
    vm.stopPrank();
  }

  function test_addIncentivesBnb() public {
    vm.mockCall(address(vault), abi.encodeWithSignature("distributorId()"), abi.encode(uint256(1000)));

    vm.expectRevert("Asset not whitelisted");
    address bnbAsset = address(0);
    votingIncentive.addIncentives(1, 2, 3, bnbAsset, 100);

    vm.startPrank(admin);
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

    vm.startPrank(admin);
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
      abi.encode(uint256(0)) // week 0
    );

    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("getDistributorWeeklyTotalWeight(uint16,uint16)", uint16(1), uint16(1)),
      abi.encode(uint256(100)) // pool weight 100 for week 1 distributor 1
    );

    vm.startPrank(admin);
    votingIncentive.whitelistAsset(address(asset1), true);
    assertTrue(votingIncentive.assetWhitelist(address(asset1)));

    deal(address(asset1), user1, 100 ether);
    vm.startPrank(user1);
    asset1.approve(address(votingIncentive), 1 ether);
    votingIncentive.addIncentives(1, 1, 2, address(asset1), 1 ether);
    vm.stopPrank();

    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("userVotedDistributorIndex(address,uint16,uint16)", address(user2), uint16(1), uint16(1)),
      abi.encode(uint256(0))
    );

    EmissionVoting.Vote[] memory user2Votes = new EmissionVoting.Vote[](1);
    user2Votes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 1 });

    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(user2), uint16(1)),
      abi.encode(user2Votes)
    );

    vm.startPrank(user2);
    uint256 balanceBefore = asset1.balanceOf(user2);
    votingIncentive.claim(1, 1, address(asset1));
    vm.stopPrank();
    assertEq(asset1.balanceOf(user2) - balanceBefore, 0.005 ether); // 0.5 * 1 / 100
  }

  function test_claim_bnb_with_zero_admin_weight() public {
    address bnbAsset = address(0);
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("distributorId()"),
      abi.encode(uint256(1000)) // max distributor id 1000
    );
    vm.mockCall(
      address(vault),
      abi.encodeWithSignature("getWeek(uint256)", uint256(1)),
      abi.encode(uint256(0)) // week 0
    );
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("getDistributorWeeklyTotalWeight(uint16,uint16)", uint16(1), uint16(1)),
      abi.encode(uint256(100)) // pool weight 100 for week 1 distributor 1
    );

    vm.startPrank(admin);
    votingIncentive.whitelistAsset(bnbAsset, true);
    assertTrue(votingIncentive.assetWhitelist(bnbAsset));

    vm.deal(user1, 100 ether);
    vm.startPrank(user1);
    asset1.approve(address(votingIncentive), 1 ether);
    votingIncentive.addIncentivesBnb{ value: 1 ether }(1, 1, 2);
    vm.stopPrank();

    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("userVotedDistributorIndex(address,uint16,uint16)", address(user2), uint16(1), uint16(1)),
      abi.encode(uint256(0))
    );

    EmissionVoting.Vote[] memory user2Votes = new EmissionVoting.Vote[](1);
    user2Votes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 1 });

    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(user2), uint16(1)),
      abi.encode(user2Votes)
    );

    vm.startPrank(user2);
    uint256 balanceBefore =user2.balance;
    votingIncentive.claim(1, 1, bnbAsset);
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
      abi.encode(uint256(0)) // week 0
    );

    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("getDistributorWeeklyTotalWeight(uint16,uint16)", uint16(1), uint16(1)),
      abi.encode(uint256(100)) // pool weight 100 for week 1 distributor 1
    );

    vm.startPrank(admin);
    votingIncentive.whitelistAsset(address(asset1), true);
    assertTrue(votingIncentive.assetWhitelist(address(asset1)));

    deal(address(asset1), user1, 100 ether);
    vm.startPrank(user1);
    asset1.approve(address(votingIncentive), 1 ether);
    votingIncentive.addIncentives(1, 1, 2, address(asset1), 1 ether);
    vm.stopPrank();

    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSignature("userVotedDistributorIndex(address,uint16,uint16)", address(user2), uint16(1), uint16(1)),
      abi.encode(uint256(0))
    );

    EmissionVoting.Vote[] memory user2Votes = new EmissionVoting.Vote[](1);
    user2Votes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 1 });
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(user2), uint16(1)),
      abi.encode(user2Votes) // mock user2's weight to be 1
    );

    EmissionVoting.Vote[] memory adminVotes = new EmissionVoting.Vote[](1);
    adminVotes[0] = EmissionVoting.Vote({ distributorId: 1, weight: 50 });
    vm.mockCall(
      address(emissionVoting),
      abi.encodeWithSelector(EmissionVoting.getUserVotedDistributors.selector, address(adminVoter), uint16(1)),
      abi.encode(adminVotes) // mock user2's weight to be 50
    );

    vm.startPrank(user2);
    uint256 balanceBefore = asset1.balanceOf(user2);
    votingIncentive.claim(1, 1, address(asset1));
    vm.stopPrank();
    assertEq(asset1.balanceOf(user2) - balanceBefore, 0.01 ether); // 0.5 * 1 / (100 - 50)
  }

  function test_setAdminVoter() public {
    vm.startPrank(admin);

    vm.expectRevert("Invalid adminVoter");
    votingIncentive.setAdminVoter(address(0));
    vm.expectRevert("Invalid adminVoter");
    votingIncentive.setAdminVoter(adminVoter);

    address newAdminVoter = makeAddr("newAdminVoter");
    vm.recordLogs();
    votingIncentive.setAdminVoter(newAdminVoter);
    Vm.Log[] memory entries = vm.getRecordedLogs();
    assertEq(entries.length, 1);
    vm.stopPrank();
  }
}
