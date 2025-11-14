// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../../contracts/dao/VaultDistributor.sol";
import "../../contracts/mock/MockERC20.sol";

contract VaultDistributorTest is Test {

    address admin;
    address manager;
    address bot;
    address proxyAdminOwner;
    address operator;
    address user1 = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
    address user2 = 0x2d886570A0dA04885bfD6eb48eD8b8ff01A0eb7e;
    address user3 = 0xed857ac80A9cc7ca07a1C213e79683A1883df07B;
    address user4 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;

    VaultDistributor vaultDistributor;

    uint chainid;

    MockERC20 lpToken;
    MockERC20 rewardsToken;

    bytes32 public root;

    bytes32[] public leafs;

    bytes32[] public l2;

    function setUp() public {
        vm.createSelectFork("https://bsc-dataseed.binance.org");

        admin = makeAddr("admin");
        manager = makeAddr("manager");
        bot = makeAddr("bot");
        proxyAdminOwner = makeAddr("proxyAdminOwner");
        operator = makeAddr("operator");

        chainid = block.chainid;

        lpToken = new MockERC20(admin, "LP Token", "LPT");
        rewardsToken = new MockERC20(admin, "Rewards Token", "RWT");
        vm.startPrank(admin);
        lpToken.setMinter(admin);
        rewardsToken.setMinter(admin);
        vm.stopPrank();

        address[] memory addrss = new address[](4);
        addrss[0] = user1;
        addrss[1] = user2;
        addrss[2] = user3;
        addrss[3] = user4;

        // calc hash of leaf
        leafs.push(keccak256(abi.encode(chainid, 0, addrss[0], 123e18, 123e18)));
        leafs.push(keccak256(abi.encode(chainid, 0, addrss[1], 456e18, 456e18)));
        leafs.push(keccak256(abi.encode(chainid, 0, addrss[2], 789e18, 789e18)));
        leafs.push(keccak256(abi.encode(chainid, 0, addrss[3], 369e18, 369e18)));

        // calc hash of layer 2
        l2.push(keccak256(abi.encodePacked(leafs[0], leafs[1])));
        l2.push(keccak256(abi.encodePacked(leafs[2], leafs[3])));

        // calc root
        root = keccak256(abi.encodePacked(l2[0], l2[1]));

        VaultDistributor vaultDistributorImpl = new VaultDistributor();
        TransparentUpgradeableProxy vaultDistributorProxy = new TransparentUpgradeableProxy(
            address(vaultDistributorImpl),
            proxyAdminOwner,
            abi.encodeWithSelector(vaultDistributorImpl.initialize.selector, admin, manager, address(lpToken))
        );

        vaultDistributor = VaultDistributor(payable(address(vaultDistributorProxy)));

        vm.startPrank(admin);
        vaultDistributor.grantRole(vaultDistributor.OPERATOR(), operator);
        vm.stopPrank();



    }

    function test_setUp() public {
        assertEq(0, vaultDistributor.nextEpochId());
    }

    function test_verifyProof() public {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        console.logBytes32(leafs[0]);
        MerkleVerifier._verifyProof(keccak256(abi.encode(chainid, 0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, 123e18)), root, proof);
    }

    function test_setEpochMerkleRoot_ok() public {
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        VaultDistributor.Epoch[] memory before = vaultDistributor.getEpochs(epochIds);
        assertEq(0, before[0].startTime);

        vm.startPrank(operator);
        vaultDistributor.setEpochMerkleRoot(0, root, address(rewardsToken), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();

        VaultDistributor.Epoch[] memory actual = vaultDistributor.getEpochs(epochIds);
        assertEq(root, actual[0].merkleRoot);
        assertEq(address(rewardsToken), actual[0].token);
        assertEq(block.timestamp + 10, actual[0].startTime);
        assertEq(block.timestamp + 1000, actual[0].endTime);
        assertEq(1737e18, actual[0].totalAmount);
    }

    function test_setEpochMerkleRoot_bnb_ok() public {
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        VaultDistributor.Epoch[] memory before = vaultDistributor.getEpochs(epochIds);
        assertEq(0, before[0].startTime);

        vm.startPrank(operator);
        vaultDistributor.setEpochMerkleRoot(0, root, address(0), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();

        VaultDistributor.Epoch[] memory actual = vaultDistributor.getEpochs(epochIds);
        assertEq(root, actual[0].merkleRoot);
        assertEq(address(0), actual[0].token);
        assertEq(block.timestamp + 10, actual[0].startTime);
        assertEq(block.timestamp + 1000, actual[0].endTime);
        assertEq(1737e18, actual[0].totalAmount);
    }

    function test_setEpochMerkleRoot_invalid_epochId() public {
        vm.startPrank(operator);
        vm.expectRevert("Invalid epochId");
        vaultDistributor.setEpochMerkleRoot(1, root, address(rewardsToken), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();
    }

    function test_setEpochMerkleRoot_acl() public {
        vm.startPrank(bot);
        vm.expectRevert(abi.encodePacked(
            "AccessControl: account ",
            StringsUpgradeable.toHexString(bot),
            " is missing role ",
            StringsUpgradeable.toHexString(uint256(vaultDistributor.OPERATOR()), 32)
        ));
        vaultDistributor.setEpochMerkleRoot(0, root, address(rewardsToken), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();
    }

    function test_revokeEpoch_ok() public {
        test_setEpochMerkleRoot_ok();

        vm.startPrank(operator);
        vaultDistributor.revokeEpoch(0);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        VaultDistributor.Epoch[] memory actual = vaultDistributor.getEpochs(epochIds);

        assertEq(bytes32(0), actual[0].merkleRoot);
        assertEq(0, actual[0].startTime);
        assertEq(0, actual[0].endTime);
        assertEq(0, actual[0].totalAmount);
    }

    function test_operatorSetEpochMerkleRoot_ok() public {
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        VaultDistributor.Epoch[] memory before = vaultDistributor.getEpochs(epochIds);
        assertEq(0, before[0].startTime);

        vm.startPrank(operator);
        vaultDistributor.setEpochMerkleRoot(0, root, address(rewardsToken), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();

        VaultDistributor.Epoch[] memory actual = vaultDistributor.getEpochs(epochIds);
        assertEq(root, actual[0].merkleRoot);
        assertEq(address(rewardsToken), actual[0].token);
        assertEq(block.timestamp + 10, actual[0].startTime);
        assertEq(block.timestamp + 1000, actual[0].endTime);
        assertEq(1737e18, actual[0].totalAmount);
    }

    function test_operatorRevokeEpoch_ok() public {
        test_setEpochMerkleRoot_ok();

        vm.startPrank(operator);
        vaultDistributor.revokeEpoch(0);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        VaultDistributor.Epoch[] memory actual = vaultDistributor.getEpochs(epochIds);

        assertEq(bytes32(0), actual[0].merkleRoot);
        assertEq(0, actual[0].startTime);
        assertEq(0, actual[0].endTime);
        assertEq(0, actual[0].totalAmount);
    }

    function test_claim_ok() public {
        test_setEpochMerkleRoot_ok();

        deal(address(rewardsToken), address(vaultDistributor), 123e18);
        deal(address(lpToken), address(this), 123e18);
        assertEq(0, rewardsToken.balanceOf(user1));
        lpToken.approve(address(vaultDistributor), 123e18);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        skip(11);
        vaultDistributor.claim(0, user1, 123e18, 123e18, proof);

        assertEq(0, rewardsToken.balanceOf(address(vaultDistributor)));
        assertEq(123e18, rewardsToken.balanceOf(user1));

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        VaultDistributor.Epoch[] memory before = vaultDistributor.getEpochs(epochIds);
        assertEq(1737e18 - 123e18, before[0].unclaimedAmount);
    }

    function test_claim_invalid_amount() public {
        test_setEpochMerkleRoot_ok();

        deal(address(rewardsToken), address(vaultDistributor), 123e18);
        deal(address(lpToken), address(this), 123e18);
        assertEq(0, rewardsToken.balanceOf(user1));
        lpToken.approve(address(vaultDistributor), 123e18);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        skip(11);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        vaultDistributor.claim(0, user1, 12e18,12e18, proof);

        assertEq(123e18, rewardsToken.balanceOf(address(vaultDistributor)));
        assertEq(0, rewardsToken.balanceOf(user1));
    }

    function test_claim_duplicate() public {
        test_claim_ok();

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        vm.expectRevert("User already claimed");
        vaultDistributor.claim(0, user1, 123e18, 12e18,proof);
    }

}
