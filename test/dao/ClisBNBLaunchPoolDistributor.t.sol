// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/dao/ClisBNBLaunchPoolDistributor.sol";

contract ClisBNBLaunchPoolDistributorTest is Test {

    address admin = address(0x1A11AA);
    address manager = address(0x2A11AA);
    address bot = address(0x3A11AA);
    address defaultReceiver = 0x78Ab74C7EC3592B5298CB912f31bD8Fb80A57DC0;
    address proxyAdminOwner = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;
    address oneInchRouter = 0x111111125421cA6dc452d289314280a0f8842A65;

    ClisBNBLaunchPoolDistributor cliBNBLaunchPoolDistributor;

    uint256 mainnet;

    uint chainid;

    IERC20 lista;

    bytes32 public root;

    bytes32[] public leafs;

    bytes32[] public l2;

    function setUp() public {
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
                "initialize(address,address,address)",
                admin, bot, address(lista)
            )
        );

        cliBNBLaunchPoolDistributor = ClisBNBLaunchPoolDistributor(address(clisBNBLPDistributorProxy));
    }

    function test_setUp() public {
        assertEq(address(lista), cliBNBLaunchPoolDistributor.token());
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

        vm.startPrank(admin);
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(0, root, block.timestamp, block.timestamp + 100, 1737e18);
        vm.stopPrank();

        ClisBNBLaunchPoolDistributor.Epoch[] memory actual = cliBNBLaunchPoolDistributor.getEpochs(epochIds);
        assertEq(root, actual[0].merkleRoot);
        assertEq(block.timestamp, actual[0].startTime);
        assertEq(block.timestamp + 100, actual[0].endTime);
        assertEq(1737e18, actual[0].totalAmount);
    }

    function test_setEpochMerkleRoot_invalid_epochId() public {
        vm.startPrank(admin);
        vm.expectRevert("Invalid epochId");
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(1, root, block.timestamp, block.timestamp + 100, 1737e18);
        vm.stopPrank();
    }

    function test_setEpochMerkleRoot_acl() public {
        vm.startPrank(bot);
        vm.expectRevert("AccessControl: account 0x00000000000000000000000000000000003a11aa is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        cliBNBLaunchPoolDistributor.setEpochMerkleRoot(0, root, block.timestamp, block.timestamp + 100, 1737e18);
        vm.stopPrank();
    }

    function test_revokeEpoch_ok() public {
        test_setEpochMerkleRoot_ok();

        vm.startPrank(admin);
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

        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 123e18, proof);

        assertEq(0, lista.balanceOf(address(cliBNBLaunchPoolDistributor)));
        assertEq(123e18, lista.balanceOf(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2));
    }

    function test_claim_invalid_amount() public {
        test_setEpochMerkleRoot_ok();

        deal(address(lista), address(cliBNBLaunchPoolDistributor), 123e18);

        assertEq(0, lista.balanceOf(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2));

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafs[1];
        proof[1] = l2[1];

        vm.expectRevert(0x09bde339);
        cliBNBLaunchPoolDistributor.claim(0, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 12e18, proof);

        assertEq(123e18, lista.balanceOf(address(cliBNBLaunchPoolDistributor)));
        assertEq(0, lista.balanceOf(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2));
    }
}
