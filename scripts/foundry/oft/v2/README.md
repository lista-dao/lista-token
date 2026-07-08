# Lista OFT v2 (upgradeable) — foundry deploy & config

Foundry (`forge script`) deployment + LayerZero wiring for the upgradeable Lista
OFT bridge. Network is selected by `--rpc-url` and resolved from `block.chainid`
in [`OFTConfig.sol`](./OFTConfig.sol) (BSC 56 / ETH 1 / BSC testnet 97 / Sepolia 11155111).

```
Native BSC LISTA --(lock)--> ListaOFTAdapterV2 --> LayerZero --> ListaOFTv2 (mint) @ ETH
ListaOFTv2 (burn) @ ETH      --> LayerZero --> ListaOFTAdapterV2 (unlock) --> BSC
```

## Files

| File | Purpose |
|------|---------|
| `OFTConfig.sol` | per-chain endpoint / send-lib / receive-lib / executor / token / eid / DVN / limits |
| `OFTScriptBase.sol` | role + transfer-limit + DVN-sort helpers |
| `DeployListaOFTAdapterV2.s.sol` | UUPS proxy deploy of the BSC lock/unlock adapter |
| `DeployListaOFTv2.s.sol` | UUPS proxy deploy of the remote mint/burn OFT |
| `SetPeer.s.sol` | wire trusted peer (MANAGER) |
| `SetTransferLimit.s.sol` | push transfer limits (MANAGER) |
| `SetDVNConfig.s.sol` | set send/receive libraries + ULN (DVN) + executor config (MANAGER/delegate) |
| `SetEnforcedOptions.s.sol` | set enforced LayerZero options / destination lzReceive gas floor (MANAGER) |
| `BridgeListaOFTV2.s.sol` | send LISTA through the local OFT adapter/OFT for test transfers |

## Environment

- `DEPLOYER_PRIVATE_KEY` — broadcaster (config scripts require MANAGER / delegate).
- `ADMIN`, `MANAGER`, `PAUSER` — role holders for deploy (default: deployer).
- `OAPP` — local proxy address (config scripts).
- `PEER` — remote proxy address (SetPeer).
- `DST_EID` — optional override of the paired remote eid (defaults to the config value).

## DVNs

Mainnet config **requires Google** plus an optional 2-of-3 of **LayerZero Labs,
Nethermind, USDT0**. Testnet config **requires LayerZero Labs** plus an optional
1-of-1 **Google**. A mandatory required DVN must sign every message, so no
optional-only subset can finalize a forged message on its own. Edit `OFTConfig.sol`
to change the policy; DVN arrays are sorted before encoding, so keep each list free
of duplicate addresses (the ULN rejects a non-unique array).

## Commands

Wire `setPeer` LAST, and only after libraries + DVNs are configured — see the
launch checklist below for why order matters.

```bash
# 1. deploy (per chain) — deploy PAUSED; unpause only after the launch checklist passes
forge script scripts/foundry/oft/v2/DeployListaOFTAdapterV2.s.sol --rpc-url bsc      --broadcast --verify --via-ir --skip Buyback.sol --skip ListaAutoBuyback.sol
forge script scripts/foundry/oft/v2/DeployListaOFTv2.s.sol         --rpc-url ethereum --broadcast --verify --via-ir --skip Buyback.sol --skip ListaAutoBuyback.sol

# 2. DVN / send / receive library config (MANAGER/delegate) — BEFORE wiring peers
OAPP=0x.. forge script scripts/foundry/oft/v2/SetDVNConfig.s.sol --rpc-url bsc --broadcast

# 3. (re)push transfer limits (MANAGER)
OAPP=0x.. forge script scripts/foundry/oft/v2/SetTransferLimit.s.sol --rpc-url bsc --broadcast

# 4. set enforced options / destination lzReceive gas floor (MANAGER)
OAPP=0x.. forge script scripts/foundry/oft/v2/SetEnforcedOptions.s.sol --rpc-url bsc --broadcast

# 5. wire peers (DEFAULT_ADMIN_ROLE) — LAST config step; this makes the route live.
#    OAPP = local proxy, PEER = remote proxy
OAPP=0x.. PEER=0x.. forge script scripts/foundry/oft/v2/SetPeer.s.sol --rpc-url bsc --broadcast

# 6. test transfer
OFT=0x.. DST_EID=40161 AMOUNT=1000000000000000000 forge script scripts/foundry/oft/v2/BridgeListaOFTV2.s.sol --rpc-url bsc-test --broadcast
OFT=0x.. DST_EID=40102 AMOUNT=1000000000000000000 forge script scripts/foundry/oft/v2/BridgeListaOFTV2.s.sol --rpc-url sepolia --broadcast
```

## Launch checklist

Cross-chain wiring is not atomic and step order matters:

- Run `SetDVNConfig` **before** `SetPeer`. `setPeer` makes a route live; if it runs
  while the endpoint still resolves to LayerZero's default library/DVN, messages in
  that window are verified under security settings the protocol did not choose.
- Deploy the OFT and adapter **paused** and unpause only after confirming, on **both
  chains and both directions**, that libraries, DVNs, enforced options, transfer
  limits, and peers are all set as intended.
- Do not announce or use the bridge until both directions are fully wired on both
  chains. A send from an unconfigured side reverts locally at `_getPeerOrRevert`
  before any packet is emitted, so no funds leave the sender. A packet arriving at
  an unconfigured receiving side reverts inside `lzReceive` and can be retried at
  the endpoint once the peer is set.

> `ethereum` / `sepolia` need an rpc alias in `foundry.toml` or pass the URL directly
> (`--rpc-url "$ETHEREUM_RPC"`). `bsc` / `bsc-test` aliases already exist.

## Tests

Contract behaviour + end-to-end bridge + BSC-fork simulation live in
`test/oft/v2/` (`forge test --match-path "test/oft/v2/*.t.sol"`).
