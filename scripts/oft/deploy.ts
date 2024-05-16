import hre, { ethers } from "hardhat";

// Ethereum and BSC use the same LayerZero ENDPOINT
const LZ_ENDPOINT = /^sepolia|bscTestnet$/.test(hre.network.name)
  ? "0x6EDCE65403992e310A62460808c4b910D972f10f"
  : "0x1a44076050125825900e736c501f859c50fE728c";

async function main() {
  const owner = (await hre.ethers.getSigners())[0].address;
  let listaTokenAddress, OFTAdapterAddress, listaOFTAddress;
  console.log("Network: ", hre.network.name);
  // deploy Lista Token at Source Chain (testnet only)
  if (hre.network.name === "bscTestnet") {
    // deploy contract
    const ListaToken = await ethers.getContractFactory("ListaToken");
    const listaToken = await ListaToken.deploy(owner);
    await listaToken.deployed();
    listaTokenAddress = listaToken.address;
    console.log("ListaToken deployed to: ", listaTokenAddress);
    // verify contract
    await hre.run("verify:verify", {
      address: listaTokenAddress,
      constructorArguments: [owner],
    });
  }
  // deploy OFT Adapter at Source Chain
  if (/^bsc/.test(hre.network.name)) {
    // deploy contract
    const OFTAdapter = await ethers.getContractFactory("ListaOFTAdapter");
    const oftAdapter = await OFTAdapter.deploy(
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
      constructorArguments: [listaTokenAddress, LZ_ENDPOINT, owner],
    });
  }
  // deploy OFT at destination chain
  if (/^sepolia|ethereum$/.test(hre.network.name)) {
    // deploy Lista oft
    const ListaOFT = await ethers.getContractFactory("ListaOFT");
    const listaOFT = await ListaOFT.deploy(LZ_ENDPOINT, owner);
    await listaOFT.deployed();
    listaOFTAddress = listaOFT.address;
    console.log("Deployed ListaOFT: ", listaOFTAddress);
    // verify contract
    await hre.run("verify:verify", {
      address: listaOFTAddress,
      constructorArguments: [LZ_ENDPOINT, owner],
    });
  }
}

main()
  .then(() => {
    console.log("Done");
  })
  .catch(console.error);
