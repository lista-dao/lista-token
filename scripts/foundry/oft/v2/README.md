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

## Environment

- `DEPLOYER_PRIVATE_KEY` — broadcaster (config scripts require MANAGER / delegate).
- `ADMIN`, `MANAGER`, `PAUSER` — role holders for deploy (default: deployer).
- `OAPP` — local proxy address (config scripts).
- `PEER` — remote proxy address (SetPeer).
- `DST_EID` — optional override of the paired remote eid (defaults to the config value).

## DVNs

Selected DVNs: **LayerZero Labs, Nethermind, Google, USDT0**. Mainnet config uses
`requiredDVNs = [LayerZero Labs, Nethermind, Google]` (3) and `optionalDVNs = [USDT0]`
(1, threshold 1). Edit `OFTConfig.sol` to change the policy; DVN arrays are sorted +
deduped before encoding.

## Commands

```bash
# 1. deploy (per chain)
forge script scripts/foundry/oft/v2/DeployListaOFTAdapterV2.s.sol --rpc-url bsc      --broadcast --verify
forge script scripts/foundry/oft/v2/DeployListaOFTv2.s.sol         --rpc-url ethereum --broadcast --verify

# 2. wire peers (MANAGER) — OAPP = local proxy, PEER = remote proxy
OAPP=0x.. PEER=0x.. forge script scripts/foundry/oft/v2/SetPeer.s.sol --rpc-url bsc --broadcast

# 3. DVN / send / receive library config (MANAGER/delegate)
OAPP=0x.. forge script scripts/foundry/oft/v2/SetDVNConfig.s.sol --rpc-url bsc --broadcast

# 4. (re)push transfer limits (MANAGER)
OAPP=0x.. forge script scripts/foundry/oft/v2/SetTransferLimit.s.sol --rpc-url bsc --broadcast
```

> `ethereum` / `sepolia` need an rpc alias in `foundry.toml` or pass the URL directly
> (`--rpc-url "$ETHEREUM_RPC"`). `bsc` / `bsc-test` aliases already exist.

## Tests

Contract behaviour + end-to-end bridge + BSC-fork simulation live in
`test/oft/v2/` (`forge test --match-path "test/oft/v2/*.t.sol"`).
