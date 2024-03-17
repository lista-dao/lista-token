# Lista DAO Token

Given as an incentive for users of the protocol. Can be locked in `TokenLocker`
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

### Run coverage

Generate coverage report:
```bash
yarn coverage
```

Open coverage report in browser: `coverage/index.html`

## How to deploy on bsc

1. Run `npx hardhat deploy:ListaToken --network bsc <ownerAddress>`, which will deploy Lista contracts on bsc
   the owner address is the address that will receive the total supply of tokens
2. Run `npx hardhat verify --network bsc <contractAddress> <ownerAddress>`, which will deploy Lista contracts on bsc
