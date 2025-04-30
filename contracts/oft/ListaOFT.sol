// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "./TransferLimiter.sol";

contract ListaOFT is
OFTUpgradeable,
TransferLimiter,
ERC20PermitUpgradeable,
AccessControlUpgradeable,
PausableUpgradeable,
UUPSUpgradeable
{
  // --- Roles ---
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");

  constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
    _disableInitializers();
  }

  /**
   * @dev Initializes the ListaOFT
   * @param _admin The address of the admin.
   * @param _manager The address of the manager.
   * @param _pauser The address of the pauser.
   * @param _name The name of the token.
   * @param _symbol The symbol of the token.
   * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    string memory _name,
    string memory _symbol,
    address _delegate
  ) external initializer {
    require(
      _admin != address(0) &&
      _manager != address(0) &&
      _pauser != address(0) &&
      _delegate != address(0), "zero address provided"
    );
    __OFT_init(_name, _symbol, _delegate);
    __Ownable_init();
    __AccessControl_init();
    __Pausable_init();
    __ERC20Permit_init(_name);
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);
  }

  /* ============================
   Transfer Limiter functionality
  ============================ */
  /**
   * @dev Sets the transfer limit configurations based on TransferLimit array. Only callable by the owner or the rate limiter.
   * @param _transferLimitConfigs An array of TransferLimit structures defining the transfer limits.
   */
  function setTransferLimitConfigs(TransferLimit[] calldata _transferLimitConfigs) external onlyOwner {
    _setTransferLimitConfigs(_transferLimitConfigs);
  }

  /**
   * @dev Credits user with the token if the contract is not paused.
   * @param _to The address of the user to be credited.
   * @param _amountLD The amount of tokens to be transferred.
   * @return amountReceivedLD The actual amount of tokens received.
   */
  function _credit(
    address _to,
    uint256 _amountLD,
    uint32 _srcEid
  ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
    return super._credit(_to, _amountLD, _srcEid);
  }

  /**
   * @dev Checks and updates the rate limit before initiating a token transfer.
   * @param _amountLD The amount of tokens to be transferred.
   * @param _minAmountLD The minimum amount of tokens expected to be received.
   * @param _dstEid The destination endpoint identifier.
   * @return amountSentLD The actual amount of tokens sent.
   * @return amountReceivedLD The actual amount of tokens received.
   */
  function _debit(
    address _from,
    uint256 _amountLD,
    uint256 _minAmountLD,
    uint32 _dstEid
  ) internal virtual override whenNotPaused returns (uint256 amountSentLD, uint256 amountReceivedLD) {
    // remove dust before checking
    uint256 _amount = _removeDust(_amountLD);
    _checkAndUpdateTransferLimit(_dstEid, _amount, _from);
    return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
  }

  /* ============================
          Admin Functions
  ============================ */
  /**
   * @dev Flips the pause state
   */
  function togglePause() external onlyRole(MANAGER) {
    paused() ? _unpause() : _pause();
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /* ============================
         Internal Functions
  ============================ */
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
