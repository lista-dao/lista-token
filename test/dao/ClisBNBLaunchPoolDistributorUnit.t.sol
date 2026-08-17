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
    uint64 constant EPOCH1 = 1; // sibling epoch on the same token, for multi-epoch coverage
    uint256 constant ALICE_AMT = 100e18;
    uint256 constant BOB_AMT = 200e18;
    uint256 constant SIGMA = 300e18; // Σ leaves = the correct total

    bytes32 leafAlice;
    bytes32 leafBob;
    bytes32 root;

    // epoch 1 leaves: same users/amounts, but the epochId is part of the leaf preimage
    bytes32 leafAlice1;
    bytes32 leafBob1;
    bytes32 root1;

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

        leafAlice1 = keccak256(abi.encode(block.chainid, EPOCH1, alice, ALICE_AMT));
        leafBob1 = keccak256(abi.encode(block.chainid, EPOCH1, bob, BOB_AMT));
        root1 = _hashPair(leafAlice1, leafBob1);
    }

    // ---- helpers ----

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _proof(bytes32 sibling) internal pure returns (bytes32[] memory p) {
        p = new bytes32[](1);
        p[0] = sibling;
    }

    /// @dev publish an epoch without activating it (still pre-start). Uses OPERATOR since
    ///      setEpochMerkleRoot is OPERATOR-gated (unchanged by this feature).
    function _publishEpoch(uint64 _epochId, bytes32 _root, address _token, uint256 _totalAmount) internal {
        vm.prank(operator);
        dist.setEpochMerkleRoot(_epochId, _root, _token, block.timestamp + 10, block.timestamp + 1000, _totalAmount);
    }

    /// @dev create epoch with a (possibly under-set) totalAmount and activate it.
    function _createEpoch(address _token, uint256 _totalAmount) internal {
        _publishEpoch(EPOCH, root, _token, _totalAmount);
        skip(11); // pass startTime so claims are active
    }

    /// @dev two epochs sharing one token, both inside their claim window. epochIds must be
    ///      published in order (setEpochMerkleRoot enforces _epochId == nextEpochId).
    function _createTwoEpochs(address _token, uint256 _total0, uint256 _total1) internal {
        _publishEpoch(EPOCH, root, _token, _total0);
        _publishEpoch(EPOCH1, root1, _token, _total1); // same block -> identical window
        skip(11);
    }

    function _epochAt(uint64 _epochId) internal view returns (ClisBNBLaunchPoolDistributor.Epoch memory) {
        uint64[] memory ids = new uint64[](1);
        ids[0] = _epochId;
        return dist.getEpochs(ids)[0];
    }

    function _epoch() internal view returns (ClisBNBLaunchPoolDistributor.Epoch memory) {
        return _epochAt(EPOCH);
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

    /// @dev [M02] the claim window is bounded on both edges. A pre-start epoch is fixed by
    ///      revoke + recreate, not by a top-up.
    function test_topUpEpoch_revertsWhenEpochNotStarted() public {
        _publishEpoch(EPOCH, root, address(token), ALICE_AMT); // published, startTime still ahead
        deal(address(token), address(dist), SIGMA); // funded, so only the window check can bite

        vm.prank(admin);
        vm.expectRevert("Epoch not started");
        dist.topUpEpoch(EPOCH, SIGMA);

        // accounting untouched
        assertEq(_epoch().totalAmount, ALICE_AMT);
        assertEq(dist.totalUnclaimedAmount(address(token)), ALICE_AMT);
    }

    /// @dev [M02] the pre-start guard also closes the route that manufactures an unearmarked
    ///      surplus: top up a not-yet-started epoch, then revokeEpoch — which adjusts accounting
    ///      but returns no tokens — leaving the added amount behind as balance above
    ///      totalUnclaimedAmount, which would then mask a later epoch's unfunded delta.
    function test_topUpEpoch_cannotManufactureSurplusViaPreStartTopUpThenRevoke() public {
        _publishEpoch(EPOCH, root, address(token), ALICE_AMT);
        deal(address(token), address(dist), SIGMA);

        vm.prank(admin);
        vm.expectRevert("Epoch not started");
        dist.topUpEpoch(EPOCH, SIGMA);

        // revoking the untouched epoch releases only what it was created with, so the
        // contract keeps no obligation-free surplus beyond what was over-funded up front
        vm.prank(operator);
        dist.revokeEpoch(EPOCH);
        assertEq(dist.totalUnclaimedAmount(address(token)), 0);
    }

    // ---- multi-epoch behaviour (two epochs sharing one token) ----

    /// @dev the top-up moves only the target epoch's caps; the sibling is untouched and the
    ///      token-wide counter is the sum of both.
    function test_topUpEpoch_multiEpoch_accountingIsPerEpoch() public {
        _createTwoEpochs(address(token), SIGMA, ALICE_AMT); // epoch0 correct, epoch1 under-set
        deal(address(token), address(dist), SIGMA + SIGMA); // fund both to their correct totals
        assertEq(dist.totalUnclaimedAmount(address(token)), SIGMA + ALICE_AMT);

        vm.prank(admin);
        dist.topUpEpoch(EPOCH1, SIGMA);

        ClisBNBLaunchPoolDistributor.Epoch memory e0 = _epochAt(EPOCH);
        assertEq(e0.totalAmount, SIGMA); // sibling untouched
        assertEq(e0.unclaimedAmount, SIGMA);

        ClisBNBLaunchPoolDistributor.Epoch memory e1 = _epochAt(EPOCH1);
        assertEq(e1.totalAmount, SIGMA);
        assertEq(e1.unclaimedAmount, SIGMA);

        assertEq(dist.totalUnclaimedAmount(address(token)), SIGMA + SIGMA);
    }

    /// @dev end-to-end remediation with a sibling epoch present. Note the tail claim reverts on
    ///      the per-epoch decrement here (the sibling's balance keeps the token-wide counter
    ///      solvent), which is the binding constraint the top-up lifts.
    function test_topUpEpoch_multiEpoch_unblocksTailClaimWithoutTouchingSibling() public {
        _createTwoEpochs(address(token), ALICE_AMT, SIGMA); // epoch0 under-set, epoch1 correct
        deal(address(token), address(dist), ALICE_AMT + SIGMA);

        dist.claim(EPOCH, alice, ALICE_AMT, _proof(leafBob)); // drains the under-set cap
        vm.expectRevert(stdError.arithmeticError);
        dist.claim(EPOCH, bob, BOB_AMT, _proof(leafAlice));

        deal(address(token), address(dist), SIGMA + BOB_AMT); // fund epoch0's missing delta
        vm.prank(admin);
        dist.topUpEpoch(EPOCH, SIGMA);

        dist.claim(EPOCH, bob, BOB_AMT, _proof(leafAlice));
        assertEq(token.balanceOf(bob), BOB_AMT);

        // epoch1 is entirely unaffected and still fully claimable
        ClisBNBLaunchPoolDistributor.Epoch memory e1 = _epochAt(EPOCH1);
        assertEq(e1.totalAmount, SIGMA);
        assertEq(e1.unclaimedAmount, SIGMA);
        assertEq(dist.totalUnclaimedAmount(address(token)), SIGMA);
        assertEq(token.balanceOf(address(dist)), SIGMA);

        dist.claim(EPOCH1, alice, ALICE_AMT, _proof(leafBob1));
        assertEq(token.balanceOf(alice), ALICE_AMT + ALICE_AMT);
    }

    /// @dev [M01] known limitation, accepted: the solvency check is token-wide, not per epoch.
    ///      A pre-existing surplus lets a top-up pass even though nobody funded this epoch's
    ///      delta — so a successful topUpEpoch is NOT proof that the epoch is individually
    ///      funded. Mitigated operationally by running one epoch per token at a time.
    function test_topUpEpoch_multiEpoch_siblingSurplusSatisfiesAggregateSolvency() public {
        _createTwoEpochs(address(token), SIGMA, ALICE_AMT); // owed: 300 + 100 = 400
        deal(address(token), address(dist), SIGMA + SIGMA); // 600 on hand: 200 unearmarked

        // raising epoch1 by 200 needs 600 token-wide, which the pre-existing surplus already
        // covers — no new funds were sent for this epoch
        vm.prank(admin);
        dist.topUpEpoch(EPOCH1, SIGMA);

        assertEq(_epochAt(EPOCH1).totalAmount, SIGMA);
        assertEq(dist.totalUnclaimedAmount(address(token)), SIGMA + SIGMA);
        assertEq(token.balanceOf(address(dist)), SIGMA + SIGMA); // balance never moved
    }

    /// @dev [M01] the converse: a sibling epoch's deficit blocks a top-up whose own delta was
    ///      funded, because the check is against the token-wide obligation.
    function test_topUpEpoch_multiEpoch_siblingDeficitBlocksFundedTopUp() public {
        _createTwoEpochs(address(token), SIGMA, ALICE_AMT); // owed: 300 + 100 = 400
        deal(address(token), address(dist), SIGMA + BOB_AMT); // 500: epoch0 short by 100...

        // ...even though epoch1's own 200 delta is sitting in the contract, raising it to 300
        // needs 600 token-wide and the sibling's shortfall makes the check fail
        vm.prank(admin);
        vm.expectRevert("Insufficient funds");
        dist.topUpEpoch(EPOCH1, SIGMA);
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
