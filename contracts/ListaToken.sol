// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./interfaces/IERC2612.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
    @title Lista DAO Token
    @notice Given as an incentive for users of the protocol. Can be locked in `TokenLocker`
            to receive lock weight, which gives governance power within the Lista DAO.
 */
contract ListaToken is ERC20, IERC2612 {
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

    // --- Functions ---
    constructor(address owner) ERC20(_NAME, _SYMBOL) {
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

        // mint 1B tokens to the lista treasury account
        _mint(owner, 1_000_000_000 * 10 ** decimals());
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
