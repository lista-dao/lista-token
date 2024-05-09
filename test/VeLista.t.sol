// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Test, console} from "forge-std/Test.sol";
import {VeLista} from "../contracts/VeLista.sol";
import {ListaToken} from "../contracts/ListaToken.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract VeListaTest is Test {
    VeLista public veLista = VeLista(0x51075B00313292db08f3450f91fCA53Db6Bd0D11);
    ListaToken public lista = ListaToken(0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB);
    ProxyAdmin public proxyAdmin = ProxyAdmin(0xc78f64Cd367bD7d2922088669463FCEE33f50b7c);
    uint256 MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address manager = 0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232;
    address user1 = 0x5a97ba0b0B18a618966303371374EBad4960B7D9;
    address user2 = 0x245b3Ee7fCC57AcAe8c208A563F54d630B5C4eD7;

    address proxyAdminOwner = 0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06;

    function setUp() public {
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        vm.startPrank(manager);
        lista.transfer(user1, 10000 ether);
        lista.transfer(user2, 20000 ether);
        vm.stopPrank();

        address impl = address(new VeLista());
        vm.prank(proxyAdminOwner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(veLista)), impl);
    }

    function test_createLock() public {
        uint256 lockAmount = 10000 ether;
        uint16 lockWeek = 50;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, lockAmount*lockWeek, "weeks 0 totalSupply");

        skip(1 weeks);

        
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, lockAmount*(lockWeek - 1), "weeks 1 user1VeListaBalance");
        assertEq(totalSupply, user1VeListaBalance, "weeks 1 totalSupply");


        uint256 user2LockAmount = 1000 ether;
        uint16 user2LockWeek = 20;
        vm.startPrank(user2);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(user2LockAmount, user2LockWeek, false);
        vm.stopPrank();
        uint256 user2VeListaBalance = veLista.balanceOf(user2);
        assertEq(user2VeListaBalance, user2LockAmount*user2LockWeek, "weeks 1 user2VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user2VeListaBalance + user1VeListaBalance, "weeks 1 totalSupply");

        skip(1 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        user2VeListaBalance = veLista.balanceOf(user2);

        assertEq(user1VeListaBalance, lockAmount*(lockWeek - 2), "weeks 2 user1VeListaBalance");
        assertEq(user2VeListaBalance, user2LockAmount*(user2LockWeek - 1), "weeks 2 user2VeListaBalance");

        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user2VeListaBalance + user1VeListaBalance, "weeks 2 totalSupply");

        skip(20 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        user2VeListaBalance = veLista.balanceOf(user2);

        assertEq(user1VeListaBalance, lockAmount*(lockWeek-22), "weeks 22 user1VeListaBalance");
        assertEq(user2VeListaBalance, 0, "weeks 21 user2VeListaBalance");

        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user1VeListaBalance, "weeks 22 totalSupply");
    }

    function test_extendAmount() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 50;
        uint256 extendAmount = 100 ether;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, lockAmount*lockWeek, "weeks 0 totalSupply");

        vm.prank(user1);
        veLista.increaseAmount(extendAmount);

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, (lockAmount + extendAmount)*lockWeek, "weeks 0 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user1VeListaBalance, "weeks 0 totalSupply");

        skip(1 weeks);
        vm.prank(user1);
        veLista.increaseAmount(extendAmount);

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, (lockAmount + extendAmount*2)*(lockWeek - 1), "weeks 1 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user1VeListaBalance, "weeks 1 totalSupply");
    }

    function test_extendWeek() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, lockAmount*lockWeek, "weeks 0 totalSupply");

        vm.prank(user1);
        veLista.extendWeek(12);

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*12, "weeks 0 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user1VeListaBalance, "weeks 0 totalSupply");

        skip(1 weeks);
        vm.prank(user1);
        veLista.extendWeek(20);

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*20, "weeks 0 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user1VeListaBalance, "weeks 0 totalSupply");
    }

    function test_autoLock() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, true);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, lockAmount*lockWeek, "weeks 0 totalSupply");

        skip(1 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 1 user1VeListaBalance");
        assertEq(totalSupply, user1VeListaBalance, "weeks 1 totalSupply");

        skip(10 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 11 user1VeListaBalance");


        uint256 user2LockAmount = 100 ether;
        uint16 user2LockWeek = 20;
        vm.startPrank(user2);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(user2LockAmount, user2LockWeek, false);
        vm.stopPrank();

        uint256 user2VeListaBalance = veLista.balanceOf(user2);
        assertEq(user2VeListaBalance, user2LockAmount*user2LockWeek, "weeks 11 user2VeListaBalance");

        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user2VeListaBalance + user1VeListaBalance, "weeks 11 totalSupply");

        skip(1 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        user2VeListaBalance = veLista.balanceOf(user2);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 12 user1VeListaBalance");
        assertEq(user2VeListaBalance, user2LockAmount*(user2LockWeek - 1), "weeks 12 user2VeListaBalance");

        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user2VeListaBalance + user1VeListaBalance, "weeks 12 totalSupply");

        vm.prank(user1);
        veLista.increaseAmount(lockAmount);

        vm.prank(user2);
        veLista.increaseAmount(user2LockAmount);

        user1VeListaBalance = veLista.balanceOf(user1);
        user2VeListaBalance = veLista.balanceOf(user2);
        assertEq(user1VeListaBalance, 2*lockAmount*lockWeek, "weeks 12 user1VeListaBalance");
        assertEq(user2VeListaBalance, 2*user2LockAmount*(user2LockWeek-1), "weeks 12 user2VeListaBalance");

        skip(1 weeks);
        vm.prank(user1);
        veLista.extendWeek(20);

        user1VeListaBalance = veLista.balanceOf(user1);
        user2VeListaBalance = veLista.balanceOf(user2);
        assertEq(user1VeListaBalance, 2*lockAmount*20, "weeks 13 user1VeListaBalance");
        assertEq(user2VeListaBalance, 2*user2LockAmount*(user2LockWeek-2), "weeks 13 user2VeListaBalance");

        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, user2VeListaBalance + user1VeListaBalance, "weeks 13 totalSupply");
    }

    function test_disableAutoLock() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        veLista.enableAutoLock();
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, lockAmount*lockWeek, "weeks 0 totalSupply");

        skip(1 weeks);
        vm.prank(user1);
        veLista.disableAutoLock();
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 1 user1VeListaBalance");
        assertEq(totalSupply, user1VeListaBalance, "weeks 1 totalSupply");

        skip(10 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, 0, "weeks 11 user1VeListaBalance");
        assertEq(totalSupply, 0, "weeks 11 totalSupply");
    }

    function test_claim() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, lockAmount*lockWeek, "weeks 0 totalSupply");
        uint256 user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether - 100 ether, "weeks 0 user1ListaBalance");

        skip(10 weeks);

        vm.prank(user1);
        veLista.claim();

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, 0, "weeks 10 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, 0, "weeks 10 totalSupply");

        user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether, "weeks 10 user1ListaBalance");

    }

    function test_earlyClaim() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, lockAmount*lockWeek, "weeks 0 totalSupply");
        uint256 user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether - 100 ether, "weeks 0 user1ListaBalance");

        vm.prank(user1);
        veLista.earlyClaim();

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, 0, "weeks 0 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, 0, "weeks 0 totalSupply");
        user1ListaBalance = lista.balanceOf(user1);
        uint256 penalty = 100 ether * lockWeek / veLista.MAX_LOCK_WEEKS();
        assertEq(user1ListaBalance, 10000 ether - penalty, "weeks 0 user1ListaBalance");

        vm.prank(user1);
        veLista.lock(lockAmount, lockWeek, false);

        skip(5 weeks);
        vm.prank(user1);
        veLista.earlyClaim();
        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, 0, "weeks 5 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, 0, "weeks 5 totalSupply");
        user1ListaBalance = lista.balanceOf(user1);
        penalty += 100 ether * (lockWeek - 5) / veLista.MAX_LOCK_WEEKS();
        assertEq(user1ListaBalance, 10000 ether - penalty, "weeks 5 user1ListaBalance");

        vm.prank(user1);
        veLista.lock(lockAmount, lockWeek, true);
        skip(5 weeks);
        vm.prank(user1);
        veLista.earlyClaim();
        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, 0, "weeks 10 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, 0, "weeks 10 totalSupply");
        user1ListaBalance = lista.balanceOf(user1);
        penalty += 100 ether * lockWeek / veLista.MAX_LOCK_WEEKS();
        assertEq(user1ListaBalance, 10000 ether - penalty, "weeks 10 user1ListaBalance");
    }
}
