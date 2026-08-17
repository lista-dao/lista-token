pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";

/**
 * Deploy a new ClisBNBLaunchPoolDistributor implementation on BSC mainnet (56)
 * or testnet (97). Impl only — no proxy interaction; per team process, the
 * storage layout is reviewed with a visual diff tool after this deployment and
 * the proxy upgrade is executed separately by the ProxyAdmin owner.
 *
 * MerkleVerifier (external library, linked via delegatecall) is resolved at run
 * time: if KNOWN_MERKLE_VERIFIER's on-chain code matches the local build it is
 * reused, otherwise a fresh copy is deployed. The implementation is linked
 * against it by patching the artifact's link placeholder, then deployed.
 *
 * Usage:
 *   forge script scripts/foundry/dao/deploy_ClisBNBLaunchPoolDistributor_impl.sol:ClisBNBLaunchPoolDistributorImplDeploy \
 *     --sig "run(uint256)" <chainId> \
 *     --rpc-url bsc-test --account deployer --broadcast -vvvv   (or --rpc-url bsc)
 *
 * Sender: supply via --account <keystore-name> (or --private-key / --sender).
 *
 * Env:
 *   KNOWN_MERKLE_VERIFIER (optional; last deployed MerkleVerifier for reuse,
 *                          unset/0x0 to always deploy a fresh copy)
 *
 * Requires foundry.toml: fs_permissions read access to ./out (artifact is read for linking).
 */
contract ClisBNBLaunchPoolDistributorImplDeploy is Script {
    uint256 constant BSC_MAINNET = 56;
    uint256 constant BSC_TESTNET = 97;

    string constant LIB_ARTIFACT = "MerkleVerifier.sol:MerkleVerifier";
    string constant LIB_FQN = "contracts/MerkleVerifier.sol:MerkleVerifier";
    string constant IMPL_ARTIFACT = "out/ClisBNBLaunchPoolDistributor.sol/ClisBNBLaunchPoolDistributor.json";

    /// @param chainId expected chain id, guards against broadcasting to the wrong network
    function run(uint256 chainId) public {
        require(block.chainid == chainId, "Chain id mismatch");
        require(
            block.chainid == BSC_MAINNET || block.chainid == BSC_TESTNET,
            "Unsupported chain (expected BSC 56 or BSC testnet 97)"
        );
        _run(vm.envOr("KNOWN_MERKLE_VERIFIER", address(0)));
    }

    function _run(address knownMerkleVerifier) internal returns (address newImpl, address lib) {
        console.log("Chain id:", block.chainid);

        lib = knownMerkleVerifier;
        bool reuse = lib != address(0) && lib.code.length > 0 &&
            _maskedCodeHash(lib.code) == _maskedCodeHash(vm.getDeployedCode(LIB_ARTIFACT));

        // no key argument: the sender comes from --account (or --private-key)
        vm.startBroadcast();

        if (reuse) {
            console.log("MerkleVerifier unchanged, reusing:", lib);
        } else {
            bytes memory libCreation = vm.getCode(LIB_ARTIFACT);
            assembly {
                lib := create(0, add(libCreation, 0x20), mload(libCreation))
            }
            require(lib != address(0) && lib.code.length > 0, "MerkleVerifier deployment failed");
            console.log("MerkleVerifier changed, deployed new copy:", lib);
        }

        bytes memory implCreation = _linkedImplCreationCode(lib);
        assembly {
            newImpl := create(0, add(implCreation, 0x20), mload(implCreation))
        }
        require(newImpl != address(0) && newImpl.code.length > 0, "Implementation deployment failed");

        vm.stopBroadcast();

        console.log("New implementation:", newImpl);
        console.log("Linked MerkleVerifier:", lib);
    }

    /// Implementation creation bytecode with the library link placeholder
    /// (`__$<keccak256(fqn)[:17]>$__`) replaced by the resolved library address.
    function _linkedImplCreationCode(address lib) internal view returns (bytes memory) {
        string memory creationHex = vm.parseJsonString(vm.readFile(IMPL_ARTIFACT), ".bytecode.object");
        bytes32 fqnHash = keccak256(bytes(LIB_FQN));
        bytes memory first17 = new bytes(17);
        for (uint256 i = 0; i < 17; i++) {
            first17[i] = fqnHash[i];
        }
        string memory placeholder = string.concat("__$", vm.replace(vm.toString(first17), "0x", ""), "$__");
        string memory addrHex = vm.replace(vm.toString(lib), "0x", "");
        return vm.parseBytes(vm.replace(creationHex, placeholder, addrHex));
    }

    /// A deployed library embeds its own address at bytes [1..21) of its runtime code
    /// (PUSH20 self-address guard against direct calls); zero that range on both sides
    /// before comparing, so on-chain code can be checked against the local artifact.
    function _maskedCodeHash(bytes memory code) internal pure returns (bytes32) {
        for (uint256 i = 1; i < 21 && i < code.length; i++) {
            code[i] = 0;
        }
        return keccak256(code);
    }
}
