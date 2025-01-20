import { deployProxy } from "../tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let admin, manager, bot, velista, lista;
  if (hre.network.name === "bsc") {
    admin = "";
    manager = "";
    bot = "";
    velista = "";
    lista = "";
  } else if (hre.network.name === "bscTestnet") {
    admin = deployer;
    manager = deployer;
    bot = deployer;
    velista = "0x79B3286c318bdf7511A59dcf9a2E88882064eCbA";
    lista = "0x90b94D605E069569Adf33C0e73E26a83637c94B1";
  }

  console.log(`VeListaVault deploy start`);
  const address = await deployProxy(
    hre,
    "VeListaVault",
    admin,
    manager,
    bot,
    velista,
    lista,
  );
  console.log(`VeListaVault deploy done, deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
