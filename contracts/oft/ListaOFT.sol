// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../interfaces/IERC2612.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "./TransferLimiter.sol";
import "./PausableAlt.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ListaOFT is TransferLimiter, OFT, IERC2612, PausableAlt {
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

  // --- Functions ---
  constructor(
    string memory _name,
    string memory _symbol,
    TransferLimit[] memory _transferLimitConfigs,
    address _lzEndpoint,
    address _owner
  ) OFT(_name, _symbol, _lzEndpoint, _owner) {
    bytes32 hashedName = keccak256(bytes(_name));
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
    _setTransferLimitConfigs(_transferLimitConfigs);
  }

  //  --- Transfer Limiter functionality ---

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
    uint32 /*_srcEid*/
  ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
    return super._credit(_to, _amountLD, 0);
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
    address recoveredAddress = ECDSA.recover(digest, v, r, s);
    require(recoveredAddress == owner, "ERC20Permit: invalid signature");
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
    bytes32 hashedName = keccak256(bytes(name()));
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
