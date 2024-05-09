// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Test, console} from "forge-std/Test.sol";
import {VeLista} from "../contracts/VeLista.sol";
import {ListaToken} from "../contracts/ListaToken.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VeListaDistributor} from "../contracts/VeListaDistributor.sol";
import {MockERC20} from "../contracts/mock/MockERC20.sol";


contract VeListaDistributorTest is Test {
    VeLista public veLista = VeLista(0x51075B00313292db08f3450f91fCA53Db6Bd0D11);
    ListaToken public lista = ListaToken(0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB);
    ProxyAdmin public proxyAdmin = ProxyAdmin(0xc78f64Cd367bD7d2922088669463FCEE33f50b7c);
    VeListaDistributor public distributor = VeListaDistributor(0x97976D0A346f6c195Dd41628717f59A3a874B86D);
    MockERC20 public token1;
    MockERC20 public token2;

    uint256 MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address manager = 0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232;

    address user1 = 0x5a97ba0b0B18a618966303371374EBad4960B7D9;
    address user2 = 0x245b3Ee7fCC57AcAe8c208A563F54d630B5C4eD7;

    address proxyAdminOwner = 0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06;

    function setUp() public {
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        token1 = new MockERC20(manager, "token1", "token1");
        token2 = new MockERC20(manager, "token2", "token2");

        vm.startPrank(manager);
        lista.transfer(user1, 10000 ether);
        lista.transfer(user2, 20000 ether);
        token1.mint(manager, 1_000_000_000 ether);
        token2.mint(manager, 1_000_000_000 ether);
        token1.approve(address(distributor), MAX_UINT);
        token2.approve(address(distributor), MAX_UINT);
        vm.stopPrank();

        vm.prank(user1);
        lista.approve(address(veLista), MAX_UINT);

        vm.prank(user2);
        lista.approve(address(veLista), MAX_UINT);

        address impl = address(new VeListaDistributor());
        vm.prank(proxyAdminOwner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(distributor)), impl);

    }

    function test_registerNewToken() public {
        uint256 currentWeek = veLista.getCurrentWeek();
        vm.startPrank(manager);
        distributor.registerNewToken(address(token1));
        distributor.registerNewToken(address(token2));
        vm.stopPrank();
        uint16 token1StartWeek = distributor.getRewardTokenStartWeek(address(token1));
        uint16 token2StartWeek = distributor.getRewardTokenStartWeek(address(token2));
        assertEq(token1StartWeek, currentWeek, "reward token 0 is not token1");
        assertEq(token2StartWeek, currentWeek, "reward token 1 is not token2");
    }

    function test_depositReward() public {
        VeListaDistributor.TokenAmount[] memory tokens = new VeListaDistributor.TokenAmount[](2);
        tokens[0].token = address(token1);
        tokens[0].amount = 100 ether;
        tokens[1].token = address(token2);
        tokens[1].amount = 1000 ether;

        skip(2 weeks);

        vm.startPrank(manager);
        distributor.registerNewToken(address(token1));
        distributor.registerNewToken(address(token2));
        vm.stopPrank();
        skip(1 weeks);
        uint16 week = veLista.getCurrentWeek() - 1;
        vm.prank(manager);
        distributor.depositNewReward(week, tokens);

        VeListaDistributor.TokenAmount[] memory rewardData = distributor.getTotalRewardByWeek(week);
        assertEq(rewardData[0].token, address(token1), "token1 is not deposited");
        assertEq(rewardData[1].token, address(token2), "token2 is not deposited");
        assertEq(rewardData[0].amount, 100 ether, "amount of token1 is not correct");
        assertEq(rewardData[1].amount, 1000 ether, "amount of token2 is not correct");
    }

    function test_claim() public {
        VeListaDistributor.TokenAmount[] memory tokensAmount = new VeListaDistributor.TokenAmount[](2);
        tokensAmount[0].token = address(token1);
        tokensAmount[0].amount = 100 ether;
        tokensAmount[1].token = address(token2);
        tokensAmount[1].amount = 1000 ether;
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        skip(1 weeks);
        vm.prank(user1);
        veLista.lock(30 ether, 50, true);

        vm.prank(user2);
        veLista.lock(70 ether, 50, true);

        skip(1 weeks);

        vm.startPrank(manager);
        distributor.registerNewToken(address(token1));
        distributor.registerNewToken(address(token2));
        vm.stopPrank();
        skip(1 weeks);
        uint16 week = veLista.getCurrentWeek() - 1;
        vm.prank(manager);
        distributor.depositNewReward(week, tokensAmount);

        VeListaDistributor.TokenAmount[] memory tokenAmounts = distributor.getClaimable(user1);
        assertEq(tokenAmounts.length, 2, "user1 has not claimable tokens");
        assertEq(tokenAmounts[0].token, address(token1), "user1 has not claimable token1");
        assertEq(tokenAmounts[1].token, address(token2), "user1 has not claimable token2");
        assertEq(tokenAmounts[0].amount, 30 ether, "user1 has not claimable amount of token1");
        assertEq(tokenAmounts[1].amount, 300 ether, "user1 has not claimable amount of token2");

        VeListaDistributor.TokenAmount[] memory tokenAmounts2 = distributor.getClaimable(user2);
        assertEq(tokenAmounts2.length, 2, "user2 has not claimable tokens");
        assertEq(tokenAmounts2[0].token, address(token1), "user2 has not claimable token1");
        assertEq(tokenAmounts2[1].token, address(token2), "user2 has not claimable token2");
        assertEq(tokenAmounts2[0].amount, 70 ether, "user2 has not claimable amount of token1");
        assertEq(tokenAmounts2[1].amount, 700 ether, "user2 has not claimable amount of token2");

        vm.prank(user1);
        distributor.claimAll(tokens);
        uint256 user1Token1Balance = token1.balanceOf(user1);
        uint256 user1Token2Balance = token2.balanceOf(user1);
        assertEq(user1Token1Balance, 30 ether, "user1 has not claimed token1");
        assertEq(user1Token2Balance, 300 ether, "user1 has not claimed token2");

        vm.prank(user2);
        distributor.claimAll(tokens);
        uint256 user2Token1Balance = token1.balanceOf(user2);
        uint256 user2Token2Balance = token2.balanceOf(user2);
        assertEq(user2Token1Balance, 70 ether, "user2 has not claimed token1");
        assertEq(user2Token2Balance, 700 ether, "user2 has not claimed token2");

        skip(20 weeks);
        week = veLista.getCurrentWeek() - 1;
        vm.prank(manager);
        distributor.depositNewReward(week, tokensAmount);

        tokenAmounts = distributor.getClaimable(user1);
        assertEq(tokenAmounts.length, 2, "user1 has not claimable tokens");
        assertEq(tokenAmounts[0].token, address(token1), "user1 has not claimable token1");
        assertEq(tokenAmounts[1].token, address(token2), "user1 has not claimable token2");
        assertEq(tokenAmounts[0].amount, 30 ether, "user1 has not claimable amount of token1");
        assertEq(tokenAmounts[1].amount, 300 ether, "user1 has not claimable amount of token2");

        vm.prank(user1);
        distributor.claimAll(tokens);
        user1Token1Balance = token1.balanceOf(user1);
        user1Token2Balance = token2.balanceOf(user1);
        assertEq(user1Token1Balance, 60 ether, "user1 has not claimed token1");
        assertEq(user1Token2Balance, 600 ether, "user1 has not claimed token2");
    }
}
