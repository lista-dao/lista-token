// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OFTAdapterUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import { EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { TransferLimiterV2 } from "./TransferLimiterV2.sol";

/**
 * @title ListaOFTAdapterV2
 * @notice Upgradeable LayerZero V2 OFT Adapter for the canonical Lista (LISTA)
 *         ERC20 token that lives natively on BNB Chain.
 *
 * @dev Bridging model:
 *        Native BSC LISTA --(lock)--> ListaOFTAdapterV2 --> LayerZero --> ListaOFTv2 (mint) @ ETH
 *      and the reverse on the way back (burn @ ETH -> unlock @ BSC).
 *
 *      This is a *lockbox* adapter: the canonical supply is escrowed inside this
 *      contract and a 1:1 backed representation is minted on remote chains. Per
 *      LayerZero rules ONLY ONE OFT Adapter may exist for a given token mesh.
 *
 *      Access control:
 *        - DEFAULT_ADMIN_ROLE : upgrade authority + role administration.
 *        - MANAGER       : LayerZero OApp configuration (setPeer, enforced
 *                               options, msg inspector, precrime), transfer
 *                               limiter configuration and unpause().
 *        - PAUSER        : pause() the bridge in an emergency.
 *
 *      Upgradeability:
 *        - UUPS; only DEFAULT_ADMIN_ROLE may authorize an implementation upgrade.
 *        - `token` and `lzEndpoint` are immutables baked into the implementation
 *          bytecode by the LayerZero base contracts, hence supplied to the
 *          constructor and reused across upgrades.
 */
contract ListaOFTAdapterV2 is
  OFTAdapterUpgradeable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  TransferLimiterV2
{
  // @notice can pause the bridge in an emergency
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // @notice can configure the OApp + transfer limiter and unpause the bridge
  bytes32 public constant MANAGER = keccak256("MANAGER");

  /**
   * @param _token The canonical LISTA ERC20 token on BNB Chain.
   * @param _lzEndpoint The LayerZero V2 endpoint on BNB Chain.
   * @dev Disables initializers on the implementation so it can only be used
   *      behind a proxy.
   */
  /// @custom:oz-upgrades-unsafe-allow constructor state-variable-immutable
  constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
    _disableInitializers();
  }

  /**
   * @notice Initializes the proxy.
   * @param _admin The DEFAULT_ADMIN_ROLE holder (upgrade + role admin). Also set
   *               as the Ownable owner to satisfy the few non-virtual LayerZero
   *               owner-gated hooks.
   * @param _manager The MANAGER holder and LayerZero endpoint delegate.
   * @param _pauser The PAUSER holder.
   * @param _transferLimitConfigs Initial transfer limit configurations.
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    TransferLimit[] memory _transferLimitConfigs
  ) external initializer {
    require(_admin != address(0), "admin cannot be zero address");
    require(_manager != address(0), "manager cannot be zero address");
    require(_pauser != address(0), "pauser cannot be zero address");

    // sets the LayerZero endpoint delegate to the manager
    __OFTAdapter_init(_manager);
    __Ownable_init();
    __AccessControl_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    // owner is used only by the non-virtual LayerZero owner hooks (eg. setDelegate)
    _transferOwnership(_admin);

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);

    _setTransferLimitConfigs(_transferLimitConfigs);
  }

  // --------------------------------------------------------------------------
  // Transfer Limiter
  // --------------------------------------------------------------------------

  /**
   * @notice Sets the transfer limit configurations.
   * @param _transferLimitConfigs An array of TransferLimit structures.
   */
  function setTransferLimitConfigs(
    TransferLimit[] calldata _transferLimitConfigs
  ) external onlyRole(MANAGER) {
    _setTransferLimitConfigs(_transferLimitConfigs);
  }

  // --------------------------------------------------------------------------
  // Pause control
  // --------------------------------------------------------------------------

  /// @notice Pause the bridge. Callable by PAUSER.
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /// @notice Unpause the bridge. Callable by MANAGER.
  function unpause() external onlyRole(MANAGER) {
    _unpause();
  }

  // --------------------------------------------------------------------------
  // OFT debit / credit hooks (lock / unlock with limiter + pause guard)
  // --------------------------------------------------------------------------

  /**
   * @dev Locks tokens on the source (this) chain when sending cross-chain.
   *      Enforces the transfer limiter and the pause guard before locking.
   */
  function _debit(
    address _from,
    uint256 _amountLD,
    uint256 _minAmountLD,
    uint32 _dstEid
  ) internal virtual override whenNotPaused returns (uint256 amountSentLD, uint256 amountReceivedLD) {
    // remove dust before checking, mirroring the value that is actually bridged
    uint256 _amount = _removeDust(_amountLD);
    _checkAndUpdateTransferLimit(_dstEid, _amount, _from);
    return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
  }

  /**
   * @dev Unlocks tokens to the recipient when receiving cross-chain.
   *      Blocked while the contract is paused.
   */
  function _credit(
    address _to,
    uint256 _amountLD,
    uint32 _srcEid
  ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
    return super._credit(_to, _amountLD, _srcEid);
  }

  // --------------------------------------------------------------------------
  // LayerZero OApp configuration — restricted to MANAGER
  // --------------------------------------------------------------------------

  /// @notice Sets the trusted peer for a destination endpoint. Restricted to MANAGER.
  function setPeer(uint32 _eid, bytes32 _peer) public override onlyRole(MANAGER) {
    _getOAppCoreStorage().peers[_eid] = _peer;
    emit PeerSet(_eid, _peer);
  }

  /// @notice Sets enforced LayerZero options. Restricted to MANAGER.
  function setEnforcedOptions(
    EnforcedOptionParam[] calldata _enforcedOptions
  ) public override onlyRole(MANAGER) {
    OAppOptionsType3Storage storage $ = _getOAppOptionsType3Storage();
    for (uint256 i = 0; i < _enforcedOptions.length; i++) {
      _assertOptionsType3(_enforcedOptions[i].options);
      $.enforcedOptions[_enforcedOptions[i].eid][_enforcedOptions[i].msgType] = _enforcedOptions[i].options;
    }
    emit EnforcedOptionSet(_enforcedOptions);
  }

  /// @notice Sets the message inspector. Restricted to MANAGER.
  function setMsgInspector(address _msgInspector) public override onlyRole(MANAGER) {
    _getOFTCoreStorage().msgInspector = _msgInspector;
    emit MsgInspectorSet(_msgInspector);
  }

  /// @notice Sets the preCrime contract. Restricted to MANAGER.
  function setPreCrime(address _preCrime) public override onlyRole(MANAGER) {
    _getOAppPreCrimeSimulatorStorage().preCrime = _preCrime;
    emit PreCrimeSet(_preCrime);
  }

  // --------------------------------------------------------------------------
  // Upgrade authorization
  // --------------------------------------------------------------------------

  /// @dev Only DEFAULT_ADMIN_ROLE may upgrade the implementation.
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  uint256[50] private __gap;
}
