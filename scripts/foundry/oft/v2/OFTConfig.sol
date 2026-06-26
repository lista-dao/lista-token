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
 * optionalDVNs must verify. Mainnet uses LayerZero Labs + Nethermind + Google +
 * USDT0 as optional DVNs with threshold 3 (3-of-4). Testnet uses Google +
 * LayerZero Labs as optional DVNs with threshold 1 (1-of-2).
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
    cfg.requiredDVNs = new address[](0);
    cfg.optionalDVNs = new address[](4);
    cfg.optionalDVNs[0] = 0xfD6865c841c2d64565562fCc7e05e619A30615f0; // LayerZero Labs
    cfg.optionalDVNs[1] = 0x31F748a368a893Bdb5aBB67ec95F232507601A73; // Nethermind
    cfg.optionalDVNs[2] = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc; // Google
    cfg.optionalDVNs[3] = 0x72F697797aC173F09eDa73Dd9C11a141376d2b57; // USDT0
    cfg.optionalDVNThreshold = 3;
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
    cfg.tokenName = "Lista DAO Token";
    cfg.symbol = "LISTA";
    cfg.confirmations = 15;
    cfg.requiredDVNs = new address[](0);
    cfg.optionalDVNs = new address[](4);
    cfg.optionalDVNs[0] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs
    cfg.optionalDVNs[1] = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5; // Nethermind
    cfg.optionalDVNs[2] = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc; // Google
    cfg.optionalDVNs[3] = 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2; // USDT0
    cfg.optionalDVNThreshold = 3;
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
    cfg.requiredDVNs = new address[](0);
    cfg.optionalDVNs = new address[](2);
    cfg.optionalDVNs[0] = 0x6f99eA3Fc9206E2779249E15512D7248dAb0B52e; // Google
    cfg.optionalDVNs[1] = 0x0eE552262f7B562eFcED6DD4A7e2878AB897d405; // LayerZero Labs
    cfg.optionalDVNThreshold = 1;
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
    cfg.tokenName = "Lista DAO Token";
    cfg.symbol = "LISTA";
    cfg.confirmations = 5;
    cfg.requiredDVNs = new address[](0);
    cfg.optionalDVNs = new address[](2);
    cfg.optionalDVNs[0] = 0x4F675c48FaD936cb4c3cA07d7cBF421CeeAE0C75; // Google
    cfg.optionalDVNs[1] = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193; // LayerZero Labs
    cfg.optionalDVNThreshold = 1;
    _defaultLimits(cfg);
  }

  function _defaultLimits(NetworkConfig memory cfg) private pure {
    cfg.maxDailyTransferAmount = 1_000_000 ether;
    cfg.singleTransferUpperLimit = 100_000 ether;
    cfg.singleTransferLowerLimit = 0.1 ether;
    cfg.dailyTransferAmountPerAddress = 200_000 ether;
    cfg.dailyTransferAttemptPerAddress = 100;
  }
}
