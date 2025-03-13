// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/dao/erc20LpProvider/ThenaERC20LpProvidableListaDistributor.sol";
import "../contracts/dao/erc20LpProvider/ERC20LpTokenProvider.sol";
import "../contracts/mock/MockERC20.sol";
import "../contracts/dao/interfaces/IDistributor.sol";
import "./interfaces/IThenaUniProxy.sol";
import "../contracts/dao/StakingVault.sol";
import "../contracts/dao/ThenaStaking.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IThenaStaking {
    function activateEmergencyMode() external;
}

interface IClisBNB is IERC20 {
    function addMinter(address minter) external;
    function _minters(address minter) external returns (bool);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 limitSqrtPrice;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract ThenaStakingDistributorTest is Test {

    // LP token of distributor, token of provider
    IERC20 lpToken = IERC20(0x3685502Ea3EA4175FB5cBB5344F74D2138A96708);
    // LP token of Provider
    IClisBNB clisBNB = IClisBNB(0x4b30fcAA7945fE9fDEFD2895aae539ba102Ed6F6);
    address clisBNBOwner = 0x702115D6d3Bbb37F407aae4dEcf9d09980e28ebc;

    address owner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6; // TimeLock
    address proxyAdminOwner = 0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253;
    ProxyAdmin proxyAdmin = ProxyAdmin(0xBd8789025E91AF10487455B692419F82523D29Be);
    address user1 = address(0x1111);
    address user2 = address(0x2222);
    address thenaStakingPoolOwner = 0xb065E4F5D71a55a4e4FC2BD871B36E33053cabEB;

    IERC20 token0 = IERC20(0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B); // slisBNB
    IERC20 token1 = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // wBNB
    IERC20 rewardToken = IERC20(0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11);
    address poolAddress = address(0x7Db93DC92ecA0c59c530A0c4bCD26a7bf363d5D1);

    IThenaUniProxy thenaUniProxy = IThenaUniProxy(0xF75c017E3b023a593505e281b565ED35Cc120efa);

    ThenaERC20LpProvidableListaDistributor slisBNBBNBThenaCorrelatedDistributor = ThenaERC20LpProvidableListaDistributor(0xFf5ed1E64aCA62c822B178FFa5C36B40c112Eb00);
    StakingVault stakingVault = StakingVault(0xF40D0d497966fe198765877484FFf08c2D2004ad);
    ThenaStaking thenaStaking = ThenaStaking(0xFA5B482882F9e025facCcE558c2F72c6c50AC719);

    ERC20LpTokenProvider tokenProvider;

    ISwapRouter thenaSwapRouter = ISwapRouter(0x327Dd3208f0bCF590A66110aCB6e5e6941A4EfA0);

    uint256 MAX_UINT256 = type(uint256).max;

    function setUp() public {
        vm.createSelectFork("bsc-main");

        deal(user1, 100 ether);
        deal(address(token0), user1, 10001 ether);
        deal(address(token1), user1, 10002 ether);

        deal(user2, 103 ether);
        deal(address(token0), user2, 10004 ether);
        deal(address(token1), user2, 10005 ether);

        // deploy token provider
        vm.startPrank(owner);
        ERC20LpTokenProvider tokenProviderImpl = new ERC20LpTokenProvider();
        TransparentUpgradeableProxy tokenProviderProxy = new TransparentUpgradeableProxy(
            address(tokenProviderImpl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(address,address,address,address,address,address,address,uint128,uint128)",
                owner,
                owner,
                owner,
                address(clisBNB),
                address(lpToken),
                address(slisBNBBNBThenaCorrelatedDistributor),
                address(owner),
                0.93 ether,
                0.93 ether
            )
        );
        tokenProvider = ERC20LpTokenProvider(address(tokenProviderProxy));
        vm.stopPrank();

        // add token provider as clisBNB's minter
        if (!clisBNB._minters(address(tokenProvider))) {
            vm.prank(clisBNBOwner);
            clisBNB.addMinter(address(tokenProvider));
        }

        // upgrade distributor
        vm.startPrank(proxyAdminOwner);
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(slisBNBBNBThenaCorrelatedDistributor));
        ThenaERC20LpProvidableListaDistributor impl = new ThenaERC20LpProvidableListaDistributor();
        proxyAdmin.upgradeAndCall(proxy, address(impl), "");
        vm.stopPrank();

        vm.startPrank(owner);
        if (!slisBNBBNBThenaCorrelatedDistributor.compatibilityMode()) {
            slisBNBBNBThenaCorrelatedDistributor.setCompatibilityMode(true);
        }
        if (!slisBNBBNBThenaCorrelatedDistributor.hasRole(keccak256("TOKEN_PROVIDER"), address(tokenProvider))) {
            slisBNBBNBThenaCorrelatedDistributor.grantRole(keccak256("TOKEN_PROVIDER"), address(tokenProvider));
        }
        vm.stopPrank();

    }


