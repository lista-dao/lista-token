import "@openzeppelin/hardhat-upgrades";
import "dotenv/config";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "@typechain/hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { HardhatUserConfig, task } from "hardhat/config";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-forta";
import { deployDirect } from "./scripts/tasks";

task("deploy:ListaToken", "Deploy ListaToken")
  .addPositionalParam("owner")
  .setAction(async ({ owner }, hre: HardhatRuntimeEnvironment) => {
    await deployDirect(hre, "ListaToken", owner);
  });

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
      viaIR: true,
    },
  },
  networks: {
    hardhat: {
      // chainId: 1,
      // allowUnlimitedContractSize: true,
      // forking: {
      //   url: process.env.BSC_RPC || "",
      //   blockNumber: 18071507,
      // },
    },
    ethereum: {
      url: process.env.ETHEREUM_RPC || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    bsc: {
      url: process.env.BSC_RPC || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    bscTestnet: {
      url: process.env.BSC_TESTNET_RPC || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    opBnbTestnet: {
      url: process.env.OPBNB_TESTNET_RPC || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    bscLocal: {
      url: "http://127.0.0.1:8545",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://bscscan.com/ or https://etherscan.io
    apiKey: {
      bscTestnet: process.env.BSCSCAN_API_KEY || "",
      bsc: process.env.BSCSCAN_API_KEY || "",
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      opBnbTestnet: process.env.OPBNB_SCAN_API_KEY || "",
    },
    customChains: [
      {
        network: "opBnbTestnet",
        chainId: 5611,
        urls: {
          apiURL: `https://open-platform.nodereal.io/${process.env.OPBNB_SCAN_API_KEY}/op-bnb-testnet/contract/`,
          browserURL: "https://testnet.opbnbscan.com/",
        },
      },
    ],
  },
};

export default config;
