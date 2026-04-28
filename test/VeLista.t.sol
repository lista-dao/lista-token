// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Test, console} from "forge-std/Test.sol";
import {VeLista} from "../contracts/VeLista.sol";
import {ListaToken} from "../contracts/ListaToken.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VeListaTest is Test {
    VeLista public veLista;
    ListaToken public lista;
    uint256 MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address manager = 0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232;
    address user1 = 0x5a97ba0b0B18a618966303371374EBad4960B7D9;
    address user2 = 0x245b3Ee7fCC57AcAe8c208A563F54d630B5C4eD7;

    address proxyAdminOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;

    address listaUser = 0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06;

    function setUp() public {

        lista = new ListaToken(listaUser);

        VeLista veListaImpl = new VeLista();
        ERC1967Proxy veListaProxy = new ERC1967Proxy(
            address(veListaImpl),
            abi.encodeWithSelector(veListaImpl.initialize.selector, manager, manager, block.timestamp / 1 weeks * 1 weeks, address(lista), manager)
        );
        veLista = VeLista(address(veListaProxy));

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        vm.startPrank(listaUser);
        lista.transfer(user1, 10000 ether);
        lista.transfer(user2, 20000 ether);
        vm.stopPrank();

        skip(100 weeks);
    }

    function test_createLock() public {
        uint256 lockAmount = 1000 ether;
        uint16 lockWeek = 50;

        uint256 startTotalSupply = veLista.totalSupply();

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");

        skip(1 weeks);

        
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, lockAmount*(lockWeek - 1), "weeks 1 user1VeListaBalance");
        assertEq(totalSupply, startTotalSupply+user1VeListaBalance, "weeks 1 totalSupply");


        uint256 user2LockAmount = 1000 ether;
        uint16 user2LockWeek = 20;
        vm.startPrank(user2);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(user2LockAmount, user2LockWeek, false);
        vm.stopPrank();
        uint256 user2VeListaBalance = veLista.balanceOf(user2);
        assertEq(user2VeListaBalance, user2LockAmount*user2LockWeek, "weeks 1 user2VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+user2VeListaBalance + user1VeListaBalance, "weeks 1 totalSupply");

        skip(1 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        user2VeListaBalance = veLista.balanceOf(user2);

        assertEq(user1VeListaBalance, lockAmount*(lockWeek - 2), "weeks 2 user1VeListaBalance");
        assertEq(user2VeListaBalance, user2LockAmount*(user2LockWeek - 1), "weeks 2 user2VeListaBalance");

        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+user2VeListaBalance + user1VeListaBalance, "weeks 2 totalSupply");

        skip(20 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        user2VeListaBalance = veLista.balanceOf(user2);

        assertEq(user1VeListaBalance, lockAmount*(lockWeek-22), "weeks 22 user1VeListaBalance");
        assertEq(user2VeListaBalance, 0, "weeks 21 user2VeListaBalance");

        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+user1VeListaBalance, "weeks 22 totalSupply");
    }

    function test_extendAmount() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 50;
        uint256 extendAmount = 100 ether;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");

        vm.prank(user1);
        veLista.increaseAmount(extendAmount);

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, (lockAmount + extendAmount)*lockWeek, "weeks 0 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+user1VeListaBalance, "weeks 0 totalSupply");

        skip(1 weeks);
        vm.prank(user1);
        veLista.increaseAmount(extendAmount);

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, (lockAmount + extendAmount*2)*(lockWeek - 1), "weeks 1 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+user1VeListaBalance, "weeks 1 totalSupply");
    }

    function test_extendWeek() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");

        vm.prank(user1);
        veLista.extendWeek(12);

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*12, "weeks 0 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+user1VeListaBalance, "weeks 0 totalSupply");

        skip(1 weeks);
        vm.prank(user1);
        veLista.extendWeek(20);

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*20, "weeks 0 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+user1VeListaBalance, "weeks 0 totalSupply");
    }

    function test_autoLock() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, true);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");

        skip(1 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 1 user1VeListaBalance");
        assertEq(totalSupply, startTotalSupply+user1VeListaBalance, "weeks 1 totalSupply");

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
        assertEq(totalSupply, startTotalSupply+user2VeListaBalance + user1VeListaBalance, "weeks 11 totalSupply");

        skip(1 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        user2VeListaBalance = veLista.balanceOf(user2);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 12 user1VeListaBalance");
        assertEq(user2VeListaBalance, user2LockAmount*(user2LockWeek - 1), "weeks 12 user2VeListaBalance");

        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+user2VeListaBalance + user1VeListaBalance, "weeks 12 totalSupply");

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
        assertEq(totalSupply, startTotalSupply+user2VeListaBalance + user1VeListaBalance, "weeks 13 totalSupply");
    }

    function test_disableAutoLock() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        veLista.enableAutoLock();
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");

        skip(1 weeks);
        vm.prank(user1);
        veLista.disableAutoLock();
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 1 user1VeListaBalance");
        assertEq(totalSupply, startTotalSupply+user1VeListaBalance, "weeks 1 totalSupply");

        skip(10 weeks);
        user1VeListaBalance = veLista.balanceOf(user1);
        totalSupply = veLista.totalSupply();
        assertEq(user1VeListaBalance, 0, "weeks 11 user1VeListaBalance");
        assertEq(totalSupply, startTotalSupply, "weeks 11 totalSupply");
    }

    function test_claim() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");
        uint256 user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether - 100 ether, "weeks 0 user1ListaBalance");

        skip(10 weeks);

        vm.prank(user1);
        veLista.claim();

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, 0, "weeks 10 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply, "weeks 10 totalSupply");

        user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether, "weeks 10 user1ListaBalance");

    }

    function test_earlyClaim() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");
        uint256 user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether - 100 ether, "weeks 0 user1ListaBalance");

        vm.prank(user1);
        veLista.earlyClaim();

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, 0, "weeks 0 user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply, "weeks 0 totalSupply");
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
        assertEq(totalSupply, startTotalSupply, "weeks 5 totalSupply");
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
        assertEq(totalSupply, startTotalSupply, "weeks 10 totalSupply");
        user1ListaBalance = lista.balanceOf(user1);
        penalty += 100 ether * lockWeek / veLista.MAX_LOCK_WEEKS();
        assertEq(user1ListaBalance, 10000 ether - penalty, "weeks 10 user1ListaBalance");
    }

    function test_balanceNotLock() public {
        assertEq(veLista.balanceOfAtWeek(user1, 0), 0, "weeks 0 balance");
    }

    function test_balanceLock() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint16 currentWeek = veLista.getCurrentWeek();

        uint256 balance = veLista.balanceOfAtWeek(user1, currentWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 0 balance");

        skip(1 weeks);

        currentWeek = veLista.getCurrentWeek();
        balance = veLista.balanceOfAtWeek(user1, currentWeek);
        assertEq(balance, lockAmount*(lockWeek - 1), "weeks 1 balance");
    }

    function test_balanceLockNotFind() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 balance = veLista.balanceOfAtWeek(user1, 1);
        assertEq(balance, 0, "weeks 0 balance");

    }

    function test_balanceLockExpired() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint16 currentWeek = veLista.getCurrentWeek();

        skip(100 weeks);

        uint256 balance = veLista.balanceOfAtWeek(user1, currentWeek+9);
        assertEq(balance, lockAmount, "weeks 9 balance");
        balance = veLista.balanceOfAtWeek(user1, currentWeek+10);
        assertEq(balance, 0, "weeks 10 balance");
        balance = veLista.balanceOfAtWeek(user1, currentWeek+20);
        assertEq(balance, 0, "weeks 20 balance");
        balance = veLista.balanceOfAtWeek(user1, currentWeek+100);
        assertEq(balance, 0, "weeks 100 balance");
    }

    function test_balanceAutoLock() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, true);
        vm.stopPrank();

        uint16 currentWeek = veLista.getCurrentWeek();

        uint256 balance = veLista.balanceOfAtWeek(user1, currentWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 0 balance");

        skip(100 weeks);

        balance = veLista.balanceOfAtWeek(user1, currentWeek+10);
        assertEq(balance, lockAmount*lockWeek, "weeks 10 balance");
        balance = veLista.balanceOfAtWeek(user1, currentWeek+20);
        assertEq(balance, lockAmount*lockWeek, "weeks 20 balance");
        balance = veLista.balanceOfAtWeek(user1, currentWeek+100);
        assertEq(balance, lockAmount*lockWeek, "weeks 100 balance");
    }

    function test_balanceManyWeek() public {
        uint256 lockAmount = 1e16;
        uint16 lockWeek = 1;

        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);

        uint16 firstWeek = veLista.getCurrentWeek();
        uint16 lastWeek = firstWeek+100;

        for (uint16 i = firstWeek; i <= lastWeek; i++) {
            veLista.lock(lockAmount, lockWeek, false);
            skip(1 weeks);
            veLista.claim();
        }
        vm.stopPrank();

        console.log("firstWeek: ", firstWeek);
        uint256 balance = veLista.balanceOfAtWeek(user1, firstWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 0 balance");

        console.log("lastWeek: ", lastWeek);
        balance = veLista.balanceOfAtWeek(user1, lastWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 100 balance");
    }

    function test_balanceNormal() public {
        uint256 lockAmount = 1e16;
        uint16 lockWeek = 1;

        uint16 firstWeek = veLista.getCurrentWeek();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);

        veLista.lock(lockAmount, lockWeek, false);

        skip(1 weeks);
        veLista.claim();
        veLista.lock(lockAmount, lockWeek, false);

        skip(2 weeks);
        veLista.claim();
        veLista.lock(lockAmount, lockWeek, false);

        skip(3 weeks);
        veLista.claim();
        veLista.lock(lockAmount, lockWeek, false);

        vm.stopPrank();

        uint256 balance = veLista.balanceOfAtWeek(user1, 0);
        assertEq(balance, 0, "weeks 0 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 1 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+1);
        assertEq(balance, lockAmount*lockWeek, "weeks 2 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+2);
        assertEq(balance, 0, "weeks 3 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+3);
        assertEq(balance, lockAmount*lockWeek, "weeks 4 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+4);
        assertEq(balance, 0, "weeks 5 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+5);
        assertEq(balance, 0, "weeks 6 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+6);
        assertEq(balance, lockAmount*lockWeek, "weeks 7 balance");

    }

    function test_balanceTwoWeek() public {
        uint256 lockAmount = 1e16;
        uint16 lockWeek = 1;

        uint16 firstWeek = veLista.getCurrentWeek();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);

        veLista.lock(lockAmount, lockWeek, false);

        skip(2 weeks);

        veLista.claim();
        veLista.lock(lockAmount, lockWeek, false);

        vm.stopPrank();

        uint16 lastWeek = veLista.getCurrentWeek();

        uint256 balance = veLista.balanceOfAtWeek(user1, firstWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 1 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+1);
        assertEq(balance, 0, "weeks 2 balance");
        balance = veLista.balanceOfAtWeek(user1, lastWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 3 balance");
    }

    function test_balanceThreeWeek() public {
        uint256 lockAmount = 1e16;
        uint16 lockWeek = 1;

        uint16 firstWeek = veLista.getCurrentWeek();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);

        veLista.lock(lockAmount, lockWeek, false);

        skip(2 weeks);

        veLista.claim();
        veLista.lock(lockAmount, lockWeek, false);

        skip(1 weeks);
        veLista.claim();
        veLista.lock(lockAmount, lockWeek, false);

        vm.stopPrank();

        uint16 lastWeek = veLista.getCurrentWeek();

        uint256 balance = veLista.balanceOfAtWeek(user1, firstWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 1 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+1);
        assertEq(balance, 0, "weeks 2 balance");
        balance = veLista.balanceOfAtWeek(user1, firstWeek+2);
        assertEq(balance, lockAmount*lockWeek, "weeks 3 balance");
        balance = veLista.balanceOfAtWeek(user1, lastWeek);
        assertEq(balance, lockAmount*lockWeek, "weeks 4 balance");
    }

    function test_setFreePenaltyPeriod() public {
        uint256 currentTime = block.timestamp;
        skip(10);
        vm.startPrank(manager);
        vm.expectRevert(bytes("invalid time period"));
        veLista.setFreePenaltyPeriod(currentTime + 10, currentTime + 10);
        veLista.setFreePenaltyPeriod(currentTime + 10, currentTime + 11);
        vm.stopPrank();

        assertEq(veLista.freePenaltyStartTime(), currentTime + 10, "freePenaltyPeriodStart");
        assertEq(veLista.freePenaltyEndTime(), currentTime + 11, "freePenaltyPeriodEnd");
    }

    function test_setEarlyClaimBlacklist() public {
        vm.startPrank(manager);
        veLista.setEarlyClaimBlacklist(user1, true);
        assertTrue(veLista.earlyClaimBlacklist(user1), "blacklist not set");
        vm.expectRevert(bytes("already set"));
        veLista.setEarlyClaimBlacklist(user1, true);
        veLista.setEarlyClaimBlacklist(user1, false);
        assertFalse(veLista.earlyClaimBlacklist(user1), "blacklist not removed");
        vm.stopPrank();
    }

    function test_earlyClaimDuringFreePenaltyPeriod() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");
        uint256 user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether - 100 ether, "weeks 0 user1ListaBalance");

        vm.startPrank(manager);
        uint256 currentTime = block.timestamp;
        veLista.setFreePenaltyPeriod(currentTime + 1 days, currentTime + 3 days);
        vm.stopPrank();

        skip(1 days);

        vm.prank(user1);
        veLista.earlyClaim();

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, 0, "weeks 2 days user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply, "weeks 2 days totalSupply");

        user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether, "weeks 2 days user1ListaBalance");
    }

    function test_earlyClaimAfterFreePenaltyPeriod() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");
        uint256 user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether - 100 ether, "weeks 0 user1ListaBalance");

        vm.startPrank(manager);
        uint256 currentTime = block.timestamp;
        veLista.setFreePenaltyPeriod(currentTime + 1 days, currentTime + 3 days);
        vm.stopPrank();

        skip(4 days);

        vm.prank(user1);
        veLista.earlyClaim();

        user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, 0, "weeks 4 days user1VeListaBalance");
        totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply, "weeks 4 days totalSupply");

        user1ListaBalance = lista.balanceOf(user1);
        uint256 penalty = 100 ether * lockWeek / veLista.MAX_LOCK_WEEKS();
        assertEq(user1ListaBalance, 10000 ether - penalty, "weeks 4 days user1ListaBalance");
    }

    function test_earlyClaimBlacklisted() public {
        uint256 lockAmount = 100 ether;
        uint16 lockWeek = 10;

        uint256 startTotalSupply = veLista.totalSupply();
        vm.startPrank(user1);
        lista.approve(address(veLista), MAX_UINT);
        veLista.lock(lockAmount, lockWeek, false);
        vm.stopPrank();

        uint256 user1VeListaBalance = veLista.balanceOf(user1);
        assertEq(user1VeListaBalance, lockAmount*lockWeek, "weeks 0 user1VeListaBalance");
        uint256 totalSupply = veLista.totalSupply();
        assertEq(totalSupply, startTotalSupply+lockAmount*lockWeek, "weeks 0 totalSupply");
        uint256 user1ListaBalance = lista.balanceOf(user1);
        assertEq(user1ListaBalance, 10000 ether - 100 ether, "weeks 0 user1ListaBalance");

        vm.startPrank(manager);
        veLista.setEarlyClaimBlacklist(user1, true);
        vm.stopPrank();

        skip(1 weeks);

        vm.prank(user1);
        vm.expectRevert(bytes("early claim is blacklisted"));
        veLista.earlyClaim();
    }
}
