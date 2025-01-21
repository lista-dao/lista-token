import { deployProxy } from "../tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let admin, manager, bot, revenueReceiver, lista, burnPercentage;
  if (hre.network.name === "bsc") {
    admin = "";
    manager = "";
    bot = "";
    revenueReceiver = "";
    lista = "";
    burnPercentage = "";
  } else if (hre.network.name === "bscTestnet") {
    admin = deployer;
    manager = deployer;
    bot = deployer;
    revenueReceiver = deployer;
    lista = "0x90b94D605E069569Adf33C0e73E26a83637c94B1";
    burnPercentage = "4000";
  }

  console.log(`VeListaRevenueDistributor deploy start`);
  const address = await deployProxy(
    hre,
    "VeListaRevenueDistributor",
    admin,
    manager,
    bot,
    revenueReceiver,
    lista,
    burnPercentage
  );
  console.log(`VeListaRevenueDistributor deploy done, deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
