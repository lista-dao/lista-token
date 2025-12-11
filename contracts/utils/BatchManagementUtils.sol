// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { IClisBNBLaunchPoolDistributor } from "../interfaces/IClisBNBLaunchPoolDistributor.sol";

contract BatchManagementUtils is AccessControlEnumerableUpgradeable, UUPSUpgradeable {
  struct MerkleRootInfo {
    address distributor;
    uint64 epochId;
    bytes32 merkleRoot;
    address token;
    uint256 startTime;
    uint256 endTime;
    uint256 totalAmount;
  }

  mapping(address => bool) public distributors;

  bytes32 public constant MANAGER = keccak256("MANAGER");
  bytes32 public constant OPERATOR = keccak256("OPERATOR");

  event SetDistributor(address indexed distributor, bool status);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /** @dev Initializer function to set up roles and initial state.
   * @param admin The address to be granted the DEFAULT_ADMIN_ROLE.
   * @param manager The address to be granted the MANAGER role.
   *
   * Requirements:
   * - `admin` must not be the zero address.
   * - `manager` must not be the zero address.
   */
  function initialize(address admin, address manager) public initializer {
    require(admin != address(0), "admin is zero address");
    require(manager != address(0), "manager is zero address");
    __AccessControlEnumerable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(MANAGER, manager);
  }

  /**
   * @dev Set market fee for multiple markets in a single transaction.
    * @param infos The array of MerkleRootInfo structs.
    * Requirements:
    * - Caller must have the OPERATOR role for the specified `distributor` contract
    * - `infos` array must be non-empty.
    * - Each distributor in `infos` must be whitelisted.
   */
  function batchSetEpochMerkleRoot(MerkleRootInfo[] memory infos) external {
    require(infos.length > 0, "No MerkleRootInfo provided");

    for (uint256 i = 0; i < infos.length; i++) {
      _setEpochMerkleRoot(infos[i]);
    }
  }

  function _setEpochMerkleRoot(MerkleRootInfo memory info) internal {
    require(distributors[info.distributor], "Distributor not valid");
    require(IAccessControl(info.distributor).hasRole(OPERATOR, msg.sender), "Not operator of distributor");

    IClisBNBLaunchPoolDistributor distributor = IClisBNBLaunchPoolDistributor(info.distributor);
    distributor.setEpochMerkleRoot(
      info.epochId,
      info.merkleRoot,
      info.token,
      info.startTime,
      info.endTime,
      info.totalAmount
    );
  }

  function setDistributor(address distributor, bool status) external onlyRole(MANAGER) {
    require(distributor != address(0), "distributor is zero address");
    require(distributors[distributor] != status, "status already set");
    distributors[distributor] = status;
    emit SetDistributor(distributor, status);
  }


  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
