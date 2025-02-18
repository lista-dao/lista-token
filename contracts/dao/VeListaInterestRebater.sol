// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { MerkleVerifier } from "../MerkleVerifier.sol";

/**
 * @title VeListaInterestRebater
 * @author Lista
 * @dev Rebate CDP borrow interests to veLista holders
 */
contract VeListaInterestRebater is Initializable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable {
  using SafeERC20 for IERC20;

  /// @dev current merkle root
  bytes32 public merkleRoot;

  /// @dev lisUSD address
  address public lisUSD;

  /// @dev userAddress => total claimed lisUSD amount
  mapping(address => uint256) public claimed;

  /// @dev next merkle root to be set
  bytes32 public pendingMerkleRoot;

  /// @dev last time pending merkle root was set
  uint256 public lastSetTime;

  /// @dev the waiting period before accepting the pending merkle root; 1 day by default
  uint256 public waitingPeriod;

  bytes32 public constant MANAGER = keccak256("MANAGER");
  bytes32 public constant BOT = keccak256("BOT");
  bytes32 public constant PAUSER = keccak256("PAUSER");

  event Claimed(address account, uint256 amount, uint256 totalAmount);
  event SetPendingMerkleRoot(bytes32 merkleRoot, uint256 lastSetTime);
  event AcceptMerkleRoot(bytes32 merkleRoot);
  event WaitingPeriodUpdated(uint256 waitingPeriod);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @param _admin Address of the admin
   * @param _manager Address of the manager
   * @param _bot Address of the bot
   * @param _pauser Address of the pauser
   * @param _lisUSD Address of the lisUSD token
   */
  function initialize(
    address _admin,
    address _manager,
    address _bot,
    address _pauser,
    address _lisUSD
  ) external initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_manager != address(0), "Invalid manager address");
    require(_bot != address(0), "Invalid bot address");
    require(_pauser != address(0), "Invalid pauser address");
    require(_lisUSD != address(0), "Invalid lisUSD address");

    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    lisUSD = _lisUSD;
    lastSetTime = type(uint256).max;
    waitingPeriod = 1 days;

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(BOT, _bot);
    _grantRole(PAUSER, _pauser);
  }

  /**
   * @dev Claim a rebate. Can be called by anyone as long as proof is valid.
   * @param _account Address of the veLista holder
   * @param _totalAmount total amount of lisUSD
   * @param _proof Merkle proof of the claim
   */
  function claim(address _account, uint256 _totalAmount, bytes32[] memory _proof) external whenNotPaused {
    require(merkleRoot != bytes32(0), "Invalid merkle root");
    require(_totalAmount > claimed[_account], "Invalid amount");

    bytes32 leaf = keccak256(abi.encode(block.chainid, _account, _totalAmount));
    MerkleVerifier._verifyProof(leaf, merkleRoot, _proof);

    uint256 amount = _totalAmount - claimed[_account];
    claimed[_account] = _totalAmount;

    IERC20(lisUSD).safeTransfer(_account, amount);

    emit Claimed(_account, amount, _totalAmount);
  }

  /**
   * @dev Set pending merkle root.
   * @param _merkleRoot Merkle root to be accepted
   */
  function setPendingMerkleRoot(bytes32 _merkleRoot) external onlyRole(BOT) whenNotPaused {
    require(_merkleRoot != bytes32(0) && _merkleRoot != pendingMerkleRoot, "Invalid new merkle root");

    pendingMerkleRoot = _merkleRoot;
    lastSetTime = block.timestamp;

    emit SetPendingMerkleRoot(_merkleRoot, lastSetTime);
  }

  /// @dev Accept the pending merkle root; pending merkle root can only be accepted after 1 day of setting
  function acceptMerkleRoot() external onlyRole(BOT) whenNotPaused {
    require(pendingMerkleRoot != bytes32(0) && pendingMerkleRoot != merkleRoot, "Invalid pending merkle root");
    require(block.timestamp >= lastSetTime + waitingPeriod, "Not ready to accept");

    merkleRoot = pendingMerkleRoot;
    pendingMerkleRoot = bytes32(0);
    lastSetTime = type(uint256).max;

    emit AcceptMerkleRoot(merkleRoot);
  }

  /// @dev Revoke the pending merkle root by Manager
  function revokePendingMerkleRoot() external onlyRole(MANAGER) whenNotPaused {
    require(pendingMerkleRoot != bytes32(0), "Pending merkle root is zero");

    pendingMerkleRoot = bytes32(0);
    lastSetTime = type(uint256).max;

    emit SetPendingMerkleRoot(bytes32(0), lastSetTime);
  }

  /**
   * @dev Change waiting period.
   * @param _waitingPeriod Waiting period to be set
   */
  function changeWaitingPeriod(uint256 _waitingPeriod) external onlyRole(MANAGER) whenNotPaused {
    require(_waitingPeriod > 0 && _waitingPeriod != waitingPeriod, "Invalid waiting period");
    waitingPeriod = _waitingPeriod;

    emit WaitingPeriodUpdated(_waitingPeriod);
  }

  /// @dev pause the contract
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /// @dev unpause the contract
  function unpause() external onlyRole(MANAGER) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
