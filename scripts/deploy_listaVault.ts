import { deployProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  console.log("admin", deployer);
  let listaToken, veLista;
  if (hre.network.name === "bsc") {
    listaToken = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
    veLista = "0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3";
  } else if (hre.network.name === "bscTestnet") {
    listaToken = "0x90b94D605E069569Adf33C0e73E26a83637c94B1";
    veLista = "0x79B3286c318bdf7511A59dcf9a2E88882064eCbA";
  }
  await deployProxy(hre, "ListaVault", deployer, deployer, listaToken, veLista);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
