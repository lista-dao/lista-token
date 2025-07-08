pragma solidity ^0.8.10;
import "forge-std/Test.sol";
import "../contracts/VeListaRewardsCourier.sol";
import "../contracts/VeLista.sol";

// CMD
// forge test -vvv --match-contract VeListaRewardsCourierTest --via-ir

// for test purpose, we need 2 more methods from VeListaDistributor
interface IVeListaDistributorAlt {
  function lastDepositWeek() external view returns (uint16);
  function grantRole(bytes32 role, address account) external;
}

contract VeListaRewardsCourierTest is Test {
  VeListaRewardsCourier veListaRewardsCourier;
  uint256 mainnet;
  address multiSig = address(0x8d388136d578dCD791D081c6042284CED6d9B0c6);
  address bot = makeAddr("bot");
  address veListaDistributor = address(0x45aAc046Bc656991c52cf25E783c6942425ce40C);
  VeLista veLista = VeLista(0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3);
  IERC20 lista = IERC20(address(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46));
  IERC20 slisBNB = IERC20(address(0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B));
  IERC20 lisUSD = IERC20(address(0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5));
  IERC20 wBETH = IERC20(address(0xa2E3356610840701BDf5611a53974510Ae27E2e1));

  IVeListaDistributor.TokenAmount[] public tokens;

  uint16 week;

  function setUp() public {
    mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");
    // new lista rewards courier contract
    vm.startPrank(multiSig);
    veListaRewardsCourier = new VeListaRewardsCourier();
    veListaRewardsCourier.initialize(multiSig, bot, veListaDistributor);
    // give some token to multiSig
    deal(address(lista), multiSig, 1000e18);
    deal(address(slisBNB), multiSig, 1000e18);
    deal(address(lisUSD), multiSig, 1000e18);
    deal(address(wBETH), multiSig, 1000e18);
    // @dev grant BOT role to `bot`
    veListaRewardsCourier.grantRole(veListaRewardsCourier.BOT(), bot);
    veListaRewardsCourier.grantRole(veListaRewardsCourier.DEFAULT_ADMIN_ROLE(), multiSig);
    veListaRewardsCourier.grantRole(veListaRewardsCourier.OPERATOR(), multiSig);

    // create rewards token array
    tokens.push(IVeListaDistributor.TokenAmount(address(lista), 11e18));
    tokens.push(IVeListaDistributor.TokenAmount(address(slisBNB), 22e18));
    tokens.push(IVeListaDistributor.TokenAmount(address(lisUSD), 33e18));
    tokens.push(IVeListaDistributor.TokenAmount(address(wBETH), 44e18));

    // approve all tokens to VeListaRewardsCourier
    lista.approve(address(veListaRewardsCourier), type(uint256).max);
    slisBNB.approve(address(veListaRewardsCourier), type(uint256).max);
    lisUSD.approve(address(veListaRewardsCourier), type(uint256).max);
    wBETH.approve(address(veListaRewardsCourier), type(uint256).max);

    vm.stopPrank();

    // @dev grant MANAGER role to veListaRewardsCourier
    // show that veListaRewardsCourier can deposit rewards to veListaDistributor
    vm.prank(multiSig);
    IVeListaDistributorAlt(veListaDistributor).grantRole(keccak256("MANAGER"), address(veListaRewardsCourier));

    // @dev mock ahead one week
    week = IVeListaDistributorAlt(veListaDistributor).lastDepositWeek() + 1;
  }

  function test_rechargeRewards() public {
    // mock timestamp ahead one week
    vm.warp(veLista.startTime() + uint256(week) * 1 weeks);
    // @dev Simulate the recharge
    vm.prank(multiSig);
    veListaRewardsCourier.rechargeRewards(week, tokens);

    // Validate results
    assertEq(veListaRewardsCourier.week(), week);
    assertEq(veListaRewardsCourier.rewardsDeliveredForWeek(), false);
    // validate tokens transferred from multiSig to VeListaRewardsCourier
    assertEq(lista.balanceOf(address(veListaRewardsCourier)), tokens[0].amount);
    assertEq(slisBNB.balanceOf(address(veListaRewardsCourier)), tokens[1].amount);
    assertEq(lisUSD.balanceOf(address(veListaRewardsCourier)), tokens[2].amount);
    assertEq(wBETH.balanceOf(address(veListaRewardsCourier)), tokens[3].amount);

    // @dev recharge again, it should fail
    vm.prank(multiSig);
    vm.expectRevert("Pending rewards delivery for the week");
    veListaRewardsCourier.rechargeRewards(week, tokens);
  }

  function test_deliverRewards() public {
    // mock timestamp ahead one week
    vm.warp(veLista.startTime() + (uint256(week) + 1) * 1 weeks);

    // recharge rewards first
    vm.prank(multiSig);
    veListaRewardsCourier.rechargeRewards(week, tokens);

    // pretend someone and deliver rewards
    vm.prank(makeAddr("someone"));
    vm.expectRevert("AccessControl: account 0x69979820b003b34127eadba93bd51caac2f768db is missing role 0x902cbe3a02736af9827fb6a90bada39e955c0941e08f0c63b3a662a7b17a4e2b");
    veListaRewardsCourier.deliverRewards();

    // bot delivers rewards
    vm.prank(bot);
    veListaRewardsCourier.deliverRewards();

    // validate rewards delivered
    assertEq(veListaRewardsCourier.rewardsDeliveredForWeek(), true);
    assertEq(lista.balanceOf(address(veListaRewardsCourier)), 0);
    assertEq(slisBNB.balanceOf(address(veListaRewardsCourier)), 0);
    assertEq(lisUSD.balanceOf(address(veListaRewardsCourier)), 0);
    assertEq(wBETH.balanceOf(address(veListaRewardsCourier)), 0);

    // validate rewards deposited to veListaDistributor
    IVeListaDistributor distributor = IVeListaDistributor(veListaDistributor);
    IVeListaDistributorAlt distributorAlt = IVeListaDistributorAlt(veListaDistributor);
    assertEq(distributorAlt.lastDepositWeek(), week);
    assertGe(lista.balanceOf(address(distributor)), tokens[0].amount);
    assertGe(slisBNB.balanceOf(address(distributor)), tokens[1].amount);
    assertGe(lisUSD.balanceOf(address(distributor)), tokens[2].amount);
    assertGe(wBETH.balanceOf(address(distributor)), tokens[3].amount);

    // @dev deliver once again, it should fail
    vm.prank(bot);
    vm.expectRevert("Rewards already delivered for the week");
    veListaRewardsCourier.deliverRewards();
  }

  function test_revoke_rewards() public {
    // mock timestamp ahead one week
    vm.warp(veLista.startTime() + uint256(week) * 1 weeks);
    vm.startPrank(multiSig);
    // @dev token recharged to VeListaRewardsCourier
    veListaRewardsCourier.rechargeRewards(week, tokens);
    assertEq(lista.balanceOf(address(veListaRewardsCourier)), tokens[0].amount);
    assertEq(slisBNB.balanceOf(address(veListaRewardsCourier)), tokens[1].amount);
    assertEq(lisUSD.balanceOf(address(veListaRewardsCourier)), tokens[2].amount);
    assertEq(wBETH.balanceOf(address(veListaRewardsCourier)), tokens[3].amount);
    vm.stopPrank();

    // @dev someone tries to revoke rewards, it should fail
    vm.prank(makeAddr("someone"));
    vm.expectRevert("AccessControl: account 0x69979820b003b34127eadba93bd51caac2f768db is missing role 0x523a704056dcd17bcf83bed8b68c59416dac1119be77755efe3bde0a64e46e0c");
    veListaRewardsCourier.revokeRewards();

    // @dev multiSig revoke rewards
    vm.prank(multiSig);
    veListaRewardsCourier.revokeRewards();

    // token transferred back to multiSig
    assertEq(lista.balanceOf(address(veListaRewardsCourier)), 0);
    assertEq(slisBNB.balanceOf(address(veListaRewardsCourier)), 0);
    assertEq(lisUSD.balanceOf(address(veListaRewardsCourier)), 0);
    assertEq(wBETH.balanceOf(address(veListaRewardsCourier)), 0);

    // @dev revoke once again, it should fail
    vm.prank(multiSig);
    vm.expectRevert("Rewards already delivered for the week");
    veListaRewardsCourier.revokeRewards();
  }

}
