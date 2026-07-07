// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title OFTConfig
 * @notice Per-chain LayerZero + Lista OFT deployment configuration, keyed by
 *         `block.chainid`. Used by the foundry deploy/config scripts so the same
 *         script works on mainnet and testnet selected purely by `--rpc-url`.
 *
 * Covered chains:
 *   - 56          BNB Chain mainnet      (ListaOFTAdapterV2, lock/unlock)
 *   - 1           Ethereum mainnet       (ListaOFTv2, mint/burn)
 *   - 97          BNB Chain testnet      (ListaOFTAdapterV2)
 *   - 11155111    Sepolia testnet        (ListaOFTv2)
 *
 * DVN policy: requiredDVNs must ALL verify; `optionalDVNThreshold` of the
 * optionalDVNs must verify. Mainnet requires Google plus 2-of-3 of LayerZero
 * Labs / Nethermind / USDT0. Testnet requires LayerZero Labs plus 1-of-1 Google.
 * A mandatory required DVN means every message must be signed by that operator,
 * so no all-optional subset can finalize a forged message on its own.
 */
library OFTConfig {
  struct NetworkConfig {
    bool isAdapter; // true: lock/unlock adapter; false: mint/burn OFT
    uint32 eid; // this chain's LayerZero endpoint id
    uint32 dstEid; // paired remote endpoint id
    address lzEndpoint;
    address sendLib; // SendUln302
    address receiveLib; // ReceiveUln302
    address executor;
    address token; // adapter only: existing canonical token
    string tokenName; // oft only
    string symbol; // oft only
    uint64 confirmations;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
    // transfer limit (single dst eid)
    uint256 maxDailyTransferAmount;
    uint256 singleTransferUpperLimit;
    uint256 singleTransferLowerLimit;
    uint256 dailyTransferAmountPerAddress;
    uint256 dailyTransferAttemptPerAddress;
  }

  function getConfig(uint256 chainId) internal pure returns (NetworkConfig memory cfg) {
    if (chainId == 56) return _bscMainnet();
    if (chainId == 1) return _ethMainnet();
    if (chainId == 97) return _bscTestnet();
    if (chainId == 11155111) return _sepolia();
    revert("OFTConfig: unsupported chainId");
  }

  // ----------------------------- mainnet -----------------------------

  function _bscMainnet() private pure returns (NetworkConfig memory cfg) {
    cfg.isAdapter = true;
    cfg.eid = 30102;
    cfg.dstEid = 30101;
    cfg.lzEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    cfg.sendLib = 0x9F8C645f2D0b2159767Bd6E0839DE4BE49e823DE;
    cfg.receiveLib = 0xB217266c3A98C8B2709Ee26836C98cf12f6cCEC1;
    cfg.executor = 0x3ebD570ed38B1b3b4BC886999fcF507e9D584859;
    cfg.token = 0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46; // canonical LISTA
    cfg.confirmations = 20;
    cfg.requiredDVNs = new address[](1);
    cfg.requiredDVNs[0] = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc; // Google (mandatory)
    cfg.optionalDVNs = new address[](3);
    cfg.optionalDVNs[0] = 0xfD6865c841c2d64565562fCc7e05e619A30615f0; // LayerZero Labs
    cfg.optionalDVNs[1] = 0x31F748a368a893Bdb5aBB67ec95F232507601A73; // Nethermind
    cfg.optionalDVNs[2] = 0x72F697797aC173F09eDa73Dd9C11a141376d2b57; // USDT0
    cfg.optionalDVNThreshold = 2;
    _defaultLimits(cfg);
  }

  function _ethMainnet() private pure returns (NetworkConfig memory cfg) {
    cfg.isAdapter = false;
    cfg.eid = 30101;
    cfg.dstEid = 30102;
    cfg.lzEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    cfg.sendLib = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    cfg.receiveLib = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
    cfg.executor = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
    cfg.tokenName = "Lista DAO";
    cfg.symbol = "LISTA";
    cfg.confirmations = 15;
    cfg.requiredDVNs = new address[](1);
    cfg.requiredDVNs[0] = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc; // Google (mandatory)
    cfg.optionalDVNs = new address[](3);
    cfg.optionalDVNs[0] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs
    cfg.optionalDVNs[1] = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5; // Nethermind
    cfg.optionalDVNs[2] = 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2; // USDT0
    cfg.optionalDVNThreshold = 2;
    _defaultLimits(cfg);
  }

  // ----------------------------- testnet -----------------------------

  function _bscTestnet() private pure returns (NetworkConfig memory cfg) {
    cfg.isAdapter = true;
    cfg.eid = 40102;
    cfg.dstEid = 40161;
    cfg.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    cfg.sendLib = 0x55f16c442907e86D764AFdc2a07C2de3BdAc8BB7;
    cfg.receiveLib = 0x188d4bbCeD671A7aA2b5055937F79510A32e9683;
    cfg.executor = 0x31894b190a8bAbd9A067Ce59fde0BfCFD2B18470;
    cfg.token = 0x90b94D605E069569Adf33C0e73E26a83637c94B1; // test LISTA
    cfg.confirmations = 5;
    cfg.requiredDVNs = new address[](1);
    cfg.requiredDVNs[0] = 0x0eE552262f7B562eFcED6DD4A7e2878AB897d405; // LayerZero Labs (mandatory)
    // Testnet: the Google DVN is not reliably attesting, so requiring it stalls the route.
    // Require only the always-on LayerZero Labs DVN (mainnet keeps the fuller policy).
    cfg.optionalDVNs = new address[](0);
    cfg.optionalDVNThreshold = 0;
    _defaultLimits(cfg);
  }

  function _sepolia() private pure returns (NetworkConfig memory cfg) {
    cfg.isAdapter = false;
    cfg.eid = 40161;
    cfg.dstEid = 40102;
    cfg.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    cfg.sendLib = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;
    cfg.receiveLib = 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851;
    cfg.executor = 0x718B92b5CB0a5552039B593faF724D182A881eDA;
    cfg.tokenName = "Lista DAO";
    cfg.symbol = "LISTA";
    cfg.confirmations = 5;
    cfg.requiredDVNs = new address[](1);
    cfg.requiredDVNs[0] = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193; // LayerZero Labs (mandatory)
    // Testnet: the Google DVN is not reliably attesting, so requiring it stalls the route.
    // Require only the always-on LayerZero Labs DVN (mainnet keeps the fuller policy).
    cfg.optionalDVNs = new address[](0);
    cfg.optionalDVNThreshold = 0;
    _defaultLimits(cfg);
  }

  function _defaultLimits(NetworkConfig memory cfg) private pure {
    // Sized against LISTA supply (totalSupply 1B, circulating ~415M, price ~$0.049):
    // the 8M/day global cap is <2% of circulating (~$392k notional) — a small max-loss
    // window before pause(), with the DVN set as the primary control and the limiter as a
    // backstop. Per-address cap is 5% of the global cap, so exhausting the shared daily
    // bucket requires 20 distinct addresses (M02). The 400k/day per-address cap also lets
    // operations bridge ~500k/week from a single wallet. Limits are applied post-deploy via
    // SetTransferLimit and remain adjustable without a redeploy.
    cfg.maxDailyTransferAmount = 8_000_000 ether;
    cfg.singleTransferUpperLimit = 200_000 ether;
    cfg.singleTransferLowerLimit = 0.1 ether;
    cfg.dailyTransferAmountPerAddress = 400_000 ether;
    cfg.dailyTransferAttemptPerAddress = 20;
  }
}
