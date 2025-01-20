pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../contracts/dao/VeListaVault.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VeListaVaultTest is Test {

    address admin = address(0x1);
    address manager = address(0x2);
    address bot = address(0x3);

    address veLista = 0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3;
    address lista = 0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46;
    address autoCompounder = 0x9a0530A81c83D3b0daE720BF91C9254FECC3BF5E;

    VeListaVault veListaVault;


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
    }

    function test_initialize() public {
        VeListaVault veListaVaultImpl = new VeListaVault();
        address zero = address(0x0);

        vm.expectRevert("admin cannot be zero address");
        new ERC1967Proxy(
            address(veListaVaultImpl),
            abi.encodeWithSelector(
                veListaVaultImpl.initialize.selector,
                zero,
                manager,
                bot,
                veLista,
                lista,
                autoCompounder
            )
        );

        vm.expectRevert("manager cannot be zero address");
        new ERC1967Proxy(
            address(veListaVaultImpl),
            abi.encodeWithSelector(
                veListaVaultImpl.initialize.selector,
                admin,
                zero,
                bot,
                veLista,
                lista,
                autoCompounder
            )
        );

        vm.expectRevert("bot cannot be zero address");
        new ERC1967Proxy(
            address(veListaVaultImpl),
            abi.encodeWithSelector(
                veListaVaultImpl.initialize.selector,
                admin,
                manager,
                zero,
                veLista,
                lista,
                autoCompounder
            )
        );

        vm.expectRevert("veLista cannot be zero address");
        new ERC1967Proxy(
            address(veListaVaultImpl),
            abi.encodeWithSelector(
                veListaVaultImpl.initialize.selector,
                admin,
                manager,
                bot,
                zero,
                lista,
                autoCompounder
            )
        );

        vm.expectRevert("lista cannot be zero address");
        new ERC1967Proxy(
            address(veListaVaultImpl),
            abi.encodeWithSelector(
                veListaVaultImpl.initialize.selector,
                admin,
                manager,
                bot,
                veLista,
                zero,
                autoCompounder
            )
        );

        vm.expectRevert("autoCompounder cannot be zero address");
        new ERC1967Proxy(
            address(veListaVaultImpl),
            abi.encodeWithSelector(
                veListaVaultImpl.initialize.selector,
                admin,
                manager,
                bot,
                veLista,
                lista,
                zero
            )
        );
    }

    function test_lock() public {
        deal(lista, bot, 100 ether);

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaVault), 100 ether);

        veListaVault.lock();

        uint256 weight = IVeLista(veLista).balanceOf(address(veListaVault));

        assertEq(5200 ether, weight, "weight error");
        vm.stopPrank();

    }

    function test_unlock() public {
        deal(lista, bot, 100 ether);

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaVault), 100 ether);

        veListaVault.lock();
        vm.stopPrank();

        vm.startPrank(manager);
        veListaVault.disableAutoLock();

        skip(52 weeks);
        veListaVault.unlock();

        uint256 weight = IVeLista(veLista).balanceOf(address(veListaVault));
        assertEq(0, weight, "weight error");

        vm.stopPrank();
    }

    function test_enableDisableAutoLock() public {
        deal(lista, bot, 200 ether);

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaVault), 100 ether);

        veListaVault.lock();
        vm.stopPrank();

        vm.startPrank(manager);

        veListaVault.disableAutoLock();

        assertTrue(!IVeLista(veLista).getLockedData(address(veListaVault)).autoLock, "disableAutoLock error");

        veListaVault.enableAutoLock();
        assertTrue(IVeLista(veLista).getLockedData(address(veListaVault)).autoLock, "disableAutoLock error");

        vm.stopPrank();
    }

    function test_increaseLock() public {
        deal(lista, bot, 200 ether);

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaVault), 100 ether);

        veListaVault.lock();
        vm.stopPrank();

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaVault), 100 ether);

        veListaVault.increaseLock();
        vm.stopPrank();

        uint256 weight = IVeLista(veLista).balanceOf(address(veListaVault));
        assertEq(10400 ether, weight, "weight error");
    }

    function test_withdraw() public {

        deal(lista, bot, 100 ether);

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaVault), 100 ether);

        veListaVault.lock();
        vm.stopPrank();

        vm.startPrank(manager);

        veListaVault.disableAutoLock();
        skip(52 weeks);
        veListaVault.unlock();
        veListaVault.withdraw(manager, 100 ether);

        uint256 balance = IERC20(lista).balanceOf(manager);

        assertEq(100 ether, balance, "balance error");

        vm.stopPrank();
    }

    function test_autoCompound() public {
        deal(lista, bot, 100 ether);

        vm.startPrank(bot);
        IERC20(lista).transfer(address(veListaVault), 100 ether);

        veListaVault.lock();
        vm.stopPrank();

        vm.startPrank(manager);
        veListaVault.disableAutoCompound();
        veListaVault.enableAutoCompound();
        vm.stopPrank();
    }
}