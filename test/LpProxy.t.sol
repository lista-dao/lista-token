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
import "./interfaces/IPancakeStableSwapTwoPool.sol";
import "../contracts/dao/StakingVault.sol";
import "../contracts/dao/PancakeStaking.sol";
import "../contracts/dao/LpProxy.sol";

contract LpProxyTest is Test {
    VeLista public veLista = VeLista(0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3);
    ListaToken public lista = ListaToken(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46);
    ListaVault listaVault = ListaVault(0x307d13267f360f78005f476Fa913F8848F30292A);
    IERC20 lpToken = IERC20(0xB2Aa63f363196caba3154D4187949283F085a488);

    address owner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;

    address proxyAdminOwner = 0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253;
    ProxyAdmin proxyAdmin = ProxyAdmin(0x87fD7d3D119C1e11cEf73f20e227e152ce35F103);
    ProxyAdmin listaVaultProxyAdmin = ProxyAdmin(0xd6cd036133cbf6a275B7700fF7B41887A9d5FCAe);

    address user1 = address(0x1111);
    address user2 = address(0x2222);

    IERC20 token0 = IERC20(0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5);
    IERC20 token1 = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 rewardToken = IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    address poolAddress = address(0xd069a9E50E4ad04592cb00826d312D9f879eBb02);

    IPancakeStableSwapTwoPool pancakeStableSwapTwoPool = IPancakeStableSwapTwoPool(0xb1Da7D2C257c5700612BdE35C8d7187dc80d79f1);

    ERC20LpListaDistributor lisUSDUSDTPancakeStablePoolDistributor = ERC20LpListaDistributor(0xe8f4644637f127aFf11F9492F41269eB5e8b8dD2);
    StakingVault stakingVault;
    PancakeStaking pancakeStaking;

    LpProxy lpProxy;

    uint256 MAX_UINT256 = type(uint256).max;

    function setUp() public {
        vm.createSelectFork("bsc");

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
        PancakeStaking pancakeStakingImpl = new PancakeStaking();
        TransparentUpgradeableProxy pancakeStakingProxy = new TransparentUpgradeableProxy(
            address(pancakeStakingImpl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(address,address)", owner, address(stakingVault))
        );
        pancakeStaking = PancakeStaking(address(pancakeStakingProxy));

        LpProxy lpProxyImpl = new LpProxy();
        TransparentUpgradeableProxy lpProxyProxy = new TransparentUpgradeableProxy(
            address(lpProxyImpl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(address)", owner)
        );
        lpProxy = LpProxy(address(lpProxyProxy));

        stakingVault.setStaking(address(pancakeStaking));
        vm.stopPrank();

        // upgrade distributor
        vm.startPrank(proxyAdminOwner);
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(lisUSDUSDTPancakeStablePoolDistributor));
        ERC20LpListaDistributor impl = new ERC20LpListaDistributor();
        proxyAdmin.upgradeAndCall(proxy, address(impl), "");

        ListaVault listaVaultLogic = new ListaVault();
        ITransparentUpgradeableProxy listaVaultProxy = ITransparentUpgradeableProxy(address(listaVault));
        listaVaultProxyAdmin.upgradeAndCall(listaVaultProxy, address(listaVaultLogic), "");
        vm.stopPrank();

        vm.startPrank(owner);
        // set staking address
        lisUSDUSDTPancakeStablePoolDistributor.setStaking(address(pancakeStaking));
        // set vault
        lisUSDUSDTPancakeStablePoolDistributor.setStakeVault(address(stakingVault));
        // register pool
        pancakeStaking.registerPool(address(lpToken), poolAddress, address(lisUSDUSDTPancakeStablePoolDistributor));
        // set listaVault
        lpProxy.setListaVault(address(listaVault));
        // set cakeVault
        lpProxy.setCakeVault(address(stakingVault));
        // listaVault set lp proxy
        listaVault.setLpProxy(address(lpProxy));
        // cakeVault set lp proxy
        stakingVault.setLpProxy(address(lpProxy));
        // set distributor to vault
        lpProxy.setDistributorToVault(address(lisUSDUSDTPancakeStablePoolDistributor), address(stakingVault));
        vm.stopPrank();

    }


    function test_deposit() public {
        uint256 user1Lp = addLiquidity(user1);
        console.log("user1 lp", lpToken.balanceOf(user1));

        vm.startPrank(user1);
        lpToken.approve(address(lisUSDUSDTPancakeStablePoolDistributor), MAX_UINT256);

        lisUSDUSDTPancakeStablePoolDistributor.deposit(user1Lp);
        console.log("user1 lp after deposit", lpToken.balanceOf(user1));

        skip(1 days);

        pancakeStaking.harvest(address(lpToken));

        console.log("vault rewards", rewardToken.balanceOf(address(stakingVault)));

        skip(1 days);

        address[] memory distributors = new address[](1);
        distributors[0] = address(lisUSDUSDTPancakeStablePoolDistributor);

//        lpProxy.claimAll(distributors);
        stakingVault.batchClaimRewards(distributors);

        console.log("user1 rewards", rewardToken.balanceOf(user1));

        lisUSDUSDTPancakeStablePoolDistributor.withdraw(user1Lp);

        console.log("user1 lp after withdraw", lpToken.balanceOf(user1));
        vm.stopPrank();
    }

    function addLiquidity(address user) public returns (uint256) {
        vm.startPrank(user);
        token0.approve(address(pancakeStableSwapTwoPool), MAX_UINT256);
        token1.approve(address(pancakeStableSwapTwoPool), MAX_UINT256);

        uint256[2] memory amounts = [
                            uint256(100 ether),
                            uint256(100 ether)
            ];
        pancakeStableSwapTwoPool.add_liquidity(amounts, 0);

        vm.stopPrank();

        return lpToken.balanceOf(user);
    }


}
