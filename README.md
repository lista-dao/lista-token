# Lista DAO
Lista DAO token and governance contracts.

## Lista Token
Given as an incentive for users of the protocol. Can be locked in `VeLista`
to receive lock weight, which gives governance power within the Lista DAO.

## How to run unit tests

### Requirements

- [Node.js](https://nodejs.org/en/) (v18 or higher)
- [Yarn](https://yarnpkg.com/) (`npm i -g yarn`)

### Install dependencies

Install dependencies with Yarn:
```bash
# Execute this command in the root directory of the repository
yarn
forge install foundry-rs/forge-std --no-commit
```

### Configure environment variables

1. Copy the `.env.example` file to `.env`:
```bash
cp .env.example .env
```

2. Fill in the environment variables in the `.env` file:
```env
ETHERSCAN_API_KEY=
BSCSCAN_API_KEY=
DEPLOYER_PRIVATE_KEY=
BSC_TESTNET_RPC=
BSC_RPC=
SEPOLIA_RPC=
ETHEREUM_RPC=
```

`DEPLOYER_PRIVATE_KEY` is the private key of the account that will deploy the contracts. It should have enough BNB/ETH to pay for the gas fees.

### Run tests

Run all tests:
```bash
yarn test:all
# or
npx hardhat test
```

Run a specific test file:
```bash
npx hardhat test <path/to/file>
```

Run a specific test file with forge:
```bash
forge test --match-contract <Contract Test Script Name> -vvv
forge test --match-contract <Contract Test Script Name> -vvv --via-ir
forge test --match-contract <Contract Test Script Name> --match-test <Test Name> -vvv

# Examples
forge test --match-contract BuybackTest -vvv
# clean the cache and run the test
forge clean && forge test --match-contract BuybackTest -vvv
# run a specific test in the contract
forge test --match-contract BuybackTest --match-test "test_buyback" -vvv
```

### Run coverage

Generate coverage report:
```bash
yarn coverage
```

Open coverage report in browser: `coverage/index.html`

## How to deploy on bsc

1. Run `npx hardhat deploy:ListaToken --network bsc <ownerAddress>`, which will deploy Lista contracts on bsc,
   the owner address is the address that will receive the total supply of tokens
2. Run `npx hardhat verify --network bsc <contractAddress> <ownerAddress>`, which will verify Lista contracts on bsc

## How to deploy on bsc with foundry
Run `forge script <path_to_script> --rpc-url <your_rpc_url> --private-key <your_private_key> --etherscan-api-key <bscscan-api-key> --broadcast --verify -vvv`, which will deploy Lista contracts on bsc with foundry, for example:
```bash
# deploy the proxy contract of Buyback
forge script scripts/buyback/Buyback.s.sol:BuybackScript --rpc-url https://bsc-dataseed.binance.org --etherscan-api-key <bscscan-api-key> --broadcast --verify -vvv
```

## Code style
The contracts in folder `contracts/buyback` are formatted using Prettier. To check and fix linting errors:
```bash
# Check for linting errors
yarn run check

# Fix linting errors
yarn run fix
```

### Check and fix linting errors for a specific contract
1. Run `npx prettier --check <contract>` to check for linting errors, for example:
```bash
npx prettier --check contracts/buyback/Buyback.sol
```
2. Run `npx prettier --write <contract>` to fix linting errors, for example:
```bash
npx prettier --write contracts/buyback/Buyback.sol
```
