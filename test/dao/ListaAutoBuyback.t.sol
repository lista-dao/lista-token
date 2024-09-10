// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../../contracts/dao/ListaAutoBuyback.sol";

contract ListaAutoBuyBackTest is Test {
    address admin = address(0x1A11AA);
    address manager = address(0x2A11AA);
    address bot = address(0x3A11AA);
    address defaultReceiver = 0x78Ab74C7EC3592B5298CB912f31bD8Fb80A57DC0;
    address proxyAdminOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;
    address oneInchRouter = 0x111111125421cA6dc452d289314280a0f8842A65;

    uint256 mainnet;

    ListaAutoBuyback listaAutoBuyBack;

    IERC20 lisUSD;


    function setUp() public {
        mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");
        lisUSD = IERC20(0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5);

        ListaAutoBuyback autoPaybackImpl = new ListaAutoBuyback();
        TransparentUpgradeableProxy listaAutoBuyBackProxy = new TransparentUpgradeableProxy(
            address(autoPaybackImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                admin, manager, bot, defaultReceiver, oneInchRouter
            )
        );
        listaAutoBuyBack = ListaAutoBuyback(address(listaAutoBuyBackProxy));

        assertEq(defaultReceiver, listaAutoBuyBack.defaultReceiver());
    }

    function test_autoBuyBack_setUp() public {
        assertEq(true, listaAutoBuyBack.oneInchRouterWhitelist(oneInchRouter));
    }

    function test_autoBuyBack_buyback_acl() public {
        bytes memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000fceb31a79f71ac9cbdcf853519c1b12d379edc46000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000078ab74c7ec3592b5298cb912f31bd8fb80a57dc0000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000003f06640a9221e160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c30000000000000000000000000000000000000000000000000001a500017700a007e5c0d20000000000000000000000000000000000000000000000000001530000f051200520451b19ad0bb00ed35ef391086a692cfc74b20782b6d8c4551b9760e74c0545a9bcd90bdc41e500449908fc8b0000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000066d57bb802a000000000000000000000000000000000000000000000000003f06640a9221e16ee63c1e5812c533e2c2b4fd1172b5a0a0178805be1526a15a755d398326f99059ff775485246999027b3197955111111125421ca6dc452d289314280a0f8842a650020d6bdbf78fceb31a79f71ac9cbdcf853519c1b12d379edc46111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000098dd6ed1";

        vm.startPrank(manager);
        vm.expectRevert("AccessControl: account 0x00000000000000000000000000000000002a11aa is missing role 0x902cbe3a02736af9827fb6a90bada39e955c0941e08f0c63b3a662a7b17a4e2b");
        listaAutoBuyBack.buyback(address(lisUSD), 100e18, oneInchRouter, data);
        vm.stopPrank();
    }

    function test_autoBuyBack_buyback_acl_pass() public {
        bytes memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000fceb31a79f71ac9cbdcf853519c1b12d379edc46000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000078ab74c7ec3592b5298cb912f31bd8fb80a57dc0000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000003f06640a9221e160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c30000000000000000000000000000000000000000000000000001a500017700a007e5c0d20000000000000000000000000000000000000000000000000001530000f051200520451b19ad0bb00ed35ef391086a692cfc74b20782b6d8c4551b9760e74c0545a9bcd90bdc41e500449908fc8b0000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000066d57bb802a000000000000000000000000000000000000000000000000003f06640a9221e16ee63c1e5812c533e2c2b4fd1172b5a0a0178805be1526a15a755d398326f99059ff775485246999027b3197955111111125421ca6dc452d289314280a0f8842a650020d6bdbf78fceb31a79f71ac9cbdcf853519c1b12d379edc46111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000098dd6ed1";

        vm.startPrank(admin);
        listaAutoBuyBack.grantRole(listaAutoBuyBack.BOT(), manager);
        vm.stopPrank();

        vm.startPrank(manager);
        vm.expectRevert("amountIn is zero");
        listaAutoBuyBack.buyback(address(lisUSD), 0, oneInchRouter, data);
        vm.stopPrank();
    }

    function test_autoBuyBack_buyback_invalid_amount() public {
        bytes memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000fceb31a79f71ac9cbdcf853519c1b12d379edc46000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000078ab74c7ec3592b5298cb912f31bd8fb80a57dc0000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000003f06640a9221e160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c30000000000000000000000000000000000000000000000000001a500017700a007e5c0d20000000000000000000000000000000000000000000000000001530000f051200520451b19ad0bb00ed35ef391086a692cfc74b20782b6d8c4551b9760e74c0545a9bcd90bdc41e500449908fc8b0000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000066d57bb802a000000000000000000000000000000000000000000000000003f06640a9221e16ee63c1e5812c533e2c2b4fd1172b5a0a0178805be1526a15a755d398326f99059ff775485246999027b3197955111111125421ca6dc452d289314280a0f8842a650020d6bdbf78fceb31a79f71ac9cbdcf853519c1b12d379edc46111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000098dd6ed1";

        vm.startPrank(bot);
        vm.expectRevert("amountIn is zero");
        listaAutoBuyBack.buyback(address(lisUSD), 0, oneInchRouter, data);
        vm.stopPrank();
    }

    function test_autoBuyBack_buyback_invalid_router() public {
        bytes memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000fceb31a79f71ac9cbdcf853519c1b12d379edc46000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000078ab74c7ec3592b5298cb912f31bd8fb80a57dc0000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000003f06640a9221e160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c30000000000000000000000000000000000000000000000000001a500017700a007e5c0d20000000000000000000000000000000000000000000000000001530000f051200520451b19ad0bb00ed35ef391086a692cfc74b20782b6d8c4551b9760e74c0545a9bcd90bdc41e500449908fc8b0000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000066d57bb802a000000000000000000000000000000000000000000000000003f06640a9221e16ee63c1e5812c533e2c2b4fd1172b5a0a0178805be1526a15a755d398326f99059ff775485246999027b3197955111111125421ca6dc452d289314280a0f8842a650020d6bdbf78fceb31a79f71ac9cbdcf853519c1b12d379edc46111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000098dd6ed1";

        vm.startPrank(bot);
        vm.expectRevert("router not whitelisted");
        listaAutoBuyBack.buyback(address(lisUSD), 1e18, proxyAdminOwner, data);
        vm.stopPrank();
    }

    function test_autoBuyBack_buyback_invalid_receiver() public {
        bytes memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000fceb31a79f71ac9cbdcf853519c1b12d379edc46000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000078ab74c7ec3592b5298cb912f31bd8fb80a57dc0000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000003f06640a9221e160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c30000000000000000000000000000000000000000000000000001a500017700a007e5c0d20000000000000000000000000000000000000000000000000001530000f051200520451b19ad0bb00ed35ef391086a692cfc74b20782b6d8c4551b9760e74c0545a9bcd90bdc41e500449908fc8b0000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000066d57bb802a000000000000000000000000000000000000000000000000003f06640a9221e16ee63c1e5812c533e2c2b4fd1172b5a0a0178805be1526a15a755d398326f99059ff775485246999027b3197955111111125421ca6dc452d289314280a0f8842a650020d6bdbf78fceb31a79f71ac9cbdcf853519c1b12d379edc46111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000098dd6ed1";
        vm.startPrank(admin);
        listaAutoBuyBack.changeDefaultReceiver(address(0x1A11AA));
        vm.stopPrank();
        assertEq(address(0x1A11AA), listaAutoBuyBack.defaultReceiver());

        vm.startPrank(bot);
        vm.expectRevert("invalid dst receiver of _data");
        listaAutoBuyBack.buyback(address(lisUSD), 1e18, oneInchRouter, data);
        vm.stopPrank();
    }

    function test_autoBuyBack_buyback_invalid_balance() public {
        deal(address(lisUSD), address(listaAutoBuyBack), 1e17);

        bytes memory data = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000fceb31a79f71ac9cbdcf853519c1b12d379edc46000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000078ab74c7ec3592b5298cb912f31bd8fb80a57dc0000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000003f06640a9221e160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c30000000000000000000000000000000000000000000000000001a500017700a007e5c0d20000000000000000000000000000000000000000000000000001530000f051200520451b19ad0bb00ed35ef391086a692cfc74b20782b6d8c4551b9760e74c0545a9bcd90bdc41e500449908fc8b0000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000066d57bb802a000000000000000000000000000000000000000000000000003f06640a9221e16ee63c1e5812c533e2c2b4fd1172b5a0a0178805be1526a15a755d398326f99059ff775485246999027b3197955111111125421ca6dc452d289314280a0f8842a650020d6bdbf78fceb31a79f71ac9cbdcf853519c1b12d379edc46111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000098dd6ed1";

        vm.startPrank(bot);
        vm.expectRevert("insufficient balance");
        listaAutoBuyBack.buyback(address(lisUSD), 1e18, oneInchRouter, data);
        vm.stopPrank();
    }

    function test_autoBuyBack_buyback_invalid_function() public {
        bytes memory data = hex"01112379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e5000000000000000000000000fceb31a79f71ac9cbdcf853519c1b12d379edc46000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000078ab74c7ec3592b5298cb912f31bd8fb80a57dc0000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000003f06640a9221e160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c30000000000000000000000000000000000000000000000000001a500017700a007e5c0d20000000000000000000000000000000000000000000000000001530000f051200520451b19ad0bb00ed35ef391086a692cfc74b20782b6d8c4551b9760e74c0545a9bcd90bdc41e500449908fc8b0000000000000000000000000782b6d8c4551b9760e74c0545a9bcd90bdc41e500000000000000000000000055d398326f99059ff775485246999027b319795500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000066d57bb802a000000000000000000000000000000000000000000000000003f06640a9221e16ee63c1e5812c533e2c2b4fd1172b5a0a0178805be1526a15a755d398326f99059ff775485246999027b3197955111111125421ca6dc452d289314280a0f8842a650020d6bdbf78fceb31a79f71ac9cbdcf853519c1b12d379edc46111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000098dd6ed1";

        vm.startPrank(bot);
        vm.expectRevert("invalid function selector of _data");
        listaAutoBuyBack.buyback(address(lisUSD), 1e18, oneInchRouter, data);
        vm.stopPrank();
    }

    function test_autoBuyBack_add1InchRouterWhitelist() public {
        assertEq(false, listaAutoBuyBack.oneInchRouterWhitelist(address(0x1A11FF)));

        vm.startPrank(admin);
        listaAutoBuyBack.add1InchRouterWhitelist(address(0x1A11FF));
        vm.stopPrank();
        assertEq(true, listaAutoBuyBack.oneInchRouterWhitelist(address(0x1A11FF)));
    }

    function test_autoBuyBack_add1InchRouterWhitelist_already() public {
        test_autoBuyBack_add1InchRouterWhitelist();

        vm.startPrank(admin);
        vm.expectRevert("router already whitelisted");
        listaAutoBuyBack.add1InchRouterWhitelist(address(0x1A11FF));
        vm.stopPrank();
    }

    function test_autoBuyBack_remove1InchRouterWhitelist() public {
        test_autoBuyBack_add1InchRouterWhitelist();

        vm.startPrank(admin);
        listaAutoBuyBack.remove1InchRouterWhitelist(address(0x1A11FF));
        vm.stopPrank();
        assertEq(false, listaAutoBuyBack.oneInchRouterWhitelist(address(0x1A11FF)));
    }
}
