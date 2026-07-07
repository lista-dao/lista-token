// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { ListaOFTAdapterV2 } from "../../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title GrantRolesAndTransferOwnership
 * @notice Handoff step 1 of 2. Grants every role/authority to the target governance
 *         holders WITHOUT stripping the deployer:
 *           - Timelock -> DEFAULT_ADMIN_ROLE + Ownable owner
 *           - Safe     -> MANAGER + LayerZero endpoint delegate
 *           - Pauser   -> PAUSER
 *         Run this first, verify on-chain that the new holders are correct and
 *         actually controllable, THEN run RevokeDeployerRole to strip the deployer.
 *         Splitting the grant from the irreversible renounce leaves a safe window: if
 *         a target is wrong, the deployer still holds admin and can correct it.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required, must currently hold DEFAULT_ADMIN_ROLE + owner)
 *   OAPP     (required) local proxy address
 *   TIMELOCK (required) new DEFAULT_ADMIN_ROLE holder + Ownable owner (must be a contract)
 *   SAFE     (required) new MANAGER holder + LayerZero delegate (must be a contract)
 *   PAUSER   (required) new PAUSER holder
 *
 * Usage:
 *   OAPP=0x.. TIMELOCK=0x.. SAFE=0x.. PAUSER=0x.. \
 *     forge script scripts/foundry/oft/v2/GrantRolesAndTransferOwnership.s.sol \
 *     --rpc-url bsc --broadcast
 *
 * @dev ListaOFTAdapterV2 is a typed handle only; every selector used here
 *      (grantRole, setDelegate, transferOwnership) is identical on ListaOFTv2.
 */
contract GrantRolesAndTransferOwnership is OFTScriptBase {
  function run() external {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(pk);
    address oapp = vm.envAddress("OAPP");
    address timelock = vm.envAddress("TIMELOCK");
    address safe = vm.envAddress("SAFE");
    address pauser = vm.envAddress("PAUSER");

    require(timelock != address(0) && safe != address(0) && pauser != address(0), "zero target");
    // All targets must differ from the deployer: a role granted to the deployer here
    // would be stripped by RevokeDeployerRole, leaving that role holderless (e.g. no
    // PAUSER = no emergency pause path).
    require(timelock != deployer && safe != deployer && pauser != deployer, "target is deployer");
    // Guard against a mistyped or cross-chain address that has no code on THIS chain:
    // handing upgrade/config authority to an EOA-less, uncontrollable address bricks
    // governance. The admin/config authorities must be deployed contracts here.
    require(timelock.code.length > 0, "TIMELOCK has no code on this chain");
    require(safe.code.length > 0, "SAFE has no code on this chain");

    ListaOFTAdapterV2 oft = ListaOFTAdapterV2(oapp);
    bytes32 ADMIN = oft.DEFAULT_ADMIN_ROLE();
    bytes32 MANAGER = oft.MANAGER();
    bytes32 PAUSER = oft.PAUSER();

    require(oft.hasRole(ADMIN, deployer), "deployer lacks ADMIN");
    require(oft.owner() == deployer, "deployer is not owner");

    console.log("OApp:", oapp);
    console.log("Timelock (ADMIN + owner):", timelock);
    console.log("Safe (MANAGER + delegate):", safe);
    console.log("Pauser (PAUSER):", pauser);

    vm.startBroadcast(pk);
    oft.grantRole(ADMIN, timelock);
    oft.grantRole(MANAGER, safe);
    oft.grantRole(PAUSER, pauser);
    // setDelegate is onlyOwner -> must run while the deployer is still owner,
    // i.e. BEFORE transferOwnership below.
    oft.setDelegate(safe);
    oft.transferOwnership(timelock);
    vm.stopBroadcast();

    // verify the grants + ownership landed (reverts the broadcast otherwise).
    require(oft.hasRole(ADMIN, timelock), "timelock missing ADMIN");
    require(oft.hasRole(MANAGER, safe), "safe missing MANAGER");
    require(oft.hasRole(PAUSER, pauser), "pauser missing PAUSER");
    require(oft.owner() == timelock, "owner not timelock");
    // The deployer intentionally KEEPS ADMIN/MANAGER here; RevokeDeployerRole strips
    // it only after the operator has confirmed the new holders are controllable.
    console.log("Granted + ownership transferred. Deployer still ADMIN until RevokeDeployerRole.");
  }
}
