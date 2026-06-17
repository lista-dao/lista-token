# Lista OFT v2 (upgradeable) — BSC ↔ Ethereum

Upgradeable LayerZero V2 bridge for the canonical LISTA token.

```
Native BSC LISTA --(lock)--> ListaOFTAdapterV2 --> LayerZero --> ListaOFTv2 (mint) @ ETH
ListaOFTv2 (burn) @ ETH      --> LayerZero --> ListaOFTAdapterV2 (unlock) --> BSC
```

| Chain | Contract | Mechanic |
|-------|----------|----------|
| BSC (home) | `ListaOFTAdapterV2` | locks / unlocks the canonical LISTA (lockbox) |
| ETH (remote) | `ListaOFTv2` | mints / burns a 1:1 backed representation (EIP-2612) |

## Roles

| Role | Capabilities |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | authorize UUPS upgrades, manage roles (also Ownable owner) |
| `MANAGER_ROLE` | `setPeer` / `setEnforcedOptions` / `setMsgInspector` / `setPreCrime`, transfer-limiter config, `unpause()`, LZ endpoint delegate |
| `PAUSER_ROLE` | `pause()` |

## Config files

- `oftChainsV2.mainnet.example.json` / `oftChainsV2.testnet.example.json` — committed templates with the real LayerZero endpoint, send/receive ULN, executor and DVN addresses.
- Copy to `oftChainsV2.mainnet.json` / `oftChainsV2.testnet.json` (git-ignored) before deploying; deploy scripts write the resulting proxy address back into the live file.
- Roles are read from the `ADMIN` / `MANAGER` / `PAUSER` environment variables.

## DVNs

Selected DVNs: **LayerZero Labs, Nethermind, Google, USDT0**. The mainnet example sets
`requiredDVNs = [LayerZero Labs, Nethermind, Google]` (3) and `optionalDVNs = [USDT0]` (1,
threshold 1). Adjust `ulnConfig` in the config file to change the policy; DVN addresses are
resolved per chain from the `dvns` map and sorted/deduped automatically.

## Commands

```bash
# 1. deploy (run on each chain)
OFT_ENV=mainnet npx hardhat run scripts/oft/v2/deploy.mainnet.ts --network bsc
OFT_ENV=mainnet npx hardhat run scripts/oft/v2/deploy.mainnet.ts --network ethereum
#    testnet equivalents:
OFT_ENV=testnet npx hardhat run scripts/oft/v2/deploy.testnet.ts --network bscTestnet
OFT_ENV=testnet npx hardhat run scripts/oft/v2/deploy.testnet.ts --network sepolia

# 2. wire peers (run on each chain, MANAGER)
OFT_ENV=mainnet npx hardhat run scripts/oft/v2/setPeer.ts --network bsc
OFT_ENV=mainnet npx hardhat run scripts/oft/v2/setPeer.ts --network ethereum

# 3. configure DVN / send / receive libraries (run on each chain, MANAGER/delegate)
OFT_ENV=mainnet npx hardhat run scripts/oft/v2/setDVNConfig.ts --network bsc
OFT_ENV=mainnet npx hardhat run scripts/oft/v2/setDVNConfig.ts --network ethereum

# 4. (re)push transfer limits if needed (MANAGER)
OFT_ENV=mainnet npx hardhat run scripts/oft/v2/setTransferLimit.ts --network bsc
```

## Tests

```bash
forge test --match-path "test/oft/v2/local.t.sol"   # mock-endpoint end-to-end
forge test --match-path "test/oft/v2/fork.t.sol"     # BSC fork against real LISTA + real endpoint
```
