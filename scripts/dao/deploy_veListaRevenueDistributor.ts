import { deployProxy } from "../tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let admin, manager, bot, revenueReceiver, lista, burnPercentage;
  if (hre.network.name === "bsc") {
    admin = "0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253"; // time lock
    manager = "0x8d388136d578dCD791D081c6042284CED6d9B0c6"; // manager
    bot = "0x44CA74923aA2036697a3fA7463CD0BA68AB7F677"; // bot
    revenueReceiver = "0x8d388136d578dCD791D081c6042284CED6d9B0c6"; // revenue receiver
    lista = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46"; // lista token
    burnPercentage = "1000";
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
