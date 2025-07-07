pragma solidity ^0.8.10;
import "forge-std/Test.sol";
import "../contracts/VeListaRewardsCourierV2.sol";
import "../contracts/VeLista.sol";
import "../contracts/VeListaDistributor.sol";

// CMD
// forge test -vvv --match-contract VeListaRewardsCourierV2Test --via-ir

// for test purpose, we need 2 more methods from VeListaDistributor
interface IVeListaDistributorAlt {
    function lastDepositWeek() external view returns (uint16);
    function grantRole(bytes32 role, address account) external;
}

contract VeListaRewardsCourierV2Test is Test {

    uint256 mainnet;
    address multiSig = address(0x8d388136d578dCD791D081c6042284CED6d9B0c6);
    address bot = makeAddr("bot");
    address distributor = makeAddr("distributor");

    VeListaRewardsCourierV2 veListaRewardsCourierV2;
    VeLista veLista = VeLista(0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3);
    VeListaDistributor veListaDistributor = VeListaDistributor(0x45aAc046Bc656991c52cf25E783c6942425ce40C);
    IERC20 lista = IERC20(address(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46));

    function setUp() public {
        mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");
        // new lista rewards courier contract
        vm.startPrank(multiSig);
        veListaRewardsCourierV2 = new VeListaRewardsCourierV2();
        veListaRewardsCourierV2.initialize(
            address(lista),
            multiSig,
            bot,
            distributor,
            address(veLista),
            address(veListaDistributor)
        );

        // give some token to multiSig
        deal(address(lista), distributor, 1000e18);

        // @dev grant BOT role to `bot`
        veListaRewardsCourierV2.grantRole(veListaRewardsCourierV2.BOT(), bot);
        veListaRewardsCourierV2.grantRole(veListaRewardsCourierV2.DEFAULT_ADMIN_ROLE(), multiSig);
        vm.stopPrank();

        // approve all tokens to VeListaRewardsCourierV2
        vm.prank(distributor);
        lista.approve(address(veListaRewardsCourierV2), type(uint256).max);

        // @dev grant MANAGER role to veListaRewardsCourierV2
        // show that veListaRewardsCourierV2 can deposit rewards to veListaDistributor
        vm.prank(multiSig);
        IVeListaDistributorAlt(0x45aAc046Bc656991c52cf25E783c6942425ce40C).grantRole(keccak256("MANAGER"), address(veListaRewardsCourierV2));
    }

    function test_rechargeRewards() public {

        uint256 WEEK = 1 weeks;
        uint256 DAY = 1 days;
        uint16 rewardWeek = veLista.getCurrentWeek();
        uint256 rewardWeekTimestamp = veLista.startTime() + uint256(rewardWeek) * WEEK;
        uint256 now = block.timestamp;
        // actual rewards belongs to rewardWeek - 1
        if (now > rewardWeekTimestamp + 5 * DAY) {
            rewardWeek += 1;
        }

        // @dev Simulate the recharge
        uint256 amount = 50e18;
        vm.startPrank(distributor);
        veListaRewardsCourierV2.rechargeRewards(amount);
        veListaRewardsCourierV2.rechargeRewards(amount);
        // validate tokens transferred from multiSig to VeListaRewardsCourierV2
        assertEq(lista.balanceOf(address(veListaRewardsCourierV2)), amount * 2);
        assertEq(veListaRewardsCourierV2.weeklyRewardAmounts(rewardWeek), amount * 2);
        vm.stopPrank();
    }

    function test_deliverRewards() public {

        uint256 WEEK = 1 weeks;
        uint256 DAY = 1 days;
        uint16 rewardWeek = veLista.getCurrentWeek();
        uint256 rewardWeekTimestamp = veLista.startTime() + uint256(rewardWeek) * WEEK;
        uint256 now = block.timestamp;
        // actual rewards belongs to rewardWeek - 1
        if (now > rewardWeekTimestamp + 5 * DAY) {
            rewardWeek += 1;
        }

        // recharge rewards first
        vm.prank(distributor);
        uint256 amount = 50e18;
        veListaRewardsCourierV2.rechargeRewards(amount);
        assertEq(veListaRewardsCourierV2.weeklyRewardAmounts(rewardWeek), amount);

        // pretend someone and deliver rewards
        vm.prank(makeAddr("someone"));
        vm.expectRevert("AccessControl: account 0x69979820b003b34127eadba93bd51caac2f768db is missing role 0x902cbe3a02736af9827fb6a90bada39e955c0941e08f0c63b3a662a7b17a4e2b");
        veListaRewardsCourierV2.deliverRewards();
        assertEq(veListaRewardsCourierV2.weeklyRewardAmounts(rewardWeek), amount);

        // bot delivers rewards
        vm.warp(rewardWeekTimestamp + 1 weeks);
        vm.prank(bot);
        veListaRewardsCourierV2.deliverRewards();
        assertEq(veListaRewardsCourierV2.rewardsDeliveredForWeek(rewardWeek - 1), true);

        // @dev deliver once again, it should fail
        vm.prank(bot);
        vm.expectRevert("Rewards already delivered for the week");
        veListaRewardsCourierV2.deliverRewards();
    }

}
