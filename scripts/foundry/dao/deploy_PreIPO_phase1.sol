pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { PreIPODistributor } from "../../../contracts/dao/PreIPODistributor.sol";

/**
 * Phase 1 (subscription) deploy to BSC mainnet.
 *
 * Grants each role to BOTH the deployer AND the real role holders, so the deployer can finish
 * setup afterwards (e.g. createSale, run separately once the whitelist root is ready). The
 * deployer's roles are removed later by the separate revoke script (revoke_PreIPO_deployer.sol).
 *
 * Real roles (launch table):
 *   - admin (DEFAULT_ADMIN_ROLE, timelock): 0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253
 *   - manager (MANAGER):                    0x8d388136d578dCD791D081c6042284CED6d9B0c6
 *   - bot (BOT, strategy):                  0x91fC4BA20685339781888eCA3E9E1c12d40F0e13
 *
 * Usage:
 *   forge script scripts/foundry/dao/deploy_PreIPO_phase1.sol:DeployPreIPOPhase1 \
 *     --rpc-url bsc --broadcast --verify -vvvv
 *
 * Requires env: DEPLOYER_BSC_PRIVATE_KEY, BSCSCAN_API_KEY (verify).
 */
contract DeployPreIPOPhase1 is Script {
    // ---- real role holders (BSC mainnet) ----
    address constant ADMIN = 0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253; // timelock
    address constant MANAGER = 0x8d388136d578dCD791D081c6042284CED6d9B0c6;
    address constant BOT = 0x91fC4BA20685339781888eCA3E9E1c12d40F0e13; // strategy

    function run() public {
        require(block.chainid == 56, "BSC mainnet only");
        uint256 pk = vm.envUint("DEPLOYER_BSC_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);
        console.log("Admin:", ADMIN);
        console.log("Manager:", MANAGER);
        console.log("Bot:", BOT);

        vm.startBroadcast(pk);

        // deploy impl + proxy; deployer holds all three roles initially (so it can grant + operate)
        PreIPODistributor impl = new PreIPODistributor();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PreIPODistributor.initialize, (deployer, deployer, deployer))
        );
        PreIPODistributor dist = PreIPODistributor(address(proxy));
        console.log("Implementation:", address(impl));
        console.log("PreIPODistributor proxy:", address(proxy));

        // grant the real role holders (deployer keeps its roles until the revoke script runs)
        dist.grantRole(dist.DEFAULT_ADMIN_ROLE(), ADMIN);
        dist.grantRole(dist.MANAGER(), MANAGER);
        dist.grantRole(dist.BOT(), BOT); // BOT role-admin is MANAGER; deployer holds MANAGER

        vm.stopBroadcast();
    }
}
