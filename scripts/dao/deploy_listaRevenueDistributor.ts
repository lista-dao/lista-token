import { deployProxy } from "../tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  console.log("admin: ", deployer);
  let bot, listaAddress, autoBuybackAddress, revenueWalletAddress, listaDistributeToAddress;

  if (hre.network.name === "bsc") {
    listaAddress = '0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46';
    bot = '';
    autoBuybackAddress = '';
    revenueWalletAddress = '';
    listaDistributeToAddress = ''
  } else if (hre.network.name === "bscTestnet") {
    listaAddress = '0x90b94D605E069569Adf33C0e73E26a83637c94B1';
    bot = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    autoBuybackAddress = '';
    revenueWalletAddress = '';
    listaDistributeToAddress = '';
  } else if (hre.network.name === "bscLocal") {
    listaAddress = '0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46';
    bot = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    autoBuybackAddress = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    revenueWalletAddress = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    listaDistributeToAddress = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
  }

  await deployProxy(hre, "ListaRevenueDistributor", deployer, bot, listaAddress, autoBuybackAddress, revenueWalletAddress, listaDistributeToAddress, '700000000000000000');
  console.log("deployProxy done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
