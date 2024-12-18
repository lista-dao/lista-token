// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../contracts/VeLista.sol";
import "../contracts/ListaToken.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/dao/ERC20LpListaDistributor.sol";
import "../contracts/dao/ListaVault.sol";
import "../contracts/mock/MockERC20.sol";
import "../contracts/dao/interfaces/IDistributor.sol";
import "./interfaces/IThenaUniProxy.sol";
import "../contracts/dao/StakingVault.sol";
import "../contracts/dao/ThenaStaking.sol";

contract ThenaStakingDistributorTest is Test {
    VeLista public veLista = VeLista(0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3);
    ListaToken public lista = ListaToken(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46);
    ListaVault listaVault = ListaVault(0x307d13267f360f78005f476Fa913F8848F30292A);
    IERC20 lpToken = IERC20(0x3685502Ea3EA4175FB5cBB5344F74D2138A96708);

    address owner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;

    address proxyAdminOwner = 0x08aE09467ff962aF105c23775B9Bc8EAa175D27F;
    ProxyAdmin proxyAdmin = ProxyAdmin(0xBd8789025E91AF10487455B692419F82523D29Be);

    address user1 = address(0x1111);
    address user2 = address(0x2222);

    IERC20 token0 = IERC20(0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B);
    IERC20 token1 = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IERC20 rewardToken = IERC20(0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11);
    address poolAddress = address(0x7Db93DC92ecA0c59c530A0c4bCD26a7bf363d5D1);

    IThenaUniProxy thenaUniProxy = IThenaUniProxy(0xF75c017E3b023a593505e281b565ED35Cc120efa);

    ERC20LpListaDistributor slisBNBBNBThenaCorrelatedDistributor = ERC20LpListaDistributor(0xFf5ed1E64aCA62c822B178FFa5C36B40c112Eb00);
    StakingVault stakingVault;
    ThenaStaking thenaStaking;

    uint256 MAX_UINT256 = type(uint256).max;

    function setUp() public {
        vm.createSelectFork("bsc-main");

        deal(user1, 100 ether);
        deal(address(token0), user1, 10001 ether);
        deal(address(token1), user1, 10002 ether);

        deal(user2, 103 ether);
        deal(address(token0), user2, 10004 ether);
        deal(address(token1), user2, 10005 ether);


        vm.startPrank(owner);
        // deploy pancake staking vault
        StakingVault stakingVaultImpl = new StakingVault();
        TransparentUpgradeableProxy stakingVaultProxy = new TransparentUpgradeableProxy(
            address(stakingVaultImpl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(address,address,address)", owner, address(rewardToken), address(owner))
        );
        stakingVault = StakingVault(address(stakingVaultProxy));

        // deploy pancake staking
        ThenaStaking thenaStakingImpl = new ThenaStaking();
        TransparentUpgradeableProxy thenaStakingProxy = new TransparentUpgradeableProxy(
            address(thenaStakingImpl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(address,address)", owner, address(stakingVault))
        );
        thenaStaking = ThenaStaking(address(thenaStakingProxy));

        stakingVault.setStaking(address(thenaStaking));
        vm.stopPrank();

        // upgrade distributor
        vm.startPrank(proxyAdminOwner);
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(slisBNBBNBThenaCorrelatedDistributor));
        ERC20LpListaDistributor impl = new ERC20LpListaDistributor();
        proxyAdmin.upgradeAndCall(proxy, address(impl), "");
        vm.stopPrank();

        vm.startPrank(owner);
        // set staking address
        slisBNBBNBThenaCorrelatedDistributor.setStaking(address(thenaStaking));
        // set vault
        slisBNBBNBThenaCorrelatedDistributor.setStakeVault(address(stakingVault));
        // register pool
        thenaStaking.registerPool(address(lpToken), poolAddress, address(slisBNBBNBThenaCorrelatedDistributor));
        vm.stopPrank();

    }


    function test_deposit() public {
        uint256 user1Lp = addLiquidity(user1);
        console.log("user1 lp", lpToken.balanceOf(user1));

        vm.startPrank(user1);
        lpToken.approve(address(slisBNBBNBThenaCorrelatedDistributor), MAX_UINT256);

        slisBNBBNBThenaCorrelatedDistributor.deposit(user1Lp);
        console.log("user1 lp after deposit", lpToken.balanceOf(user1));

        skip(1 days);

        thenaStaking.harvest(address(lpToken));

        console.log("vault rewards", rewardToken.balanceOf(address(stakingVault)));

        skip(1 days);

        address[] memory distributors = new address[](1);
        distributors[0] = address(slisBNBBNBThenaCorrelatedDistributor);

        stakingVault.batchClaimRewards(distributors);

        console.log("user1 rewards", rewardToken.balanceOf(user1));

        slisBNBBNBThenaCorrelatedDistributor.withdraw(user1Lp);

        console.log("user1 lp after withdraw", lpToken.balanceOf(user1));
        vm.stopPrank();
    }

    function addLiquidity(address user) public returns (uint256) {
        vm.startPrank(user);
        token0.approve(address(lpToken), MAX_UINT256);
        token1.approve(address(lpToken), MAX_UINT256);

        uint256 amount0 = 100 ether;
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

    function test_emergencyWithdraw() public {
        (,,,,bool _active,) = thenaStaking.pools(address(lpToken));
        assertTrue(_active, "pool should be active");
        vm.startPrank(owner);

        address lpToken_ = address(slisBNBBNBThenaCorrelatedDistributor);
        thenaStaking.emergencyWithdraw(lpToken_);
        vm.stopPrank();

        assertTrue(thenaStaking.emergencyModeForLpToken(lpToken_), "emergency mode should be true");
    }
}
