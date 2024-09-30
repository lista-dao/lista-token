import { deployProxy } from "../tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  console.log("admin: ", deployer);
  let bot, receiver, router;

  if (hre.network.name === "bsc") {
    bot = '0x44CA74923aA2036697a3fA7463CD0BA68AB7F677';
    receiver = '0x8d388136d578dCD791D081c6042284CED6d9B0c6';
    router = '0x111111125421cA6dc452d289314280a0f8842A65';
  } else if (hre.network.name === "bscTestnet") {
    bot = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    receiver = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    router = '0x111111125421cA6dc452d289314280a0f8842A65';
  } else if (hre.network.name === "bscLocal") {
    bot = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    receiver = '0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232';
    router = '0x111111125421cA6dc452d289314280a0f8842A65';
  }

  await deployProxy(hre, "ListaAutoBuyback", deployer, bot, receiver, router);
  console.log("deployProxy done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