    function test_deposit_and_withdraw() public {
        // provide liquidity
        uint256 user1Lp = addLiquidity(user1, 100 ether);

        vm.startPrank(user1);
        // user normal deposit
        lpToken.approve(address(slisBNBBNBThenaCorrelatedDistributor), MAX_UINT256);
        slisBNBBNBThenaCorrelatedDistributor.deposit(user1Lp);
        skip(1 days);
        // harvest rewards
        thenaStaking.harvest(address(lpToken));
        skip(1 days);
        address[] memory distributors = new address[](1);
        distributors[0] = address(slisBNBBNBThenaCorrelatedDistributor);
        stakingVault.batchClaimRewards(distributors);
        // user withdraw
        slisBNBBNBThenaCorrelatedDistributor.withdraw(user1Lp);
        vm.stopPrank();

        // ----- disable compatibility
        vm.prank(owner);
        slisBNBBNBThenaCorrelatedDistributor.setCompatibilityMode(false);

        vm.startPrank(user1);

        // user could not deposit and withdraw when compatibility mode disabled
        vm.expectRevert("compatibility mode is disabled");
        slisBNBBNBThenaCorrelatedDistributor.deposit(user1Lp);
        vm.expectRevert("compatibility mode is disabled");
        slisBNBBNBThenaCorrelatedDistributor.withdraw(user1Lp);

        // only provider can call depositFor()
        vm.expectRevert();
        slisBNBBNBThenaCorrelatedDistributor.depositFor(user1Lp, user1);
        vm.expectRevert();
        slisBNBBNBThenaCorrelatedDistributor.withdrawFor(user1Lp, user1);

        vm.stopPrank();
    }

    function test_provider_deposit_and_withdraw() public {
        // make sure compatibility mode is disabled
        if (slisBNBBNBThenaCorrelatedDistributor.compatibilityMode()) {
            vm.prank(owner);
            slisBNBBNBThenaCorrelatedDistributor.setCompatibilityMode(false);
        }
        // provide liquidity and get LP
        uint256 user1Lp = addLiquidity(user1, 100 ether);
        // calculate expected clisBNB to get
        (uint256 holderLpAmt, uint256 reservedLpAmt) = tokenToClisBNB(user1Lp/2);

        /* ----------- deposit ----------- */
        vm.startPrank(user1);

        uint256 preU1Bal; // post clisBNB balance of user1
        uint256 preU2Bal; // post clisBNB balance of user2
        uint256 u1Changed; // clisBNB gained by user1
        uint256 u2Changed; // clisBNB gained by user2

        // --------- user1 deposit
        preU1Bal = clisBNB.balanceOf(user1);
        lpToken.approve(address(tokenProvider), MAX_UINT256);
        tokenProvider.deposit(user1Lp/2);
        u1Changed = clisBNB.balanceOf(user1) - preU1Bal;
        assertEq(u1Changed, holderLpAmt, "clisBNB gained should be equal to holderLpAmt");
        assertEq(reservedLpAmt, tokenProvider.userReservedLp(user1), "reservedLpAmt should be equal to userReservedLp");

        console.log("User 1 gained clisBNB");

        // --------- user1 deposit and delegate to user2
        preU2Bal = clisBNB.balanceOf(user2);
        tokenProvider.deposit(user1Lp/2, user2);
        u2Changed = clisBNB.balanceOf(user2) - preU2Bal;
        assertEq(u2Changed, holderLpAmt, "clisBNB gained should be equal to holderLpAmt");
        assertEq(reservedLpAmt*2, tokenProvider.userReservedLp(user1), "reservedLpAmt should be equal to userReservedLp");

        console.log("User 1 delegated clisBNB to user 2");

        // -------- user 1 withdraw 1/4
        (uint256 quarterHolderLpAmt,) = tokenToClisBNB(user1Lp/4);
        // burn delegatee first
        preU1Bal = clisBNB.balanceOf(user1);
        preU2Bal = clisBNB.balanceOf(user2);
        tokenProvider.withdraw(user1Lp/4);
        u1Changed = preU1Bal - clisBNB.balanceOf(user1);
        u2Changed = preU2Bal - clisBNB.balanceOf(user2);
        assertEq(u1Changed, 0, "User 1 should not burn any clisBNB");
        assertEq(u2Changed, quarterHolderLpAmt, "User 2 should burn `quarterHolderLpAmt` of clisBNB");

        // -------- user 1 further withdraw 1/2
        // that means user 2 have no clisBNB left
        // and user 1 should 1/4 of clisBNB as 3/4 of LP has been withdrawn
        preU1Bal = clisBNB.balanceOf(user1);
        preU2Bal = clisBNB.balanceOf(user2);
        tokenProvider.withdraw(user1Lp/2);
        u1Changed = preU1Bal - clisBNB.balanceOf(user1);
        u2Changed = preU2Bal - clisBNB.balanceOf(user2);
        assertApproxEqAbs(
            u1Changed, quarterHolderLpAmt, 10000,
            "both user 1 and 2 should burn `halfHolderLpAmt` of clisBNB"
        );
        assertApproxEqAbs(
            u2Changed, quarterHolderLpAmt, 10000,
            "both user 1 and 2 should burn `halfHolderLpAmt` of clisBNB"
        );
        vm.stopPrank();
    }

