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
    address listaToWalletAddress = address(0x5A11AA);
    address lisUSDCostToAddress = address(0x6A11AA);
    address proxyAdminOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;

    uint256 mainnet;

    ListaRevenueDistributor listaRevenueDistributor;

    IERC20 slisBNB;

    IERC20 lisUSD;

    IERC20 ETH;

    IERC20 lista;

    function setUp() public {
        mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");
        slisBNB = IERC20(0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B);
        lisUSD = IERC20(0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5);
        ETH = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
        lista = IERC20(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46);

        ListaRevenueDistributor listaRevenueDistributorImpl = new ListaRevenueDistributor();
        TransparentUpgradeableProxy listaRevenueDistributorProxy = new TransparentUpgradeableProxy(
            address(listaRevenueDistributorImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,uint128)",
                admin, manager, address(lista), autoBuybackAddress, revenueWalletAddress, listaToWalletAddress, 7e17
            )
        );
        listaRevenueDistributor = ListaRevenueDistributor(address(listaRevenueDistributorProxy));
        assertEq(7e17, listaRevenueDistributor.distributeRate());

        address[] memory tokens = new address[](4);
        tokens[0] = address(slisBNB);
        tokens[1] = address(lisUSD);
        tokens[2] = address(ETH);
        tokens[3] = address(lista);

        vm.startPrank(admin);
        listaRevenueDistributor.addTokensToWhitelist(tokens);
        listaRevenueDistributor.changeCostToAddress(lisUSDCostToAddress);
        vm.stopPrank();

        assertTrue(listaRevenueDistributor.tokenWhitelist(address(slisBNB)));
        assertTrue(listaRevenueDistributor.tokenWhitelist(address(lisUSD)));
    }

    function test_revenueDistributor_setUp() public {
        assertEq(autoBuybackAddress, listaRevenueDistributor.autoBuybackAddress());
        assertEq(revenueWalletAddress, listaRevenueDistributor.revenueWalletAddress());
        assertEq(address(lista), listaRevenueDistributor.listaTokenAddress());
        assertEq(listaToWalletAddress, listaRevenueDistributor.listaDistributeToAddress());
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
        assertEq(0, lisUSD.balanceOf(listaToWalletAddress));

        vm.startPrank(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(lisUSD);
        listaRevenueDistributor.distributeTokens(tokens);
        vm.stopPrank();

        assertEq(0, lisUSD.balanceOf(listaToWalletAddress));
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

    function test_revenueDistributor_distributeTokens_lista() public {
        deal(address(lista), address(listaRevenueDistributor), 123e18);

        assertEq(0, lista.balanceOf(autoBuybackAddress));
        assertEq(0, lista.balanceOf(revenueWalletAddress));
        assertEq(0, lista.balanceOf(listaToWalletAddress));

        vm.startPrank(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(lista);
        listaRevenueDistributor.distributeTokens(tokens);
        vm.stopPrank();


        assertEq(0, lista.balanceOf(autoBuybackAddress));
        assertEq(123e18 * 7e17 / 1e18, lista.balanceOf(listaToWalletAddress));
        assertEq(123e18 - (123e18 * 7e17 / 1e18), lista.balanceOf(revenueWalletAddress));
    }

    function test_revenueDistributor_distributeTokens_not_whitelist() public {
        IERC20 usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
        deal(address(usdc), address(listaRevenueDistributor), 123e18);

        assertEq(0, usdc.balanceOf(autoBuybackAddress));
        assertEq(0, usdc.balanceOf(revenueWalletAddress));
        assertEq(0, usdc.balanceOf(listaToWalletAddress));

        vm.startPrank(manager);
        vm.expectRevert("token not whitelisted");
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        listaRevenueDistributor.distributeTokens(tokens);
        vm.stopPrank();
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

    function test_distributeTokenWithCost() public {
        deal(address(lisUSD), address(listaRevenueDistributor), 123e18);

        assertEq(0, lista.balanceOf(autoBuybackAddress));
        assertEq(0, lista.balanceOf(revenueWalletAddress));
        assertEq(0, lista.balanceOf(listaToWalletAddress));
        assertEq(0, lista.balanceOf(lisUSDCostToAddress));


        vm.startPrank(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(lisUSD);
        uint256[] memory costs = new uint256[](1);
        costs[0] = 3e18;
        listaRevenueDistributor.distributeTokensWithCost(tokens, costs);
        vm.stopPrank();

        assertEq(0, lisUSD.balanceOf(listaToWalletAddress));
        assertEq(120e18 * 7e17 / 1e18, lisUSD.balanceOf(autoBuybackAddress));
        assertEq(120e18 - (120e18 * 7e17 / 1e18), lisUSD.balanceOf(revenueWalletAddress));
        assertEq(3e18, lisUSD.balanceOf(lisUSDCostToAddress));
    }

    function test_distributeTokenWithCost_all_balance() public {
        deal(address(lisUSD), address(listaRevenueDistributor), 123e18);

        assertEq(0, lista.balanceOf(autoBuybackAddress));
        assertEq(0, lista.balanceOf(revenueWalletAddress));
        assertEq(0, lista.balanceOf(listaToWalletAddress));
        assertEq(0, lista.balanceOf(lisUSDCostToAddress));


        vm.startPrank(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(lisUSD);
        uint256[] memory costs = new uint256[](1);
        costs[0] = 125e18;
        listaRevenueDistributor.distributeTokensWithCost(tokens, costs);
        vm.stopPrank();

        assertEq(0, lisUSD.balanceOf(listaToWalletAddress));
        assertEq(0, lisUSD.balanceOf(autoBuybackAddress));
        assertEq(0, lisUSD.balanceOf(revenueWalletAddress));
        assertEq(123e18, lisUSD.balanceOf(lisUSDCostToAddress));
    }

    function test_distributeWithCosts() public {
        deal(address(lisUSD), address(listaRevenueDistributor), 123e18);
        address costTo = address(0x123456);

        assertEq(0, lista.balanceOf(autoBuybackAddress));
        assertEq(0, lista.balanceOf(revenueWalletAddress));
        assertEq(0, lista.balanceOf(listaToWalletAddress));
        assertEq(0, lista.balanceOf(costTo));


        vm.startPrank(manager);

        listaRevenueDistributor.whitelistCostToAddress(costTo);
        assertTrue(listaRevenueDistributor.costToWhitelist(costTo));

        ListaRevenueDistributor.Cost memory _cost = ListaRevenueDistributor.Cost({
            token: address(lisUSD),
            amount: 3e18,
            costTo: costTo
        });

        ListaRevenueDistributor.Cost[] memory costs = new ListaRevenueDistributor.Cost[](1);
        costs[0] = _cost;
        address[] memory tokens = new address[](1);
        tokens[0] = address(lisUSD);

        listaRevenueDistributor.distributeWithCosts(costs, tokens);
        vm.stopPrank();

        assertEq(0, lisUSD.balanceOf(listaToWalletAddress));
        assertEq(120e18 * 7e17 / 1e18, lisUSD.balanceOf(autoBuybackAddress));
        assertEq(120e18 - (120e18 * 7e17 / 1e18), lisUSD.balanceOf(revenueWalletAddress));
        assertEq(3e18, lisUSD.balanceOf(costTo));
    }

    function test_distributeWithCosts_all_balance() public {
        deal(address(lisUSD), address(listaRevenueDistributor), 123e18);
        address costTo = address(0x1234567);

        assertEq(0, lista.balanceOf(autoBuybackAddress));
        assertEq(0, lista.balanceOf(revenueWalletAddress));
        assertEq(0, lista.balanceOf(listaToWalletAddress));
        assertEq(0, lista.balanceOf(costTo));


        vm.startPrank(manager);

        ListaRevenueDistributor.Cost memory _cost = ListaRevenueDistributor.Cost({
            token: address(lisUSD),
            amount: 123e18,
            costTo: costTo
        });

        ListaRevenueDistributor.Cost[] memory costs = new ListaRevenueDistributor.Cost[](1);
        costs[0] = _cost;
        address[] memory tokens = new address[](1);
        tokens[0] = address(lisUSD);

        vm.expectRevert("costTo address not whitelisted");
        listaRevenueDistributor.distributeWithCosts(costs, tokens);

        listaRevenueDistributor.whitelistCostToAddress(costTo);
        listaRevenueDistributor.distributeWithCosts(costs, tokens); // success
        vm.stopPrank();

        assertEq(0, lisUSD.balanceOf(listaToWalletAddress));
        assertEq(0, lisUSD.balanceOf(autoBuybackAddress));
        assertEq(0, lisUSD.balanceOf(revenueWalletAddress));
        assertEq(123e18, lisUSD.balanceOf(costTo));
    }
}
