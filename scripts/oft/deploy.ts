import hre, { ethers } from "hardhat";
import chains from "./oftChains.json";

function getConfig() {
  const network = hre.network.name;
  const config = chains.filter((c) => c.network === network)[0];
  if (!config) throw new Error("Chain not found");
  return config;
}

async function main() {
  const owner = (await hre.ethers.getSigners())[0].address;
  const chainConfig = getConfig();
  const LZ_ENDPOINT = chainConfig.lz;
  const limit = (chainConfig.transferLimits || [])[0];
  console.log("Network: ", hre.network.name);
  console.log("Chain Config: ", chainConfig);
  let listaTokenAddress = chainConfig.existingTokenAddress;
  let OFTAdapterAddress;
  let listaOFTAddress;
  // deploy Lista Token at Source Chain (testnet only)
  if (hre.network.name === "bscTestnet" && !listaTokenAddress) {
    // deploy contract
    const ListaToken = await ethers.getContractFactory("MockToken");
    const listaToken = await ListaToken.deploy(
      owner,
      chainConfig.tokenName,
      chainConfig.symbol
    );
    await listaToken.deployed();
    listaTokenAddress = listaToken.address;
    console.log("ListaToken deployed to: ", listaTokenAddress);
    // verify contract
    await hre.run("verify:verify", {
      address: listaTokenAddress,
      contract: "contracts/mock/MockToken.sol:MockToken",
      constructorArguments: [owner, chainConfig.tokenName, chainConfig.symbol],
    });
  }
  // deploy OFT Adapter at Source Chain
  if (chainConfig.contract === "ListaOFTAdapter") {
    if (!(listaTokenAddress || "").length) {
      throw new Error("ListaToken address is required");
    }
    const args = [
      limit
        ? [
            [
              limit.dstEid,
              limit.maxDailyTransferAmount,
              limit.singleTransferUpperLimit,
              limit.singleTransferLowerLimit,
              limit.dailyTransferAmountPerAddress,
              limit.dailyTransferAttemptPerAddress,
            ],
          ]
        : [],
      listaTokenAddress,
      LZ_ENDPOINT,
      owner,
    ];
    // deploy contract
    const OFTAdapter = await ethers.getContractFactory("ListaOFTAdapter");
    const oftAdapter = await OFTAdapter.deploy(...args);
    await oftAdapter.deployed();
    OFTAdapterAddress = oftAdapter.address;
    console.log("OFTAdapter deployed to: ", OFTAdapterAddress);
    // verify contract
    await hre.run("verify:verify", {
      address: OFTAdapterAddress,
      constructorArguments: args,
    });
  }
  // deploy OFT at destination chain
  if (chainConfig.contract === "ListaOFT") {
    const args = [
      chainConfig.tokenName,
      chainConfig.symbol,
      limit
        ? [
            [
              limit.dstEid,
              limit.maxDailyTransferAmount,
              limit.singleTransferUpperLimit,
              limit.singleTransferLowerLimit,
              limit.dailyTransferAmountPerAddress,
              limit.dailyTransferAttemptPerAddress,
            ],
          ]
        : [],
      LZ_ENDPOINT,
      owner,
    ];
    // deploy Lista oft
    const ListaOFT = await ethers.getContractFactory("ListaOFT");
    const listaOFT = await ListaOFT.deploy(...args);
    await listaOFT.deployed();
    listaOFTAddress = listaOFT.address;
    console.log("Deployed ListaOFT: ", listaOFTAddress);
    console.log("Waiting for 10 seconds before verifying contract...");
    await new Promise((resolve) => setTimeout(resolve, 10000));
    // verify contract
    await hre.run("verify:verify", {
      address: listaOFTAddress,
      constructorArguments: args,
    });
  }
}

main()
  .then(() => {
    console.log("Done");
  })
  .catch(console.error);
