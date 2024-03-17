# Helio ETH-contracts (forked from Prisma finance - commit hash #6952ff8d3fc0511fff6015701e9f513510be8cce)

A decentralized, non-custodial stablecoin backed by Ethereum liquid staking tokens.

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
DEPLOYER_KEY="your private key"
ALCHEMY_API_KEY="your alchemy api key"
ETHERSCAN_API_KEY=""
```

`DEPLOYER_KEY` is the private key of the account that will deploy the contracts. It should have enough ETH to pay for the gas fees.

To get `ALCHEMY_API_KEY`, you need to create an account on [Alchemy](https://www.alchemy.com/). Then, create a new Ethereum app and copy the API key.

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

## How to deploy on Sepolia

1. Add `SEPOLIA_DEPLOYER_KEY` to `.env` file and make sure other environment variables are valid
2. Run `npx hardhat run scripts/deploy.ts --network sepolia`, which will deploy and verify Lista contracts on Sepolia
