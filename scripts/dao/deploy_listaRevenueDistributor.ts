import { deployProxy } from "../tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  console.log("admin: ", deployer);
  let bot, autoBuybackAddress, revenueWalletAddress;

  if (hre.network.name === "bsc") {
    bot = '';
    autoBuybackAddress = '';
    revenueWalletAddress = '';
  } else if (hre.network.name === "bscTestnet") {
    bot = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    autoBuybackAddress = '';
    revenueWalletAddress = '';
  }
  await deployProxy(hre, "ListaRevenueDistributor", deployer, bot, autoBuybackAddress, revenueWalletAddress, 7e17);
  console.log("deployProxy done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
