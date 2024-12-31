// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../contracts/dao/BorrowListaDistributor.sol";

contract BorrowListaDistributorTest is Test {

    address admin = address(0x1A11AA);
    address manager = address(0x2A11AA);
    address user = address(0x3A11AA);
    address proxyAdminOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;

    address listaVault = address(0x307d13267f360f78005f476Fa913F8848F30292A);

    uint256 mainnet;

    IERC20 slisBNB;

    BorrowListaDistributor slisBnbBorrowlDistributor;

    function setUp() public {
        mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");
        slisBNB = IERC20(0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B);

        BorrowListaDistributor slisBnbBorrowlDistributorImpl = new BorrowListaDistributor();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(slisBnbBorrowlDistributorImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(string,string,address,address,address,address)",
                "slisBNBBorrowDistributor", "slisBNB", admin, manager, listaVault, address(slisBNB)
            )
        );

        slisBnbBorrowlDistributor = BorrowListaDistributor(address(proxy));

        assertEq("slisBNBBorrowDistributor", slisBnbBorrowlDistributor.name());
    }

    function test_takeSnapshot() public {
        assertEq(0, slisBnbBorrowlDistributor.balanceOf(user));

        vm.startPrank(manager);
        slisBnbBorrowlDistributor.takeSnapshot(address(slisBNB), user, 123e18);
        vm.stopPrank();

        assertEq(123e18, slisBnbBorrowlDistributor.balanceOf(user));
    }
}
