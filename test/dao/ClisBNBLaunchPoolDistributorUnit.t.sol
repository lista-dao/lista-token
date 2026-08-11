// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../../contracts/dao/ClisBNBLaunchPoolDistributor.sol";
import "../../contracts/mock/MockERC20.sol";

/// @dev Non-fork unit tests for ClisBNBLaunchPoolDistributor.topUpEpoch.
///      Reproduces the launchpool under-funding bug (totalAmount < Σ leaves)
///      and verifies topUpEpoch remediates it. topUpEpoch is DEFAULT_ADMIN_ROLE-gated
///      (like collectUnclaimed / adminTransfer), while setEpochMerkleRoot stays OPERATOR.
///      Uses a MockERC20 reward token so no mainnet fork is needed (dev unit style,
///      cf. PreIPODistributor.t.sol).
contract ClisBNBLaunchPoolDistributorUnitTest is Test {
    address admin = makeAddr("admin"); // holds DEFAULT_ADMIN_ROLE (set in initialize)
    address operator = makeAddr("operator"); // holds OPERATOR only
    address outsider = makeAddr("outsider");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    ClisBNBLaunchPoolDistributor dist;
    MockERC20 token;

    uint64 constant EPOCH = 0;
    uint256 constant ALICE_AMT = 100e18;
    uint256 constant BOB_AMT = 200e18;
    uint256 constant SIGMA = 300e18; // Σ leaves = the correct total

    bytes32 leafAlice;
    bytes32 leafBob;
    bytes32 root;

    // mirror of the contract event, for expectEmit
    event TopUpEpoch(uint64 epochId, address token, uint256 oldTotalAmount, uint256 newTotalAmount, uint256 addedAmount);

    function setUp() public {
        token = new MockERC20(admin, "Mock", "MCK");

        ClisBNBLaunchPoolDistributor impl = new ClisBNBLaunchPoolDistributor();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(ClisBNBLaunchPoolDistributor.initialize.selector, admin)
        );
        dist = ClisBNBLaunchPoolDistributor(payable(address(proxy)));

        // admin already holds DEFAULT_ADMIN_ROLE from initialize; grant OPERATOR to operator
        vm.startPrank(admin);
        dist.grantRole(dist.OPERATOR(), operator);
        vm.stopPrank();

        // leaf = keccak256(abi.encode(chainid, epochId, account, amount))
        leafAlice = keccak256(abi.encode(block.chainid, EPOCH, alice, ALICE_AMT));
        leafBob = keccak256(abi.encode(block.chainid, EPOCH, bob, BOB_AMT));
        root = _hashPair(leafAlice, leafBob);
    }

    // ---- helpers ----

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _proof(bytes32 sibling) internal pure returns (bytes32[] memory p) {
        p = new bytes32[](1);
        p[0] = sibling;
    }

    /// @dev create epoch with a (possibly under-set) totalAmount and activate it. Uses
    ///      OPERATOR since setEpochMerkleRoot is OPERATOR-gated (unchanged by this feature).
    function _createEpoch(address _token, uint256 _totalAmount) internal {
        vm.prank(operator);
        dist.setEpochMerkleRoot(EPOCH, root, _token, block.timestamp + 10, block.timestamp + 1000, _totalAmount);
        skip(11); // pass startTime so claims are active
    }

    function _epoch() internal view returns (ClisBNBLaunchPoolDistributor.Epoch memory) {
        uint64[] memory ids = new uint64[](1);
        ids[0] = EPOCH;
        return dist.getEpochs(ids)[0];
    }

    // ---- primary behavioral test ----

    function test_topUpEpoch_unblocksTailClaim() public {
        // under-funded epoch: totalAmount(100) < Σ leaves(300)
        _createEpoch(address(token), ALICE_AMT);
        deal(address(token), address(dist), ALICE_AMT); // funded only to the under-set total

        // alice is within the cap and claims fine
        dist.claim(EPOCH, alice, ALICE_AMT, _proof(leafBob));
        assertEq(token.balanceOf(alice), ALICE_AMT);

        // bob (tail) is blocked: accounting underflows once the under-set cap is drained
        vm.expectRevert(stdError.arithmeticError);
        dist.claim(EPOCH, bob, BOB_AMT, _proof(leafAlice));

        // remediation: fund the missing delta, then raise the cap to the correct total (admin)
        deal(address(token), address(dist), BOB_AMT);
        vm.prank(admin);
        dist.topUpEpoch(EPOCH, SIGMA);

        // bob can now claim his full reward
        dist.claim(EPOCH, bob, BOB_AMT, _proof(leafAlice));
        assertEq(token.balanceOf(bob), BOB_AMT);
        assertEq(token.balanceOf(address(dist)), 0);
    }

    // ---- guards ----

    function test_topUpEpoch_revertsWhenNotAdmin() public {
        _createEpoch(address(token), ALICE_AMT);
        deal(address(token), address(dist), SIGMA);

        // holding OPERATOR is not enough: topUpEpoch requires DEFAULT_ADMIN_ROLE
        string memory err = string(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(operator),
                " is missing role ",
                Strings.toHexString(uint256(dist.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        vm.prank(operator);
        vm.expectRevert(bytes(err));
        dist.topUpEpoch(EPOCH, SIGMA);
    }

    function test_topUpEpoch_revertsWhenNotIncrease() public {
        _createEpoch(address(token), SIGMA); // already the correct total
        deal(address(token), address(dist), SIGMA);

        vm.startPrank(admin);
        vm.expectRevert("Not an increase");
        dist.topUpEpoch(EPOCH, SIGMA); // equal -> reject
        vm.expectRevert("Not an increase");
        dist.topUpEpoch(EPOCH, SIGMA - 1); // lower -> reject
        vm.stopPrank();
    }

    function test_topUpEpoch_revertsWhenInsufficientFunds() public {
        _createEpoch(address(token), ALICE_AMT); // under-set to 100
        deal(address(token), address(dist), ALICE_AMT); // only 100 funded

        vm.prank(admin);
        vm.expectRevert("Insufficient funds"); // raising cap to 300 > balance 100
        dist.topUpEpoch(EPOCH, SIGMA);
    }

    function test_topUpEpoch_revertsWhenInvalidEpochId() public {
        vm.prank(admin);
        vm.expectRevert("Invalid epochId");
        dist.topUpEpoch(5, SIGMA); // no such epoch
    }

    function test_topUpEpoch_updatesAccountingAndEmits() public {
        _createEpoch(address(token), ALICE_AMT); // 100
        deal(address(token), address(dist), SIGMA); // fund to correct total

        vm.expectEmit(true, true, true, true, address(dist));
        emit TopUpEpoch(EPOCH, address(token), ALICE_AMT, SIGMA, SIGMA - ALICE_AMT);
        vm.prank(admin);
        dist.topUpEpoch(EPOCH, SIGMA);

        ClisBNBLaunchPoolDistributor.Epoch memory e = _epoch();
        assertEq(e.totalAmount, SIGMA);
        assertEq(e.unclaimedAmount, SIGMA); // no claims yet
        assertEq(dist.totalUnclaimedAmount(address(token)), SIGMA);
    }

    function test_topUpEpoch_revertsWhenEpochEnded() public {
        _createEpoch(address(token), ALICE_AMT);
        deal(address(token), address(dist), SIGMA);

        skip(2000); // move past endTime (set to now + 1000 at creation)

        // topping up a dead epoch is a no-op for claim() and would only strand accounting
        vm.prank(admin);
        vm.expectRevert("Epoch ended");
        dist.topUpEpoch(EPOCH, SIGMA);
    }

    function test_topUpEpoch_bnb_solvencyUsesNativeBalance() public {
        _createEpoch(address(0), ALICE_AMT); // BNB epoch, under-set to 100

        // unfunded -> solvency must use native balance and revert
        vm.prank(admin);
        vm.expectRevert("Insufficient funds");
        dist.topUpEpoch(EPOCH, SIGMA);

        // fund native, retry -> succeeds
        vm.deal(address(dist), SIGMA);
        vm.prank(admin);
        dist.topUpEpoch(EPOCH, SIGMA);
        assertEq(_epoch().totalAmount, SIGMA);
        assertEq(dist.totalUnclaimedAmount(address(0)), SIGMA);
    }
}
