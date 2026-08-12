// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/dao/ClisBNBLaunchPoolDistributor.sol";
import "../../contracts/utils/BatchManagementUtils.sol";

contract ClisBNBLaunchPoolDistributorTest is Test {

    address admin = address(0x1A11AA);
    address manager = address(0x2A11AA);
    address bot = address(0x3A11AA);
    address defaultReceiver = 0x78Ab74C7EC3592B5298CB912f31bD8Fb80A57DC0;
    address proxyAdminOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;
    address oneInchRouter = 0x111111125421cA6dc452d289314280a0f8842A65;
    address operator;

    ClisBNBLaunchPoolDistributor cliBNBLaunchPoolDistributor;
    BatchManagementUtils batchManagementUtils;

    uint256 mainnet;

    uint chainid;

    IERC20 lista;

    bytes32 public root;

    bytes32[] public leafs;

    bytes32[] public l2;

    function setUp() public {
        operator = makeAddr("operator");
        mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");

        chainid = block.chainid;

        lista = IERC20(0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46);

        address[] memory addrss = new address[](4);
        addrss[0] = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
        addrss[1] = 0x2d886570A0dA04885bfD6eb48eD8b8ff01A0eb7e;
        addrss[2] = 0xed857ac80A9cc7ca07a1C213e79683A1883df07B;
        addrss[3] = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;

        // calc hash of leaf
        leafs.push(keccak256(abi.encode(chainid, 0, addrss[0], 123e18)));
        leafs.push(keccak256(abi.encode(chainid, 0, addrss[1], 456e18)));
        leafs.push(keccak256(abi.encode(chainid, 0, addrss[2], 789e18)));
        leafs.push(keccak256(abi.encode(chainid, 0, addrss[3], 369e18)));

        // calc hash of layer 2
        l2.push(keccak256(abi.encodePacked(leafs[0], leafs[1])));
        l2.push(keccak256(abi.encodePacked(leafs[2], leafs[3])));

        // calc root
        root = keccak256(abi.encodePacked(l2[0], l2[1]));
        console.logBytes32(root);

        ClisBNBLaunchPoolDistributor clisBNBLPDistributor = new ClisBNBLaunchPoolDistributor();
        TransparentUpgradeableProxy clisBNBLPDistributorProxy = new TransparentUpgradeableProxy(
            address(clisBNBLPDistributor),
            proxyAdminOwner,
            abi.encodeWithSignature(
                "initialize(address)",
                admin
            )
        );

        cliBNBLaunchPoolDistributor = ClisBNBLaunchPoolDistributor(payable(address(clisBNBLPDistributorProxy)));

        BatchManagementUtils batchUtilsImpl = new BatchManagementUtils();
        ERC1967Proxy batchUtilsProxy = new ERC1967Proxy(
            address(batchUtilsImpl),
            abi.encodeWithSelector(
                batchManagementUtils.initialize.selector,
                admin,
                manager
            )
        );
        batchManagementUtils = BatchManagementUtils(address(batchUtilsProxy));

        vm.startPrank(manager);
        batchManagementUtils.setDistributor(address(cliBNBLaunchPoolDistributor), true);
        vm.stopPrank();

        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.grantRole(cliBNBLaunchPoolDistributor.OPERATOR(), operator);
        cliBNBLaunchPoolDistributor.grantRole(cliBNBLaunchPoolDistributor.OPERATOR(), address(batchManagementUtils));
        vm.stopPrank();



    }

    function test_setUp() public {
        assertEq(0, cliBNBLaunchPoolDistributor.nextEpochId());
    }

    function test_verifyProof() public {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        address proofAddress = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
        MerkleVerifier._verifyProof(keccak256(abi.encode(chainid, 0, proofAddress, 123e18)), root, proof);
    }

    function test_setEpochMerkleRoot_ok() public {
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory before = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(0, before[0].startTime);

        vm.startPrank(operator);
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(0, root, address(lista), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();

        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(root, actual[0].merkleRoot);
        assertEq(address(lista), actual[0].token);
        assertEq(block.timestamp + 10, actual[0].startTime);
        assertEq(block.timestamp + 1000, actual[0].endTime);
        assertEq(1737e18, actual[0].totalAmount);
    }

    function test_setEpochMerkleRoot_bnb_ok() public {
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory before = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(0, before[0].startTime);

        vm.startPrank(operator);
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(0, root, address(0), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();

        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(root, actual[0].merkleRoot);
        assertEq(address(0), actual[0].token);
        assertEq(block.timestamp + 10, actual[0].startTime);
        assertEq(block.timestamp + 1000, actual[0].endTime);
        assertEq(1737e18, actual[0].totalAmount);
    }

    function test_setEpochMerkleRoot_invalid_epochId() public {
        vm.startPrank(operator);
        vm.expectRevert("Invalid epochId");
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(1, root, address(lista), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();
    }

    function test_setEpochMerkleRoot_acl() public {
        vm.startPrank(bot);
        vm.expectRevert("AccessControl: account 0x00000000000000000000000000000000003a11aa is missing role 0x523a704056dcd17bcf83bed8b68c59416dac1119be77755efe3bde0a64e46e0c");
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(0, root, address(lista), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();
    }

    function test_revokeEpoch_ok() public {
        test_setEpochMerkleRoot_ok();

        vm.startPrank(operator);
        cliBNBLaunchPoolDistributor.revokeEpoch(0);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);

        assertEq(bytes32(0), actual[0].merkleRoot);
        assertEq(0, actual[0].startTime);
        assertEq(0, actual[0].endTime);
        assertEq(0, actual[0].totalAmount);
    }

    function test_operatorSetEpochMerkleRoot_ok() public {
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory before = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(0, before[0].startTime);

        vm.startPrank(operator);
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(0, root, address(lista), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        vm.stopPrank();

        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(root, actual[0].merkleRoot);
        assertEq(address(lista), actual[0].token);
        assertEq(block.timestamp + 10, actual[0].startTime);
        assertEq(block.timestamp + 1000, actual[0].endTime);
        assertEq(1737e18, actual[0].totalAmount);
    }

    function test_operatorRevokeEpoch_ok() public {
        test_setEpochMerkleRoot_ok();

        vm.startPrank(operator);
        cliBNBLaunchPoolDistributor.revokeEpoch(0);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);

        assertEq(bytes32(0), actual[0].merkleRoot);
        assertEq(0, actual[0].startTime);
        assertEq(0, actual[0].endTime);
        assertEq(0, actual[0].totalAmount);
    }

    function test_claim_ok() public {
        test_setEpochMerkleRoot_ok();

        deal(address(lista), address(cliBNBLaunchPoolDistributor), 123e18);
        assertEq(0, lista.balanceOf(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2));

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        skip(11);
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, proof);

        assertEq(0, lista.balanceOf(address(cliBNBLaunchPoolDistributor)));
        assertEq(123e18, lista.balanceOf(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2));

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory before = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(1737e18 - 123e18, before[0].unclaimedAmount);
    }

    function test_claim_bnb_ok() public {
        test_setEpochMerkleRoot_bnb_ok();

        deal(address(cliBNBLaunchPoolDistributor), 123e18);
        deal(address(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2), 0);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        skip(11);
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, proof);

        assertEq(0, address(cliBNBLaunchPoolDistributor).balance);

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory before = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(1737e18 - 123e18, before[0].unclaimedAmount);
    }

    function test_claim_invalid_amount() public {
        test_setEpochMerkleRoot_ok();

        deal(address(lista), address(cliBNBLaunchPoolDistributor), 123e18);
        assertEq(0, lista.balanceOf(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2));

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        skip(11);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 12e18, proof);

        assertEq(123e18, lista.balanceOf(address(cliBNBLaunchPoolDistributor)));
        assertEq(0, lista.balanceOf(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2));
    }

    function test_claim_duplicate() public {
        test_claim_ok();

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        vm.expectRevert("User already claimed");
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, proof);
    }

    // epoch whose totalAmount(1000e18) is lower than the sum of the merkle tree(1737e18)
    function _setEpochWithInsufficientTotalAmount() private {
        vm.startPrank(operator);
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(0, root, address(lista), block.timestamp + 10, block.timestamp + 1000, 1000e18);
        vm.stopPrank();

        deal(address(lista), address(cliBNBLaunchPoolDistributor), 1737e18);
        skip(11);
    }

    function _proof(uint256 _index) private view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        if (_index == 0) {
            proof[0] = leafs[1];
            proof[1] = l2[1];
        } else if (_index == 1) {
            proof[0] = leafs[0];
            proof[1] = l2[1];
        } else if (_index == 2) {
            proof[0] = leafs[3];
            proof[1] = l2[0];
        } else {
            proof[0] = leafs[2];
            proof[1] = l2[0];
        }
        return proof;
    }

    function test_updateEpochTotalAmount_fix_insufficient_total_amount() public {
        _setEpochWithInsufficientTotalAmount();

        // first two users can claim, 1000 - 123 - 456 = 421 left
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, _proof(0));
        cliBNBLaunchPoolDistributor.claim(0, 0x2d886570A0dA04885bfD6eb48eD8b8ff01A0eb7e, 456e18, _proof(1));

        // the third user cannot claim 789 out of 421
        vm.expectRevert();
        cliBNBLaunchPoolDistributor.claim(0, 0xed857ac80A9cc7ca07a1C213e79683A1883df07B, 789e18, _proof(2));

        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1737e18);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(1737e18, actual[0].totalAmount);
        assertEq(1737e18 - 123e18 - 456e18, actual[0].unclaimedAmount);
        assertEq(1737e18 - 123e18 - 456e18, cliBNBLaunchPoolDistributor.totalUnclaimedAmount(address(lista)));

        // remaining users can claim now
        cliBNBLaunchPoolDistributor.claim(0, 0xed857ac80A9cc7ca07a1C213e79683A1883df07B, 789e18, _proof(2));
        cliBNBLaunchPoolDistributor.claim(0, 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990, 369e18, _proof(3));

        actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(0, actual[0].unclaimedAmount);
        assertEq(0, cliBNBLaunchPoolDistributor.totalUnclaimedAmount(address(lista)));
        assertEq(0, lista.balanceOf(address(cliBNBLaunchPoolDistributor)));
    }

    function test_updateEpochTotalAmount_decrease_ok() public {
        test_setEpochMerkleRoot_ok();
        deal(address(lista), address(cliBNBLaunchPoolDistributor), 1737e18);

        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1000e18);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(1000e18, actual[0].totalAmount);
        assertEq(1000e18, actual[0].unclaimedAmount);
        assertEq(1000e18, cliBNBLaunchPoolDistributor.totalUnclaimedAmount(address(lista)));
    }

    function test_updateEpochTotalAmount_emit_event() public {
        test_setEpochMerkleRoot_ok();
        deal(address(lista), address(cliBNBLaunchPoolDistributor), 2000e18);

        vm.expectEmit(true, true, true, true, address(cliBNBLaunchPoolDistributor));
        emit ClisBNBLaunchPoolDistributor.UpdateEpochTotalAmount(0, address(lista), 1737e18, 2000e18, 2000e18);

        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 2000e18);
        vm.stopPrank();
    }

    // totalUnclaimedAmount is shared by all epochs of the same token
    function test_updateEpochTotalAmount_multiple_epochs_same_token() public {
        vm.startPrank(operator);
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(0, root, address(lista), block.timestamp + 10, block.timestamp + 1000, 1737e18);
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(1, root, address(lista), block.timestamp + 10, block.timestamp + 1000, 1000e18);
        vm.stopPrank();
        assertEq(2737e18, cliBNBLaunchPoolDistributor.totalUnclaimedAmount(address(lista)));

        // balance only covers the current total of both epochs
        deal(address(lista), address(cliBNBLaunchPoolDistributor), 2737e18);
        vm.startPrank(admin);
        vm.expectRevert("Insufficient balance");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1800e18);
        vm.stopPrank();

        deal(address(lista), address(cliBNBLaunchPoolDistributor), 2800e18);
        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1800e18);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](2);
        epochIds[0] = 0;
        epochIds[1] = 1;
        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(1800e18, actual[0].totalAmount);
        assertEq(1800e18, actual[0].unclaimedAmount);
        // the other epoch of the same token is untouched
        assertEq(1000e18, actual[1].totalAmount);
        assertEq(1000e18, actual[1].unclaimedAmount);
        assertEq(2800e18, cliBNBLaunchPoolDistributor.totalUnclaimedAmount(address(lista)));
    }

    function test_updateEpochTotalAmount_collectUnclaimed_after_increase() public {
        _setEpochWithInsufficientTotalAmount();
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, _proof(0));

        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1737e18);
        vm.stopPrank();

        skip(1000);
        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.collectUnclaimed(0);
        vm.stopPrank();

        assertEq(1737e18 - 123e18, lista.balanceOf(admin));
        assertEq(0, lista.balanceOf(address(cliBNBLaunchPoolDistributor)));
        assertEq(0, cliBNBLaunchPoolDistributor.totalUnclaimedAmount(address(lista)));
    }

    // cut the total amount down to exactly what has been claimed
    function test_updateEpochTotalAmount_decrease_to_claimed_amount() public {
        _setEpochWithInsufficientTotalAmount();
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, _proof(0));

        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 123e18);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(123e18, actual[0].totalAmount);
        assertEq(0, actual[0].unclaimedAmount);
        assertEq(0, cliBNBLaunchPoolDistributor.totalUnclaimedAmount(address(lista)));
    }

    function test_updateEpochTotalAmount_decrease_below_claimed() public {
        _setEpochWithInsufficientTotalAmount();
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, _proof(0));

        vm.startPrank(admin);
        vm.expectRevert("Amount already claimed");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 100e18);
        vm.stopPrank();
    }

    function test_updateEpochTotalAmount_bnb_ok() public {
        test_setEpochMerkleRoot_bnb_ok();
        deal(address(cliBNBLaunchPoolDistributor), 2000e18);

        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 2000e18);
        vm.stopPrank();

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(2000e18, actual[0].totalAmount);
        assertEq(2000e18, actual[0].unclaimedAmount);
        assertEq(2000e18, cliBNBLaunchPoolDistributor.totalUnclaimedAmount(address(0)));
    }

    function test_updateEpochTotalAmount_insufficient_balance() public {
        test_setEpochMerkleRoot_ok();
        deal(address(lista), address(cliBNBLaunchPoolDistributor), 1737e18);

        vm.startPrank(admin);
        vm.expectRevert("Insufficient balance");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1737e18 + 1);
        vm.stopPrank();
    }

    function test_updateEpochTotalAmount_bnb_insufficient_balance() public {
        test_setEpochMerkleRoot_bnb_ok();
        deal(address(cliBNBLaunchPoolDistributor), 1737e18);

        vm.startPrank(admin);
        vm.expectRevert("Insufficient balance");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1737e18 + 1);
        vm.stopPrank();
    }

    function test_updateEpochTotalAmount_invalid_epochId() public {
        test_setEpochMerkleRoot_ok();

        vm.startPrank(admin);
        vm.expectRevert("Invalid epochId");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(1, 1737e18);
        vm.stopPrank();
    }

    function test_updateEpochTotalAmount_revoked_epoch() public {
        test_revokeEpoch_ok();

        vm.startPrank(admin);
        vm.expectRevert("Invalid epochId");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1737e18);
        vm.stopPrank();
    }

    function test_updateEpochTotalAmount_same_amount() public {
        test_setEpochMerkleRoot_ok();

        vm.startPrank(admin);
        vm.expectRevert("Same total amount");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 1737e18);
        vm.stopPrank();
    }

    function test_updateEpochTotalAmount_zero_amount() public {
        test_setEpochMerkleRoot_ok();

        vm.startPrank(admin);
        vm.expectRevert("Invalid total amount");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 0);
        vm.stopPrank();
    }

    function test_updateEpochTotalAmount_epoch_ended() public {
        test_setEpochMerkleRoot_ok();
        deal(address(lista), address(cliBNBLaunchPoolDistributor), 2000e18);
        skip(1001);

        vm.startPrank(admin);
        vm.expectRevert("Epoch already ended");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 2000e18);
        vm.stopPrank();
    }

    function test_updateEpochTotalAmount_acl() public {
        test_setEpochMerkleRoot_ok();
        deal(address(lista), address(cliBNBLaunchPoolDistributor), 2000e18);

        vm.startPrank(bot);
        vm.expectRevert("AccessControl: account 0x00000000000000000000000000000000003a11aa is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 2000e18);
        vm.stopPrank();

        // OPERATOR is not enough, only DEFAULT_ADMIN_ROLE can update
        vm.startPrank(operator);
        vm.expectRevert();
        cliBNBLaunchPoolDistributor.updateEpochTotalAmount(0, 2000e18);
        vm.stopPrank();
    }

    function test_batch_setEpochMerkleRoot_ok() public {
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 0;
        ClisBNBLaunchPoolDistributor.Epoch[] memory before = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(0, before[0].startTime);

        BatchManagementUtils.MerkleRootInfo[] memory infos = new BatchManagementUtils.MerkleRootInfo[](1);
        infos[0] = BatchManagementUtils.MerkleRootInfo({
            distributor: address(cliBNBLaunchPoolDistributor),
            epochId: 0,
            merkleRoot: root,
            token: address(lista),
            startTime: block.timestamp + 10,
            endTime: block.timestamp + 1000,
            totalAmount: 1737e18
        });

        vm.startPrank(operator);
        batchManagementUtils.batchSetEpochMerkleRoot(infos);
        vm.stopPrank();

        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(root, actual[0].merkleRoot);
        assertEq(address(lista), actual[0].token);
        assertEq(block.timestamp + 10, actual[0].startTime);
        assertEq(block.timestamp + 1000, actual[0].endTime);
        assertEq(1737e18, actual[0].totalAmount);
    }
}
