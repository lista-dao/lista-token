// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../contracts/dao/interfaces/OracleInterface.sol";
import "../contracts/interfaces/IVeLista.sol";

import {VeLista} from "../contracts/VeLista.sol";
import {ListaToken} from "../contracts/ListaToken.sol";
import {VeListaDistributor} from "../contracts/VeListaDistributor.sol";
import {VeListaAutoCompounder} from "../contracts/VeListaAutoCompounder.sol";
import {MockResilientOracle} from "../contracts/mock/MockResilientOracle.sol";

contract VeListaAutoCompounderTest is Test {
    ListaToken lista;
    VeLista veLista;
    VeListaDistributor veListaDistributor;

    OracleInterface public oracle;

    VeListaAutoCompounder compounder;

    address feeReceiver = makeAddr("feeReceiver");
    address admin = makeAddr("admin");
    address user1 = makeAddr("user1");

    function setUp() public {
        lista = new ListaToken(admin);
        veLista = new VeLista();
        veListaDistributor = new VeListaDistributor();
        oracle = new MockResilientOracle();
        compounder = new VeListaAutoCompounder();

        vm.mockCall(
            address(veLista),
            abi.encodeWithSignature("token()"),
            abi.encode(IERC20(lista))
        );

        vm.mockCall(
            address(veListaDistributor),
            abi.encodeWithSignature("veLista()"),
            abi.encode(IVeLista(veLista))
        );

        compounder.initialize(
            address(lista),
            address(veLista),
            address(veListaDistributor),
            address(oracle),
            feeReceiver,
            admin
        );
        assertEq(
            compounder.hasRole(compounder.DEFAULT_ADMIN_ROLE(), admin),
            true
        );

        assertEq(address(compounder.lista()), address(lista));
        assertEq(address(compounder.veLista()), address(veLista));
        assertEq(
            address(compounder.veListaDistributor()),
            address(veListaDistributor)
        );
        assertEq(address(compounder.oracle()), address(oracle));
        assertEq(compounder.feeReceiver(), feeReceiver);

        assertEq(compounder.feeRate(), 300);
        assertEq(compounder.maxFeeRate(), 1000);
        assertEq(compounder.maxFee(), 10 * 10 ** 18);
        assertEq(compounder.autoCompoundThreshold(), 5 * 10 ** 18);

        assertEq(compounder.totalFee(), 0);
    }

    function test_toggleAutoCompound() public {
        assertEq(compounder.autoCompoundEnabled(user1), false);

        vm.startPrank(user1);
        compounder.toggleAutoCompound();
        vm.stopPrank();

        assertEq(compounder.autoCompoundEnabled(user1), true);
    }

    function test_isEligibleForAutoCompound() public {
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(
                MockResilientOracle.peek.selector,
                address(lista)
            ),
            abi.encode(uint256(50000000)) // returns $0.5
        );

        assertEq(compounder.isEligibleForAutoCompound(10e18), true); // 10 Lista
        assertEq(compounder.isEligibleForAutoCompound(9e18), false); // 9 Lista
    }

    function test_getAmountToCompound() public {
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(
                MockResilientOracle.peek.selector,
                address(lista)
            ),
            abi.encode(uint256(40157283)) // returns $0.40157283
        );

        vm.startPrank(user1);
        uint256 _amtToCompound = compounder.getAmountToCompound(100e18); // 100 Lista
        vm.stopPrank();

        assertEq(_amtToCompound, 97e18);
    }

    function test_claimAndIncreaseAmount() public {
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(
                MockResilientOracle.peek.selector,
                address(lista)
            ),
            abi.encode(uint256(50000000)) // returns $0.5
        );

        IVeLista.AccountData memory mockData = IVeLista.AccountData({
            locked: 100e18,
            lastLockWeek: 1,
            lockWeeks: 100,
            autoLock: true,
            lockTimestamp: 100
        });

        vm.mockCall(
            address(veLista),
            abi.encodeWithSelector(veLista.getLockedData.selector, user1),
            abi.encode(
                mockData.locked,
                mockData.lastLockWeek,
                mockData.lockWeeks,
                mockData.autoLock,
                mockData.lockTimestamp
            )
        );

        vm.mockCall(
            address(veListaDistributor),
            abi.encodeWithSelector(
                VeListaDistributor.getTokenClaimable.selector,
                user1,
                address(lista),
                uint16(1)
            ),
            abi.encode(uint256(100e18), uint16(1))
        );

        vm.mockCall(
            address(veListaDistributor),
            abi.encodeWithSelector(
                VeListaDistributor.claimForCompound.selector,
                user1,
                address(lista),
                uint16(1)
            ),
            abi.encode(uint256(100e18))
        );

        vm.mockCall(
            address(veLista),
            abi.encodeWithSelector(
                VeLista.increaseAmountFor.selector,
                user1,
                uint256(97e18)
            ),
            abi.encode()
        );

        vm.expectRevert("Auto compound not enabled");
        vm.startPrank(user1);
        compounder.claimAndIncreaseAmount(1);
        vm.stopPrank();

        vm.startPrank(user1);
        compounder.toggleAutoCompound();
        compounder.claimAndIncreaseAmount(1);
        vm.stopPrank();

        assertEq(compounder.totalFee(), 3e18);
    }

    function test_file_uint() public {
        vm.expectRevert(
            "AccessControl: account 0x7fa9385be102ac3eac297483dd6233d62b3e1496 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        compounder.file("feeRate", 100);

        vm.startPrank(admin);
        vm.expectRevert("Invalid feeRate");
        compounder.file("feeRate", 1001);
        compounder.file("feeRate", 100);
        assertEq(compounder.feeRate(), 100);

        vm.expectRevert("Invalid maxFeeRate");
        compounder.file("maxFeeRate", 99);
        compounder.file("maxFeeRate", 2000);
        assertEq(compounder.maxFeeRate(), 2000);

        vm.expectRevert("Invalid maxFee");
        compounder.file("maxFee", 100);
        compounder.file("maxFee", 20e18);
        assertEq(compounder.maxFee(), 20e18);

        vm.expectRevert("Invalid autoCompoundThreshold");
        compounder.file("autoCompoundThreshold", 10000e18);
        compounder.file("autoCompoundThreshold", 6e18);
        assertEq(compounder.autoCompoundThreshold(), 6e18);

        vm.stopPrank();
    }

    function test_file_address() public {
        vm.expectRevert(
            "AccessControl: account 0x7fa9385be102ac3eac297483dd6233d62b3e1496 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        compounder.file("feeReceiver", user1);

        vm.startPrank(admin);

        vm.expectRevert("Invalid Lista token");
        compounder.file("lista", address(0x11));
        vm.mockCall(
            address(veLista),
            abi.encodeWithSignature("token()"),
            abi.encode(IERC20(address(0x11)))
        );
        compounder.file("lista", address(0x11));
        assertEq(address(compounder.lista()), address(0x11));

        vm.expectRevert("Invalid veLista");
        compounder.file("veLista", address(0x12));
        vm.mockCall(
            address(veListaDistributor),
            abi.encodeWithSignature("veLista()"),
            abi.encode(IVeLista(address(0x12)))
        );
        compounder.file("veLista", address(0x12));
        assertEq(address(compounder.veLista()), address(0x12));

        compounder.file("veListaDistributor", address(0x13));
        assertEq(address(compounder.veListaDistributor()), address(0x13));

        compounder.file("oracle", address(0x14));
        assertEq(address(compounder.oracle()), address(0x14));

        compounder.file("feeReceiver", user1);
        assertEq(compounder.feeReceiver(), user1);

        vm.stopPrank();
    }
}
