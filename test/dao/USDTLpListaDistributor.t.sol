// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IDistributor } from "../../contracts/dao/interfaces/IDistributor.sol";
import { IV2Wrapper } from "../../contracts/dao/interfaces/IV2Wrapper.sol";

import { USDTLpListaDistributor } from "../../contracts/dao/USDTLpListaDistributor.sol";
import { VeLista } from "../../contracts/VeLista.sol";
import { ListaToken } from "../../contracts/ListaToken.sol";
import { ListaVault } from "../../contracts/dao/ListaVault.sol";
import { PancakeStaking } from "../../contracts/dao/PancakeStaking.sol";
import { StakingVault } from "../../contracts/dao/StakingVault.sol";

import "../../contracts/mock/MockERC20.sol";

contract USDTLpListaDistributorTest is Test {
  address stableSwap = 0xb1Da7D2C257c5700612BdE35C8d7187dc80d79f1;
  address stableSwapPoolInfo = 0x150c8AbEB487137acCC541925408e73b92F39A50;
  address usdt = 0x55d398326f99059fF775485246999027B3197955;
  address lisUSD = 0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5;
  address v2wrapper = 0xd069a9E50E4ad04592cb00826d312D9f879eBb02; // stableswap LP farming
  address cake = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
  IERC20 lpToken = IERC20(0xB2Aa63f363196caba3154D4187949283F085a488);

  address stakingVaultOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;

  ProxyAdmin public proxyAdminStakingVault = ProxyAdmin(0x1d7296C2a2dE261732931F82174272A361E21B0b);
  address proxyAdminOwnerStakingVault = 0x08aE09467ff962aF105c23775B9Bc8EAa175D27F;
  ITransparentUpgradeableProxy stakingVaultProxy =
    ITransparentUpgradeableProxy(0x62DfeC5C9518fE2e0ba483833d1BAD94ecF68153);
  StakingVault public stakingVault = StakingVault(0x62DfeC5C9518fE2e0ba483833d1BAD94ecF68153);

  ListaToken public lista = ListaToken(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46);
  VeLista public veLista = VeLista(0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3);

  ListaVault listaVault;
  USDTLpListaDistributor usdtDistributor;

  ProxyAdmin public proxyAdmin = ProxyAdmin(0xc78f64Cd367bD7d2922088669463FCEE33f50b7c);
  address proxyAdminOwner = 0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06;

  address manager = makeAddr("manager");
  address user1 = makeAddr("user1");
  address user2 = makeAddr("user2");
  uint256 MAX_UINT = type(uint256).max;

  function setUp() public {
    vm.createSelectFork("https://rpc.ankr.com/bsc", 43143645);

    // Upgrade StakingVault
    vm.startPrank(proxyAdminOwnerStakingVault);
    StakingVault stakingVaultLogic = new StakingVault();
    proxyAdminStakingVault.upgradeAndCall{ value: 0 }(stakingVaultProxy, address(stakingVaultLogic), bytes(""));
    vm.stopPrank();

    vm.startPrank(proxyAdminOwner);
    ListaVault listaVaultLogic = new ListaVault();
    TransparentUpgradeableProxy listaVaultProxy = new TransparentUpgradeableProxy(
      address(listaVaultLogic),
      proxyAdminOwner,
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        manager,
        manager,
        address(lista),
        address(veLista)
      )
    );
    listaVault = ListaVault(address(listaVaultProxy));

    USDTLpListaDistributor distributorLogic = new USDTLpListaDistributor(
      address(stableSwap),
      address(stableSwapPoolInfo),
      address(v2wrapper)
    );
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(distributorLogic),
      proxyAdminOwner,
      abi.encodeWithSignature(
        "initialize(address,address,address,address,address)",
        manager,
        manager,
        manager,
        address(listaVault),
        address(stakingVault)
      )
    );
    usdtDistributor = USDTLpListaDistributor(address(proxy));
    vm.stopPrank();

    deal(address(usdt), user1, 10000 ether); // 10000 USDT
    deal(address(lista), manager, 1000000 ether); // 1M LISTA

    vm.prank(user1);
    IERC20(usdt).approve(address(usdtDistributor), MAX_UINT);
    vm.stopPrank();

    // Set usdt distributor to the staking vault
    vm.startPrank(stakingVaultOwner);
    stakingVault.setUsdtDistributor(address(usdtDistributor));
    vm.stopPrank();

    skip(1 weeks);
  }

  function test_depositRewards() public {
    vm.mockCall(address(lista), abi.encodeWithSignature("approve()"), abi.encode(uint256(MAX_UINT)));

    uint16 currentWeek = veLista.getCurrentWeek();
    vm.startPrank(manager);
    lista.approve(address(listaVault), MAX_UINT);
    listaVault.depositRewards(100 ether, currentWeek + 1);
    listaVault.depositRewards(200 ether, currentWeek + 2);
    vm.stopPrank();

    uint256 week1Emission = listaVault.weeklyEmissions(currentWeek + 1);
    uint256 week2Emission = listaVault.weeklyEmissions(currentWeek + 2);
    assertEq(week1Emission, 100 ether);
    assertEq(week2Emission, 200 ether);
  }

  function test_registerReceiver() public {
    vm.startPrank(manager);
    uint16 id = listaVault.registerDistributor(address(usdtDistributor));
    vm.stopPrank();

    assertEq(listaVault.idToDistributor(id), address(usdtDistributor), "register receiver failed");
    assertEq(usdtDistributor.distributorId(), id, "register receiver id error");
  }

  function test_setWeeklyReceiverPercent() public {
    uint16 currentWeek = veLista.getCurrentWeek();
    vm.startPrank(manager);
    uint16 id = listaVault.registerDistributor(address(usdtDistributor));
    uint16[] memory ids = new uint16[](1);
    ids[0] = id;
    uint256[] memory percents = new uint256[](1);
    percents[0] = 1e18;
    listaVault.setWeeklyDistributorPercent(currentWeek + 1, ids, percents);

    lista.approve(address(listaVault), MAX_UINT);
    listaVault.depositRewards(100 ether, currentWeek + 1);
    vm.stopPrank();

    assertEq(listaVault.weeklyDistributorPercent(currentWeek + 1, 0), 1, "set weekly receiver percent failed");
    assertEq(listaVault.weeklyDistributorPercent(currentWeek + 1, id), 1e18, "set weekly receiver percent failed");
    assertEq(
      listaVault.getDistributorWeeklyEmissions(id, currentWeek + 1),
      100 ether,
      "get receiver weekly emissions error"
    );
  }

  function test_deposit() public {
    uint256 usdtAmt = 10 ether; // 10 USDT
    uint256 expectLpMinted = usdtDistributor.getLpToMint(usdtAmt);

    vm.startPrank(user1);
    vm.expectRevert("Invalid min lp amount");
    usdtDistributor.deposit(usdtAmt, expectLpMinted + 1 ether);
    usdtDistributor.deposit(usdtAmt, expectLpMinted);
    vm.stopPrank();

    uint256 lpBalance = usdtDistributor.balanceOf(user1);
    uint256 totalSupply = usdtDistributor.totalSupply();
    assertEq(lpBalance, expectLpMinted, "user1 balance error");
    assertEq(totalSupply, expectLpMinted, "total supply error");
  }

  function test_withdraw() public {
    // Step 1. User1 deposit 10 USDT
    uint256 usdtAmt = 10 ether; // 10 USDT
    uint256 expectLpMinted = usdtDistributor.getLpToMint(usdtAmt);
    vm.startPrank(user1);
    usdtDistributor.deposit(usdtAmt, expectLpMinted);
    vm.stopPrank();
    assertEq(usdtDistributor.balanceOf(user1), expectLpMinted, "user1's lp balance should be updated correctly");

    skip(1 weeks);

    // Step 2. User1 withdraw
    uint256 lisUSDBalance = IERC20(lisUSD).balanceOf(user1);
    uint256 usdtBalance = IERC20(usdt).balanceOf(user1);
    (uint256 _lisUSDAmount, uint256 _usdtAmount) = usdtDistributor.getCoinsAmount(usdtDistributor.balanceOf(user1));
    vm.startPrank(user1);
    usdtDistributor.withdraw(usdtDistributor.balanceOf(user1), _lisUSDAmount, _usdtAmount);
    vm.stopPrank();

    // Check user1's LP balance, distributor's total supply, and user1's lisUSD and USDT balance
    assertEq(usdtDistributor.balanceOf(user1), 0, "user1's lp balance should be zero");
    assertEq(usdtDistributor.totalSupply(), 0, "distributor's lp total supply should be zero");
    uint256 lisUSDBalanceAfter = IERC20(lisUSD).balanceOf(user1);
    uint256 usdtBalanceAfter = IERC20(usdt).balanceOf(user1);
    assertEq(lisUSDBalanceAfter, lisUSDBalance + _lisUSDAmount, "lisUSD amount is not correct");
    assertEq(usdtBalanceAfter, usdtBalance + _usdtAmount, "usdt amount is not correct");
  }

  function test_fetchRewards_lista() public {
    uint16 currentWeek = veLista.getCurrentWeek();
    uint256 weekAmount = 700 ether;
    vm.startPrank(manager);

    lista.approve(address(listaVault), MAX_UINT);
    listaVault.depositRewards(weekAmount, currentWeek + 1);

    uint16 id = listaVault.registerDistributor(address(usdtDistributor));

    uint16[] memory ids = new uint16[](1);
    ids[0] = id;
    uint256[] memory percents = new uint256[](1);
    percents[0] = 1e18;
    listaVault.setWeeklyDistributorPercent(currentWeek + 1, ids, percents);

    vm.stopPrank();

    skip(1 weeks);

    vm.startPrank(user1);
    usdtDistributor.fetchRewards();
    vm.stopPrank();

    assertEq(usdtDistributor.rewardRate(), weekAmount / 1 weeks, "reward rate error");
    assertEq(usdtDistributor.lastUpdate(), block.timestamp, "last update error");
    assertEq(usdtDistributor.periodFinish(), block.timestamp + 1 weeks, "period finish error");
  }

  function test_claimReward_lista() public {
    uint16 currentWeek = veLista.getCurrentWeek();
    uint256 weekAmount = 700 ether;

    // Step 1. Deposit rewards and register distributor
    vm.startPrank(manager);
    lista.approve(address(listaVault), MAX_UINT);
    listaVault.depositRewards(weekAmount, currentWeek + 1);

    uint16 id = listaVault.registerDistributor(address(usdtDistributor));

    uint16[] memory ids = new uint16[](1);
    ids[0] = id;
    uint256[] memory percents = new uint256[](1);
    percents[0] = 1e18;
    listaVault.setWeeklyDistributorPercent(currentWeek + 1, ids, percents);
    vm.stopPrank();

    // Step 2. User1 deposit 10 USDT
    uint256 usdtAmt = 10 ether; // 10 USDT
    uint256 expectLpMinted = usdtDistributor.getLpToMint(usdtAmt);
    vm.startPrank(user1);
    usdtDistributor.deposit(usdtAmt, expectLpMinted);
    vm.stopPrank();
    assertEq(usdtDistributor.balanceOf(user1), expectLpMinted, "user1's lp balance should be updated correctly");

    // Step 3. Fetch rewards
    skip(1 weeks);
    usdtDistributor.fetchRewards();

    address[] memory distributors = new address[](1);
    distributors[0] = address(usdtDistributor);

    // Step 4. Claim rewards
    skip(1 days);
    uint256 claimable = usdtDistributor.claimableReward(user1);
    uint256 rewardRate = usdtDistributor.rewardRate();
    assertApproxEqAbs(claimable, rewardRate * 1 days, 1, "claimable amount is incorrect");

    vm.startPrank(user1);
    listaVault.batchClaimRewards(distributors);
    vm.stopPrank();
    uint256 listaBalance = lista.balanceOf(user1);
    assertApproxEqAbs(listaBalance, claimable, 1, "reward amount is incorrect");
  }

  function test_harvest() public {
    // Step 1. User1 deposit 10 USDT
    uint256 usdtAmt = 10 ether; // 10 USDT
    uint256 expectLpMinted = usdtDistributor.getLpToMint(usdtAmt);
    vm.startPrank(user1);
    usdtDistributor.deposit(usdtAmt, expectLpMinted);
    vm.stopPrank();
    assertEq(usdtDistributor.balanceOf(user1), expectLpMinted, "user1's lp balance should be updated correctly");

    skip(1 days);

    // Step 2. Harvest
    uint256 pending = IV2Wrapper(v2wrapper).pendingReward(address(usdtDistributor));
    uint256 claimed = usdtDistributor.harvest();
    assertEq(claimed, pending, "harvest amount is incorrect");
  }

  function test_emergencyWithdraw() public {
    // Step 1. User1 deposit 10 USDT
    uint256 usdtAmt = 10 ether; // 10 USDT
    uint256 expectLpMinted = usdtDistributor.getLpToMint(usdtAmt);
    vm.startPrank(user1);
    usdtDistributor.deposit(usdtAmt, expectLpMinted);
    vm.stopPrank();
    assertEq(usdtDistributor.balanceOf(user1), expectLpMinted, "user1's lp balance should be updated correctly");

    skip(1 weeks);

    // Step 2. Emergency withdraw
    uint256 exitAmount = IERC20(lpToken).balanceOf(address(usdtDistributor));
    vm.startPrank(manager);
    usdtDistributor.emergencyWithdraw();
    vm.stopPrank();
    exitAmount = IERC20(lpToken).balanceOf(address(usdtDistributor)) - exitAmount;

    assertEq(exitAmount, expectLpMinted, "emergency withdraw amount is incorrect");
    assertEq(usdtDistributor.emergencyMode(), true, "emergency mode should be turned on");
  }

  function test_withdraw_on_emergencyMode() public {
    // Step 1. User1 deposit 10 USDT
    uint256 usdtAmt = 10 ether; // 10 USDT
    uint256 expectLpMinted = usdtDistributor.getLpToMint(usdtAmt);
    vm.startPrank(user1);
    usdtDistributor.deposit(usdtAmt, expectLpMinted);
    vm.stopPrank();
    assertEq(usdtDistributor.balanceOf(user1), expectLpMinted, "user1's lp balance should be updated correctly");

    skip(1 weeks);

    // Step 2. Emergency withdraw
    uint256 exitAmount = IERC20(lpToken).balanceOf(address(usdtDistributor));
    vm.startPrank(manager);
    usdtDistributor.emergencyWithdraw();
    vm.stopPrank();
    exitAmount = IERC20(lpToken).balanceOf(address(usdtDistributor)) - exitAmount;

    assertEq(exitAmount, expectLpMinted, "emergency withdraw amount is incorrect");
    assertEq(usdtDistributor.emergencyMode(), true, "emergency mode should be turned on");

    // Step 3. User1 withdraw
    uint256 lisUSDBalance = IERC20(lisUSD).balanceOf(user1);
    uint256 usdtBalance = IERC20(usdt).balanceOf(user1);
    (uint256 _lisUSDAmount, uint256 _usdtAmount) = usdtDistributor.getCoinsAmount(usdtDistributor.balanceOf(user1));
    vm.startPrank(user1);
    usdtDistributor.withdraw(usdtDistributor.balanceOf(user1), _lisUSDAmount, _usdtAmount);
    vm.stopPrank();

    // Check user1's LP balance, distributor's total supply, and user1's lisUSD and USDT balance
    assertEq(usdtDistributor.balanceOf(user1), 0, "user1's lp balance should be zero");
    assertEq(usdtDistributor.totalSupply(), 0, "distributor's lp total supply should be zero");
    uint256 lisUSDBalanceAfter = IERC20(lisUSD).balanceOf(user1);
    uint256 usdtBalanceAfter = IERC20(usdt).balanceOf(user1);
    assertEq(lisUSDBalanceAfter, lisUSDBalance + _lisUSDAmount, "lisUSD amount is not correct");
  }

  function test_setHarvestTimeGap() public {
    uint256 harvestTimeGap = 1 days;
    vm.startPrank(manager);
    usdtDistributor.setHarvestTimeGap(harvestTimeGap);
    vm.stopPrank();

    assertEq(usdtDistributor.harvestTimeGap(), harvestTimeGap, "harvest time gap is incorrect");
  }

  function test_stopEmergencyMode() public {
    // Step 1. User1 deposit 10 USDT
    uint256 usdtAmt = 10 ether; // 10 USDT
    uint256 expectLpMinted = usdtDistributor.getLpToMint(usdtAmt);
    vm.startPrank(user1);
    usdtDistributor.deposit(usdtAmt, expectLpMinted);
    vm.stopPrank();
    assertEq(usdtDistributor.balanceOf(user1), expectLpMinted, "user1's lp balance should be updated correctly");

    skip(1 weeks);

    // Step 2. Emergency withdraw
    uint256 exitAmount = IERC20(lpToken).balanceOf(address(usdtDistributor));
    vm.startPrank(manager);
    usdtDistributor.emergencyWithdraw();
    vm.stopPrank();
    exitAmount = IERC20(lpToken).balanceOf(address(usdtDistributor)) - exitAmount;

    assertEq(exitAmount, expectLpMinted, "emergency withdraw amount is incorrect");
    assertEq(usdtDistributor.emergencyMode(), true, "emergency mode should be turned on");

    // Step 3. Stop emergency mode
    vm.startPrank(manager);
    usdtDistributor.stopEmergencyMode();
    vm.stopPrank();

    assertEq(usdtDistributor.emergencyMode(), false, "emergency mode should be turned off");
  }

  function test_setIsActive() public {
    vm.startPrank(manager);
    usdtDistributor.setIsActive(false);
    vm.stopPrank();

    assertEq(usdtDistributor.isActive(), false, "is active should be false");

    // deposit should fail
    uint256 usdtAmt = 10 ether; // 10 USDT
    uint256 expectLpMinted = usdtDistributor.getLpToMint(usdtAmt);
    vm.startPrank(user1);
    vm.expectRevert("Distributor is not active");
    usdtDistributor.deposit(usdtAmt, expectLpMinted);
    vm.stopPrank();
  }
}
