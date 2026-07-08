// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { ListaOFTAdapterV2 } from "../../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title RevokeDeployerRole
 * @notice Handoff step 2 of 2 (final, irreversible). Strips the deployer of PAUSER,
 *         MANAGER and DEFAULT_ADMIN_ROLE. Run ONLY after
 *         GrantRolesAndTransferOwnership has handed authority to the Timelock + Safe
 *         and you have verified those holders are correct and controllable.
 *
 *         Preconditions assert the new admin + owner are already in place, so the
 *         deployer can never renounce the last admin and lock the contract out.
 *         DEFAULT_ADMIN_ROLE is renounced LAST (after the MANAGER/PAUSER revokes it
 *         authorizes). Run once per chain.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required, still holds DEFAULT_ADMIN_ROLE)
 *   OAPP     (required) local proxy address
 *   TIMELOCK (required) expected DEFAULT_ADMIN_ROLE holder + owner (precondition check)
 *
 * Usage:
 *   OAPP=0x.. TIMELOCK=0x.. forge script scripts/foundry/oft/v2/RevokeDeployerRole.s.sol \
 *     --rpc-url bsc --broadcast
 *
 * @dev ListaOFTAdapterV2 is a typed handle only; every selector used here
 *      (revokeRole, renounceRole) is identical on ListaOFTv2.
 */
contract RevokeDeployerRole is OFTScriptBase {
  function run() external {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(pk);
    address oapp = vm.envAddress("OAPP");
    address timelock = vm.envAddress("TIMELOCK");

    ListaOFTAdapterV2 oft = ListaOFTAdapterV2(oapp);
    bytes32 ADMIN = oft.DEFAULT_ADMIN_ROLE();
    bytes32 MANAGER = oft.MANAGER();
    bytes32 PAUSER = oft.PAUSER();

    // Preconditions: the handoff (grant step) must already be in place, so stripping
    // the deployer cannot leave the contract without an admin or owner.
    require(timelock != address(0) && timelock != deployer, "bad TIMELOCK");
    require(oft.hasRole(ADMIN, timelock), "timelock lacks ADMIN - run grant step first");
    require(oft.owner() == timelock, "owner not timelock - run grant step first");
    require(oft.hasRole(ADMIN, deployer), "deployer already stripped");

    console.log("OApp:", oapp);
    console.log("Deployer (stripped):", deployer);
    console.log("Timelock (retains ADMIN + owner):", timelock);

    vm.startBroadcast(pk);
    oft.revokeRole(PAUSER, deployer);
    oft.revokeRole(MANAGER, deployer);
    oft.renounceRole(ADMIN, deployer); // LAST
    vm.stopBroadcast();

    // final invariant: the deployer holds nothing.
    require(!oft.hasRole(ADMIN, deployer), "deployer still ADMIN");
    require(!oft.hasRole(MANAGER, deployer), "deployer still MANAGER");
    require(!oft.hasRole(PAUSER, deployer), "deployer still PAUSER");
    console.log("Deployer fully stripped.");
  }
}
