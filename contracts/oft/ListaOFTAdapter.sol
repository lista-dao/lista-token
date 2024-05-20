// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

/**
  * @title Lista OFTAdapter Contract
  * @dev Lista OFTAdapter is a contract that adapts the ListaToken to the OFT functionality.
    User's are can transfer their lista token by lock their tokens into this contract,
    and receive the 1:1 backed token on the other chain.
  */
contract ListaOFTAdapter is RateLimiter, OFTAdapter {

  // @dev skip rate limit check (eid) => (bool)
  mapping(uint32 => bool) public skipRateLimitCheck;

  /**
    * @dev Constructor for the ListaAdapter contract
    * @param _token An ERC20 token address that has already been deployed and exists.
    * @param _lzEndpoint The address of the LayerZero endpoint
    * @param _owner The address of the owner of the contract
    */
  constructor (
    RateLimitConfig[] memory _rateLimitConfigs,
    address _token,
    address _lzEndpoint,
    address _owner
  ) OFTAdapter(_token, _lzEndpoint, _owner) {
    _setRateLimits(_rateLimitConfigs);
  }

  //  --- RateLimiter functionality ---
  /**
    * @dev Sets the rate limits based on RateLimitConfig array. Only callable by the owner or the rate limiter.
    * @param _rateLimitConfigs An array of RateLimitConfig structures defining the rate limits.
    */
  function setRateLimits(
    RateLimitConfig[] calldata _rateLimitConfigs
  ) external onlyOwner {
    _setRateLimits(_rateLimitConfigs);
  }

  /**
    * @dev Toggle skip rate limit check
    * @param _skipRateLimitCheck is check skip rate limit
    */
  function setSkipRateLimitCheck(uint32 _eid, bool _skipRateLimitCheck) external onlyOwner {
    skipRateLimitCheck[_eid] = _skipRateLimitCheck;
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
  ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
    if (skipRateLimitCheck[_dstEid] != true) {
      _checkAndUpdateRateLimit(_dstEid, _amountLD);
    }
    return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
  }

}
