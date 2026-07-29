pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { PreIPODistributor } from "../../../contracts/dao/PreIPODistributor.sol";

/**
 * Deploy a new PreIPODistributor implementation on BSC (impl only — no proxy, no upgrade call).
 *
 * Usage:
 *   forge script scripts/foundry/dao/deploy_PreIPO_impl.sol:PreIPODistributorImplDeploy \
 *     --rpc-url bsc --broadcast --verify -vvvv
 *
 * Requires env: DEPLOYER_BSC_PRIVATE_KEY / DEPLOYER_TESTNET_PRIVATE_KEY, BSCSCAN_API_KEY (--verify).
 */
contract PreIPODistributorImplDeploy is Script {
    uint256 constant BSC_MAINNET = 56;
    uint256 constant BSC_TESTNET = 97;

    function run() public {
        uint256 pk = _deployerKey();
        address deployer = vm.addr(pk);
        console.log("Chain id:", block.chainid);
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);
        PreIPODistributor impl = new PreIPODistributor();
        vm.stopBroadcast();

        console.log("PreIPODistributor implementation:", address(impl));
        console.log("--- upgrade calldata for the admin multisig (target = the proxy) ---");
        console.log("[first settlement upgrade] upgradeToAndCall(impl, initializeV2()):");
        console.logBytes(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                address(impl),
                abi.encodeCall(PreIPODistributor.initializeV2, ())
            )
        );
        console.log("[subsequent impl swap] upgradeTo(impl):");
        console.logBytes(abi.encodeWithSignature("upgradeTo(address)", address(impl)));
    }

    function _deployerKey() internal view returns (uint256) {
        if (block.chainid == BSC_MAINNET) {
            return vm.envUint("DEPLOYER_BSC_PRIVATE_KEY");
        } else if (block.chainid == BSC_TESTNET) {
            return vm.envUint("DEPLOYER_TESTNET_PRIVATE_KEY");
        } else {
            revert("Unsupported chain (expected BSC 56 or BSC testnet 97)");
        }
    }
}
