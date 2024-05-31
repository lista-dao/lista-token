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
  console.log("Network: ", hre.network.name);
  console.log("Chain Config: ", chainConfig);
  let listaTokenAddress, OFTAdapterAddress, listaOFTAddress;
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
    // deploy contract
    const OFTAdapter = await ethers.getContractFactory("ListaOFTAdapter");
    const oftAdapter = await OFTAdapter.deploy(
      [],
      listaTokenAddress,
      LZ_ENDPOINT,
      owner
    );
    await oftAdapter.deployed();
    OFTAdapterAddress = oftAdapter.address;
    console.log("OFTAdapter deployed to: ", OFTAdapterAddress);
    // verify contract
    await hre.run("verify:verify", {
      address: OFTAdapterAddress,
      constructorArguments: [[], listaTokenAddress, LZ_ENDPOINT, owner],
    });
  }
  // deploy OFT at destination chain
  if (chainConfig.contract === "ListaOFT") {
    // deploy Lista oft
    const ListaOFT = await ethers.getContractFactory("ListaOFT");
    const listaOFT = await ListaOFT.deploy(
      chainConfig.tokenName,
      chainConfig.symbol,
      [],
      LZ_ENDPOINT,
      owner
    );
    await listaOFT.deployed();
    listaOFTAddress = listaOFT.address;
    console.log("Deployed ListaOFT: ", listaOFTAddress);
    // verify contract
    await hre.run("verify:verify", {
      address: listaOFTAddress,
      constructorArguments: [
        chainConfig.tokenName,
        chainConfig.symbol,
        [],
        LZ_ENDPOINT,
        owner,
      ],
    });
  }
}

main()
  .then(() => {
    console.log("Done");
  })
  .catch(console.error);
