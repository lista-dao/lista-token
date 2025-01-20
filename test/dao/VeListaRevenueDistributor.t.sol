pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../contracts/dao/VeListaVault.sol";
import "../../contracts/dao/VeListaRevenueDistributor.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VeListaRevenueDistributortTest is Test {

    address admin = address(0x1);
    address manager = address(0x2);
    address bot = address(0x3);
    address revenueReceiver = address(0x4);

    address veLista = 0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3;
    address lista = 0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46;
    address autoCompounder = 0x9a0530A81c83D3b0daE720BF91C9254FECC3BF5E;


    VeListaVault veListaVault;
    VeListaRevenueDistributor veListaRevenueDistributor;


    function setUp() public {
        vm.createSelectFork("bsc-main");

        VeListaVault veListaVaultImpl = new VeListaVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(veListaVaultImpl),
            abi.encodeWithSelector(
                VeListaVault.initialize.selector,
                admin,
                manager,
                bot,
                veLista,
                lista,
                autoCompounder
            )
        );

        veListaVault = VeListaVault(address(proxy));

        VeListaRevenueDistributor veListaRevenueDistributorImpl = new VeListaRevenueDistributor();

        ERC1967Proxy proxy2 = new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                VeListaRevenueDistributor.initialize.selector,
                admin,
                manager,
                bot,
                revenueReceiver,
                address(veListaVault),
                lista,
                5000
            )
        );

        veListaRevenueDistributor = VeListaRevenueDistributor(address(proxy2));
    }

    function test_initialize() public {
        VeListaRevenueDistributor veListaRevenueDistributorImpl = new VeListaRevenueDistributor();
        address zero = address(0x0);

        vm.expectRevert("admin cannot be zero address");
        new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                veListaRevenueDistributorImpl.initialize.selector,
                zero,
                manager,
                bot,
                revenueReceiver,
                veLista,
                lista,
                0
            )
        );

        vm.expectRevert("manager cannot be zero address");
        new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                veListaRevenueDistributorImpl.initialize.selector,
                admin,
                zero,
                bot,
                revenueReceiver,
                veLista,
                lista,
                0
            )
        );

        vm.expectRevert("bot cannot be zero address");
        new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                veListaRevenueDistributorImpl.initialize.selector,
                admin,
                manager,
                zero,
                revenueReceiver,
                veLista,
                lista,
                0
            )
        );

        vm.expectRevert("revenueReceiver cannot be zero address");
        new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                veListaRevenueDistributorImpl.initialize.selector,
                admin,
                manager,
                bot,
                zero,
                veLista,
                lista,
                0
            )
        );

        vm.expectRevert("veListaVault cannot be zero address");
        new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                veListaRevenueDistributorImpl.initialize.selector,
                admin,
                manager,
                bot,
                revenueReceiver,
                zero,
                lista,
                0
            )
        );

        vm.expectRevert("lista cannot be zero address");
        new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                veListaRevenueDistributorImpl.initialize.selector,
                admin,
                manager,
                bot,
                revenueReceiver,
                veLista,
                zero,
                0
            )
        );

        vm.expectRevert("vaultPercentage cannot be greater than PRECISION");
        new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                veListaRevenueDistributorImpl.initialize.selector,
                admin,
                manager,
                bot,
                revenueReceiver,
                veLista,
                lista,
                10001
            )
        );

    }

    function test_setRevenueReceiver() public {
        vm.startPrank(manager);
        veListaRevenueDistributor.setRevenueReceiver(address(0x5));
        assertEq(veListaRevenueDistributor.revenueReceiver(), address(0x5), "revenueReceiver error");
        vm.stopPrank();
    }

    function test_setVaultPercentage() public {
        vm.startPrank(manager);
        veListaRevenueDistributor.setVaultPercentage(1000);
        assertEq(veListaRevenueDistributor.vaultPercentage(), 1000, "vaultPercentage error");
        vm.stopPrank();
    }

    function test_distribute() public {
        deal(lista, bot, 100 ether);

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaRevenueDistributor), 100 ether);

        veListaRevenueDistributor.distribute();
        vm.stopPrank();

        assertEq(IERC20(lista).balanceOf(address(veListaVault)), 50 ether, "distribute error");
    }

}