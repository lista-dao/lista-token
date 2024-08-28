// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../../contracts/dao/ListaRevenueDistributor.sol";

contract ListaRevenueDistributorTest is Test {
    address admin = address(0x1A11AA);
    address manager = address(0x2A11AA);
    address autoBuybackAddress = address(0x3A11AA);
    address revenueWalletAddress = address(0x4A11AA);
    address proxyAdminOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;

    uint256 mainnet;

    ListaRevenueDistributor listaRevenueDistributor;

    IERC20 slisBNB;

    IERC20 lisUSD;

    IERC20 ETH;

    function setUp() public {
        mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");
        slisBNB = IERC20(0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B);
        lisUSD = IERC20(0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5);
        ETH = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);

        ListaRevenueDistributor listaRevenueDistributorImpl = new ListaRevenueDistributor();
        TransparentUpgradeableProxy listaRevenueDistributorProxy = new TransparentUpgradeableProxy(
            address(listaRevenueDistributorImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint128)",
                admin, manager, autoBuybackAddress, revenueWalletAddress, 7e17
            )
        );
        listaRevenueDistributor = ListaRevenueDistributor(address(listaRevenueDistributorProxy));

        assertEq(7e17, listaRevenueDistributor.distributeRate());
    }

    function test_revenueDistributor_setUp() public {
        assertEq(autoBuybackAddress, listaRevenueDistributor.autoBuybackAddress());
        assertEq(revenueWalletAddress, listaRevenueDistributor.revenueWalletAddress());
    }

    function test_revenueDistributor_distributeTokens_acl() public {
        vm.startPrank(admin);
        vm.expectRevert("AccessControl: account 0x00000000000000000000000000000000001a11aa is missing role 0xaf290d8680820aad922855f39b306097b20e28774d6c1ad35a20325630c3a02c");

        address[] memory tokens = new address[](1);
        tokens[0] = address(lisUSD);
        listaRevenueDistributor.distributeTokens(tokens);
        vm.stopPrank();
    }

    function test_revenueDistributor_distributeTokens_lisUSD() public {
        deal(address(lisUSD), address(listaRevenueDistributor), 123e18);

        assertEq(0, lisUSD.balanceOf(autoBuybackAddress));
        assertEq(0, lisUSD.balanceOf(revenueWalletAddress));

        vm.startPrank(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(lisUSD);
        listaRevenueDistributor.distributeTokens(tokens);
        vm.stopPrank();

        assertEq(123e18 * 7e17 / 1e18, lisUSD.balanceOf(autoBuybackAddress));
        assertEq(123e18 - (123e18 * 7e17 / 1e18), lisUSD.balanceOf(revenueWalletAddress));
    }

    function test_revenueDistributor_distributeTokens_multi() public {
        deal(address(lisUSD), address(listaRevenueDistributor), 123e18);
        deal(address(slisBNB), address(listaRevenueDistributor), 456e18);

        assertEq(0, lisUSD.balanceOf(autoBuybackAddress));
        assertEq(0, lisUSD.balanceOf(revenueWalletAddress));
        assertEq(0, slisBNB.balanceOf(autoBuybackAddress));
        assertEq(0, slisBNB.balanceOf(revenueWalletAddress));

        vm.startPrank(manager);
        address[] memory tokens = new address[](2);
        tokens[0] = address(lisUSD);
        tokens[1] = address(slisBNB);
        listaRevenueDistributor.distributeTokens(tokens);
        vm.stopPrank();

        assertEq(123e18 * 7e17 / 1e18, lisUSD.balanceOf(autoBuybackAddress));
        assertEq(123e18 - (123e18 * 7e17 / 1e18), lisUSD.balanceOf(revenueWalletAddress));
        assertEq(456e18 * 7e17 / 1e18, slisBNB.balanceOf(autoBuybackAddress));
        assertEq(456e18 - (456e18 * 7e17 / 1e18), slisBNB.balanceOf(revenueWalletAddress));
    }

    function test_revenueDistributor_changeAutoBuybackAddress_acl() public {
        vm.startPrank(manager);
        vm.expectRevert("AccessControl: account 0x00000000000000000000000000000000002a11aa is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        listaRevenueDistributor.changeAutoBuybackAddress(address(0x123456));
        vm.stopPrank();
    }

    function test_revenueDistributor_changeAutoBuybackAddress_ok() public {
        assertEq(address(0x3A11AA), listaRevenueDistributor.autoBuybackAddress());

        vm.startPrank(admin);
        listaRevenueDistributor.changeAutoBuybackAddress(address(0x123456));
        vm.stopPrank();

        assertEq(address(0x123456), listaRevenueDistributor.autoBuybackAddress());
    }
}
