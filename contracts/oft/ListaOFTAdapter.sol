// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import "./TransferLimiter.sol";
import "./PausableAlt.sol";

/**
  * @title Lista OFTAdapter Contract
  * @dev Lista OFTAdapter is a contract that adapts the ERC20 token to the OFT functionality.
    Users can transfer their token by lock their tokens into this contract,
    and receive the 1:1 backed token on the other chain.
  */
contract ListaOFTAdapter is TransferLimiter, OFTAdapter, PausableAlt {

  /**
    * @dev Constructor for the ListaAdapter contract
    * @param _token An ERC20 token address that has already been deployed and exists.
    * @param _lzEndpoint The address of the LayerZero endpoint
    * @param _owner The address of the owner of the contract
    */
  constructor (
    TransferLimit[] memory _transferLimitConfigs,
    address _token,
    address _lzEndpoint,
    address _owner
  ) OFTAdapter(_token, _lzEndpoint, _owner) {
    _setTransferLimitConfigs(_transferLimitConfigs);
  }

  // ------ Transfer Limiter functionality ------

  /**
   * @dev Sets the transfer limit configurations based on TransferLimit array. Only callable by the owner or the rate limiter.
   * @param _transferLimitConfigs An array of TransferLimit structures defining the transfer limits.
   */
  function setTransferLimitConfigs(
    TransferLimit[] calldata _transferLimitConfigs
  ) external onlyOwner {
    _setTransferLimitConfigs(_transferLimitConfigs);
  }

  /**
   * @dev Toggle skip transfer limit check
   * @param _skipTransferLimitCheck is check skip rate limit
   */
  function setSkipTransferLimitCheck(uint32 _eid, bool _skipTransferLimitCheck) external onlyOwner {
    _setSkipTransferLimitCheck(_eid, _skipTransferLimitCheck);
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
    _checkAndUpdateTransferLimit(_dstEid, _amountLD, _from);
    return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
  }

}
