pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../contracts/dao/VeListaRevenueDistributor.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VeListaRevenueDistributortTest is Test {

    address admin = address(0x1);
    address manager = address(0x2);
    address bot = address(0x3);
    address revenueReceiver = address(0x4);

    address veLista = 0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3;
    address lista = 0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46;


    VeListaRevenueDistributor veListaRevenueDistributor;


    function setUp() public {
        vm.createSelectFork("bsc");

        VeListaRevenueDistributor veListaRevenueDistributorImpl = new VeListaRevenueDistributor();

        ERC1967Proxy proxy2 = new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                VeListaRevenueDistributor.initialize.selector,
                admin,
                manager,
                bot,
                revenueReceiver,
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
                zero,
                0
            )
        );

        vm.expectRevert("burnPercentage cannot be greater than PRECISION");
        new ERC1967Proxy(
            address(veListaRevenueDistributorImpl),
            abi.encodeWithSelector(
                veListaRevenueDistributorImpl.initialize.selector,
                admin,
                manager,
                bot,
                revenueReceiver,
                lista,
                10001
            )
        );

    }

    function test_setRevenueReceiver() public {
        vm.startPrank(admin);
        veListaRevenueDistributor.setRevenueReceiver(address(0x5));
        assertEq(veListaRevenueDistributor.revenueReceiver(), address(0x5), "revenueReceiver error");
        vm.stopPrank();
    }

    function test_setBurnPercentage() public {
        vm.startPrank(admin);
        veListaRevenueDistributor.setBurnPercentage(1000);
        assertEq(veListaRevenueDistributor.burnPercentage(), 1000, "burnPercentage error");
        vm.stopPrank();
    }

    function test_distribute() public {
        deal(lista, bot, 100 ether);

        uint256 beforeRevenueReceiver = IERC20(lista).balanceOf(revenueReceiver);
        uint256 beforeDead = IERC20(lista).balanceOf(address(0xdead));

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaRevenueDistributor), 100 ether);

        veListaRevenueDistributor.distribute();
        vm.stopPrank();

        uint256 afterRevenueReceiver = IERC20(lista).balanceOf(revenueReceiver);
        uint256 afterDead = IERC20(lista).balanceOf(address(0xdead));
        assertEq(afterRevenueReceiver - beforeRevenueReceiver, 50 ether, "revenueReceiver error");
        assertEq(afterDead - beforeDead, 50 ether, "dead error");

    }

}