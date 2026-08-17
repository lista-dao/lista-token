// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Test } from "forge-std/Test.sol";
import {
    ClisBNBLaunchPoolDistributorImplDeploy
} from "../../scripts/foundry/dao/deploy_ClisBNBLaunchPoolDistributor_impl.sol";

// exposes the parameterized entry point so tests can skip the chain-id guard
contract DeployScriptHarness is ClisBNBLaunchPoolDistributorImplDeploy {
    function runWith(address knownMerkleVerifier) external returns (address, address) {
        return _run(knownMerkleVerifier);
    }
}

/**
 * Fork tests for the implementation deploy script (impl only — the script never
 * touches the proxy). Skipped unless BSC_TESTNET_RPC is set.
 */
contract DeployClisBNBLaunchPoolDistributorImplScriptTest is Test {
    address constant KNOWN_LIB = 0x816a48CA45226c27D33e8a08517e87a173399aE8;

    function _forkOrSkip() internal returns (bool) {
        string memory rpc = vm.envOr("BSC_TESTNET_RPC", string(""));
        if (bytes(rpc).length == 0) {
            emit log("BSC_TESTNET_RPC not set, skipping fork test");
            return false;
        }
        vm.createSelectFork(rpc);
        return true;
    }

    function test_deploysFreshLibraryWhenNoneKnown() public {
        if (!_forkOrSkip()) return;

        (address impl, address lib) = new DeployScriptHarness().runWith(address(0));

        assertGt(impl.code.length, 0, "implementation not deployed");
        assertGt(lib.code.length, 0, "library not deployed");
        assertTrue(lib != KNOWN_LIB, "should have deployed a fresh library");
        assertTrue(_codeContains(impl.code, lib), "impl not linked to the deployed library");
        // the new implementation must expose topUpEpoch (added in this upgrade)
        (bool ok, bytes memory ret) =
            impl.staticcall(abi.encodeWithSignature("topUpEpoch(uint64,uint256)", uint64(1), uint256(1)));
        assertFalse(ok);
        assertGt(ret.length, 0, "topUpEpoch missing on new implementation");
    }

    function test_reusesUnchangedLibrary() public {
        if (!_forkOrSkip()) return;

        // pretend the known library already matches the local build
        vm.etch(KNOWN_LIB, vm.getDeployedCode("MerkleVerifier.sol:MerkleVerifier"));

        (address impl, address lib) = new DeployScriptHarness().runWith(KNOWN_LIB);

        assertEq(lib, KNOWN_LIB, "library not reused");
        assertTrue(_codeContains(impl.code, KNOWN_LIB), "impl not linked to reused library");
    }

    function test_redeploysWhenKnownLibraryDiffers() public {
        if (!_forkOrSkip()) return;

        // the real on-chain copy was built by a different toolchain -> code differs
        (address impl, address lib) = new DeployScriptHarness().runWith(KNOWN_LIB);

        assertTrue(lib != KNOWN_LIB, "stale library must not be reused");
        assertGt(lib.code.length, 0);
        assertTrue(_codeContains(impl.code, lib), "impl not linked to the new library");
    }

    function _codeContains(bytes memory code, address needle) internal pure returns (bool) {
        bytes20 target = bytes20(needle);
        for (uint256 i = 0; i + 20 <= code.length; i++) {
            uint256 j = 0;
            while (j < 20 && code[i + j] == target[j]) {
                j++;
            }
            if (j == 20) return true;
        }
        return false;
    }
}