    function test_delegateAll() public {
        // make sure compatibility mode is disabled
        if (slisBNBBNBThenaCorrelatedDistributor.compatibilityMode()) {
            vm.prank(owner);
            slisBNBBNBThenaCorrelatedDistributor.setCompatibilityMode(false);
        }
        // provide liquidity and get LP
        uint256 user1Lp = addLiquidity(user1, 100 ether);
        // calculate expected clisBNB to get
        (uint256 holderLpAmt, uint256 reservedLpAmt) = tokenToClisBNB(user1Lp);

        vm.startPrank(user1);

        // delegate to user2 first
        uint256 preU2Bal = clisBNB.balanceOf(user2);
        lpToken.approve(address(tokenProvider), MAX_UINT256);
        tokenProvider.deposit(user1Lp, user2);
        uint256 u2Changed = clisBNB.balanceOf(user2) - preU2Bal;
        assertEq(u2Changed, holderLpAmt, "all clisBNB should be delegated to user2");

        address user3 = address(0x333333);
        // delegate to user3
        uint256 preU3Bal = clisBNB.balanceOf(user3);
        tokenProvider.delegateAllTo(user3);
        uint256 u3Changed = clisBNB.balanceOf(user3) - preU3Bal;
        assertEq(u3Changed, holderLpAmt, "all clisBNB should be delegated to user3");
        assertEq(clisBNB.balanceOf(user1), 0, "user1 should have no clisBNB left");
        assertEq(clisBNB.balanceOf(user2), 0, "user2 should have no clisBNB left");

        vm.stopPrank();
    }

    function test_syncLp() public {
        // provide liquidity and get LP
        addLiquidity(user1, 100 ether);

        // check is synced
        bool isSynced = tokenProvider.isUserLpSynced(user1);
        assertEq(isSynced, true);

        vm.expectRevert("already synced");
        tokenProvider.syncUserLp(user1);
    }

    function test_emergencyWithdraw() public {
        // activate ThenaStakingPool's emergency mode
        vm.prank(thenaStakingPoolOwner);
        IThenaStaking(address(poolAddress)).activateEmergencyMode();

        (,,,,bool _active,) = thenaStaking.pools(address(lpToken));
        assertTrue(_active, "pool should be active");
        vm.startPrank(owner);
        // address lpToken_ = address(slisBNBBNBThenaCorrelatedDistributor);
        thenaStaking.emergencyWithdraw(address(lpToken));
        vm.stopPrank();

        assertTrue(thenaStaking.emergencyModeForLpToken(address(lpToken)), "emergency mode should be true");
    }

    // ------------------------ Utility functions ------------------------ //
    function tokenToClisBNB(uint256 amount) public returns (uint256, uint256) {
        uint256 netLp = slisBNBBNBThenaCorrelatedDistributor.getLpToQuoteToken(amount);
        uint256 deltaLpAmount = netLp * tokenProvider.exchangeRate() / tokenProvider.RATE_DENOMINATOR();
        uint256 deltaHolderLpAmount = deltaLpAmount * tokenProvider.userLpRate() / tokenProvider.RATE_DENOMINATOR();
        uint256 deltaReserveLpAmount = deltaLpAmount - deltaHolderLpAmount;
        return (deltaHolderLpAmount, deltaReserveLpAmount);
    }

    // User get Thena LP token from ThenaUniProxy
    function addLiquidity(address user, uint256 amount0) public returns (uint256) {
        vm.startPrank(user);
        token0.approve(address(lpToken), MAX_UINT256);
        token1.approve(address(lpToken), MAX_UINT256);

        (uint256 amount1Start, uint256 amount1End) = thenaUniProxy.getDepositAmount(
            address(lpToken),
            address(token0),
            amount0
        );

        uint256 amount1 = (amount1Start + amount1End) / 2;
        uint256[4] memory minIn;
        thenaUniProxy.deposit(
            amount0,
            amount1,
            user,
            address(lpToken),
            minIn
        );
        vm.stopPrank();

        return lpToken.balanceOf(user);
    }
}
