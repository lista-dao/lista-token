// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console } from "forge-std/Script.sol";
import { TransferLimiterV2 } from "../../../../contracts/oft/v2/TransferLimiterV2.sol";
import { OFTConfig } from "./OFTConfig.sol";

/**
 * @title OFTScriptBase
 * @notice Shared helpers for the Lista OFT v2 foundry scripts: role resolution,
 *         transfer-limit construction and DVN sorting.
 */
abstract contract OFTScriptBase is Script {
  /// @dev Resolves ADMIN / MANAGER / PAUSER from the environment, each
  ///      defaulting to the deployer when unset.
  function _roles(address deployer) internal view returns (address admin, address manager, address pauser) {
    admin = vm.envOr("ADMIN", deployer);
    manager = vm.envOr("MANAGER", deployer);
    pauser = vm.envOr("PAUSER", deployer);
    // Loudly flag the unsafe case where a role env var is unset and silently collapses onto the
    // deployer EOA, concentrating admin/manager/pauser in one hot key. Warn only (no revert) so
    // single-key test/staging deploys still work; rotate to distinct multisigs post-deploy.
    if (admin == deployer || manager == deployer || pauser == deployer) {
      console.log(
        "WARNING: ADMIN/MANAGER/PAUSER resolved to the deployer EOA. Set these env vars to distinct keys and rotate roles to multisigs after deploy."
      );
    }
  }

  /// @dev Builds the single-destination TransferLimit array from a config.
  function _limits(
    OFTConfig.NetworkConfig memory cfg
  ) internal pure returns (TransferLimiterV2.TransferLimit[] memory limits) {
    limits = new TransferLimiterV2.TransferLimit[](1);
    limits[0] = TransferLimiterV2.TransferLimit({
      dstEid: cfg.dstEid,
      maxDailyTransferAmount: cfg.maxDailyTransferAmount,
      singleTransferUpperLimit: cfg.singleTransferUpperLimit,
      singleTransferLowerLimit: cfg.singleTransferLowerLimit,
      dailyTransferAmountPerAddress: cfg.dailyTransferAmountPerAddress,
      dailyTransferAttemptPerAddress: cfg.dailyTransferAttemptPerAddress
    });
  }

  /// @dev Ascending insertion sort (ULN requires sorted, unique DVN arrays).
  function _sorted(address[] memory arr) internal pure returns (address[] memory) {
    for (uint256 i = 1; i < arr.length; i++) {
      address key = arr[i];
      uint256 j = i;
      while (j > 0 && uint160(arr[j - 1]) > uint160(key)) {
        arr[j] = arr[j - 1];
        j--;
      }
      arr[j] = key;
    }
    return arr;
  }
}
