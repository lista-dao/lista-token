"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("@openzeppelin/hardhat-upgrades");
require("dotenv/config");
require("@nomiclabs/hardhat-etherscan");
const config_1 = require("hardhat/config");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("hardhat-forta");
const tasks_1 = require("./scripts/tasks");
(0, config_1.task)(
  "deployCrossChainTestToken",
  "Deploy Cross Chain Test Token By Proxy Way"
)
  .addPositionalParam("admin")
  .setAction(async ({ admin }, hre) => {
    await (0, tasks_1.deployProxy)(hre, "CrossChainTestToken", admin);
  });
(0, config_1.task)(
  "upgradeCrossChainTestTokenProxy",
  "Upgrade CrossChainTestToken Proxy"
)
  .addPositionalParam("proxyAddress")
  .setAction(async ({ proxyAddress }, hre) => {
    await (0, tasks_1.upgradeProxy)(hre, "CrossChainTestToken", proxyAddress);
  });
(0, config_1.task)(
  "deployCrossChainTestTokenImpl",
  "Deploy CrossChainTestToken Implementation only"
).setAction(async (args, hre) => {
  await (0, tasks_1.deployDirect)(hre, "CrossChainTestToken");
});
const config = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
      viaIR: true,
    },
    compilers: [
      {
        version: "0.8.19",
        settings: {
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      chainId: 1,
      allowUnlimitedContractSize: true,
      forking: {
        url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        blockNumber: 18071507,
      },
    },
    mainnet: {
      chainId: 1,
      url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [process.env.DEPLOYER_KEY],
    },
    goerli: {
      chainId: 5,
      url: `https://eth-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [process.env.DEPLOYER_KEY],
    },
    sepolia: {
      chainId: 11155111,
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [process.env.DEPLOYER_KEY],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
exports.default = config;
