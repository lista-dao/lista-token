// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../interfaces/IERC2612.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

contract ListaOFT is RateLimiter, OFT, IERC2612 {
  // --- ERC20 Data ---
  string internal constant _NAME = "Lista DAO";
  string internal constant _SYMBOL = "LISTA";

  // --- EIP 2612 Data ---
  bytes32 public constant PERMIT_TYPE_HASH =
  keccak256(
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
  );
  // version for EIP 712
  string public constant EIP712_VERSION = "1";
  // domain type hash for EIP 712
  bytes32 public constant EIP712_DOMAIN =
  keccak256(
    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
  );

  // domain separator for EIP 712
  bytes32 private DOMAIN_SEPARATOR;

  // @dev Mapping from (owner) => (next valid nonce) for EIP-712 signatures.
  mapping(address => uint256) private _nonces;

  // @dev skip rate limit check (eid) => (bool)
  mapping(uint32 => bool) public skipRateLimitCheck;

  // --- Functions ---
  constructor(
    RateLimitConfig[] memory _rateLimitConfigs,
    address _lzEndpoint,
    address _owner
  ) OFT(_NAME, _SYMBOL, _lzEndpoint, _owner) {
    bytes32 hashedName = keccak256(bytes(_NAME));
    bytes32 hashedVersion = keccak256(bytes(EIP712_VERSION));
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        EIP712_DOMAIN,
        hashedName,
        hashedVersion,
        block.chainid,
        address(this)
      )
    );
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

  // --- EIP 2612 functionality ---
  function permit(
    address owner,
    address spender,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external override {
    require(block.timestamp <= deadline, "ERC20Permit: expired deadline");
    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(
          abi.encode(
            PERMIT_TYPE_HASH,
            owner,
            spender,
            amount,
            _nonces[owner]++,
            deadline
          )
        )
      )
    );
    address recoveredAddress = ecrecover(digest, v, r, s);
    require(recoveredAddress == owner && owner != address(0), "ERC20Permit: invalid signature");
    _approve(owner, spender, amount);
  }

  /**
   * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
  function nonces(address owner) external view override returns (uint256) {
    return _nonces[owner];
  }

  /**
   * @dev Updates the domain separator with the latest chain id.
     */
  function updateDomainSeparator() external {
    bytes32 hashedName = keccak256(bytes(_NAME));
    bytes32 hashedVersion = keccak256(bytes(EIP712_VERSION));
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        EIP712_DOMAIN,
        hashedName,
        hashedVersion,
        block.chainid,
        address(this)
      )
    );
  }
}
