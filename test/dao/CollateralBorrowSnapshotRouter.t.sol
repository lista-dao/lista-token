// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../contracts/dao/CollateralBorrowSnapshotRouter.sol";
import "../../contracts/dao/BorrowLisUSDListaDistributor.sol";
import "../../contracts/dao/CollateralListaDistributor.sol";
import "../../contracts/dao/BorrowListaDistributor.sol";


contract CollateralBorrowSnapshotRouterTest is Test {
    address admin = address(0x1A11AA);
    address manager = address(0x2A11AA);
    address user = address(0x3A11AA);
    address proxyAdminOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;

    address listaVault = 0x307d13267f360f78005f476Fa913F8848F30292A;

    CollateralBorrowSnapshotRouter collateralBorrowSnapshotRouter;

    BorrowLisUSDListaDistributor borrowLisUSDListaDistributor;

    uint256 mainnet;

    IERC20 slisBNB;
    IERC20 ETH;
    CollateralListaDistributor slisBNBCollateralDistributor;
    CollateralListaDistributor ethCollateralDistributor;
    BorrowListaDistributor slisBnbBorrowListaDistributor;

    function setUp() public {
        mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");
        slisBNB = IERC20(0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B);
        ETH = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);

        BorrowLisUSDListaDistributor borrowImpl = new BorrowLisUSDListaDistributor();
        TransparentUpgradeableProxy borrowProxy = new TransparentUpgradeableProxy(
            address(borrowImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(string,string,address,address,address,address)",
                "slisBNBCollateralDistributor", "slisBNB", admin, manager, listaVault, address(slisBNB)
            )
        );


        borrowLisUSDListaDistributor = BorrowLisUSDListaDistributor(address(borrowProxy));

        CollateralListaDistributor slisBNBCollateralDistributorImpl = new CollateralListaDistributor();
        CollateralListaDistributor ethCollateralDistributorImpl = new CollateralListaDistributor();
        TransparentUpgradeableProxy slisBNBCollateralDistributorProxy = new TransparentUpgradeableProxy(
            address(slisBNBCollateralDistributorImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(string,string,address,address,address,address)",
                "slisBNBCollateralDistributor", "slisBNB", admin, manager, listaVault, address(slisBNB)
            )
        );
        TransparentUpgradeableProxy ethCollateralDistributorProxy = new TransparentUpgradeableProxy(
            address(ethCollateralDistributorImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(string,string,address,address,address,address)",
                "ETHCollateralDistributor", "ETH", admin, manager, listaVault, address(ETH)
            )
        );

        slisBNBCollateralDistributor = CollateralListaDistributor(address(slisBNBCollateralDistributorProxy));
        ethCollateralDistributor = CollateralListaDistributor(address(ethCollateralDistributorProxy));

        address[] memory tokens = new address[](2);
        tokens[0] = address(slisBNB);
        tokens[1] = address(ETH);

        address[] memory distributors = new address[](2);
        distributors[0] = address(slisBNBCollateralDistributor);
        distributors[1] = address(ethCollateralDistributor);

        CollateralBorrowSnapshotRouter routerImpl = new CollateralBorrowSnapshotRouter();
        TransparentUpgradeableProxy routerProxy = new TransparentUpgradeableProxy(
            address(routerImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(address,address,address,address[],address[])",
                admin, manager, address(borrowLisUSDListaDistributor), tokens, distributors
            )
        );

        collateralBorrowSnapshotRouter = CollateralBorrowSnapshotRouter(address(routerProxy));

        vm.startPrank(admin);
        borrowLisUSDListaDistributor.grantRole(borrowLisUSDListaDistributor.MANAGER(), address(collateralBorrowSnapshotRouter));
        ethCollateralDistributor.grantRole(ethCollateralDistributor.MANAGER(), address(collateralBorrowSnapshotRouter));
        slisBNBCollateralDistributor.grantRole(slisBNBCollateralDistributor.MANAGER(), address(collateralBorrowSnapshotRouter));
        vm.stopPrank();

        // Deploy and set slisBNB borrow distributor
        BorrowListaDistributor slisBnbBorrowListaDistributorImpl = new BorrowListaDistributor();
        TransparentUpgradeableProxy slisBnbBorrowListaDistributorProxy = new TransparentUpgradeableProxy(
            address(slisBnbBorrowListaDistributorImpl),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(string,string,address,address,address,address)",
                "slisBnbBorrowListaDistributor", "slisBNB", admin, manager, listaVault, address(slisBNB)
            )
        );
        slisBnbBorrowListaDistributor = BorrowListaDistributor(address(slisBnbBorrowListaDistributorProxy));

        address[] memory _tokens = new address[](1);
        _tokens[0] = address(slisBNB);
        address[] memory _distributors = new address[](1);
        _distributors[0] = address(slisBnbBorrowListaDistributor);

        vm.startPrank(admin);
        collateralBorrowSnapshotRouter.batchSetBorrowDistributors(_tokens, _distributors);
        slisBnbBorrowListaDistributor.grantRole(slisBnbBorrowListaDistributor.MANAGER(), address(collateralBorrowSnapshotRouter));
    }

    function test_setUp() public {
        assertEq(address(borrowLisUSDListaDistributor), address(collateralBorrowSnapshotRouter.borrowLisUSDListaDistributor()));

        assertEq(address(ethCollateralDistributor), address(collateralBorrowSnapshotRouter.collateralDistributors(address(ETH))));
        assertEq(address(slisBNBCollateralDistributor), address(collateralBorrowSnapshotRouter.collateralDistributors(address(slisBNB))));
        assertEq(address(slisBnbBorrowListaDistributor), address(collateralBorrowSnapshotRouter.borrowDistributors(address(slisBNB))));
    }

    function test_takeSnapshot_acl() public {
        vm.startPrank(user);
        vm.expectRevert("AccessControl: account 0x00000000000000000000000000000000003a11aa is missing role 0xaf290d8680820aad922855f39b306097b20e28774d6c1ad35a20325630c3a02c");
        collateralBorrowSnapshotRouter.takeSnapshot(address(slisBNB), user, 123e18, 456e18, true, true);
        vm.stopPrank();
    }

    function test_takeSnapshot_collateral_slisBNB() public {
        assertEq(0, slisBNBCollateralDistributor.balanceOf(user));

        vm.expectEmit(address(slisBNBCollateralDistributor));
        emit CommonListaDistributor.LPTokenDeposited(address(slisBNB), user, 123e18);

        vm.startPrank(manager);
        collateralBorrowSnapshotRouter.takeSnapshot(address(slisBNB), user, 123e18, 0, true, false);
        vm.stopPrank();

        assertEq(123e18, slisBNBCollateralDistributor.balanceOf(user));
    }

    function test_takeSnapshot_collateral_ETH() public {
        assertEq(0, slisBNBCollateralDistributor.balanceOf(user));

        vm.expectEmit(address(ethCollateralDistributor));
        emit CommonListaDistributor.LPTokenDeposited(address(ETH), user, 123e18);

        vm.startPrank(manager);
        collateralBorrowSnapshotRouter.takeSnapshot(address(ETH), user, 123e18, 0, true, false);
        vm.stopPrank();

        assertEq(123e18, ethCollateralDistributor.balanceOf(user));
    }

    function test_takeSnapshot_borrow() public {
        assertEq(0, slisBnbBorrowListaDistributor.balanceOf(user));

        vm.expectEmit(address(slisBnbBorrowListaDistributor));
        emit CommonListaDistributor.LPTokenDeposited(address(slisBNB), user, 123e18);

        vm.startPrank(manager);
        collateralBorrowSnapshotRouter.takeSnapshot(address(slisBNB), user, 0, 123e18, false, true);
        vm.stopPrank();

        assertEq(123e18, slisBnbBorrowListaDistributor.balanceOf(user));
    }

    function test_takeSnapshot_collateral_borrow() public {
        assertEq(0, slisBNBCollateralDistributor.balanceOf(user));
        assertEq(0, slisBnbBorrowListaDistributor.balanceOf(user));

        vm.expectEmit(address(slisBNBCollateralDistributor));
        emit CommonListaDistributor.LPTokenDeposited(address(slisBNB), user, 123e18);

        vm.expectEmit(address(slisBnbBorrowListaDistributor));
        emit CommonListaDistributor.LPTokenDeposited(address(slisBNB), user, 456e18);

        vm.startPrank(manager);
        collateralBorrowSnapshotRouter.takeSnapshot(address(slisBNB), user, 123e18, 456e18, true, true);
        vm.stopPrank();

        assertEq(123e18, slisBNBCollateralDistributor.balanceOf(user));
        assertEq(456e18, slisBnbBorrowListaDistributor.balanceOf(user));
    }
}
