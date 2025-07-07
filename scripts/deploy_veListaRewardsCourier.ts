import { deployProxy } from "./tasks";
import hre from "hardhat";
async function main() {
  const contractName = "VeListaRewardsCourier";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  let admin, bot, veListaDistributor;

  if (hre.network.name === "bsc") {
    admin = deployer;
    bot = "";
    veListaDistributor = "0x45aAc046Bc656991c52cf25E783c6942425ce40C";
  } else if (hre.network.name === "bscTestnet") {
    admin = deployer;
    bot = deployer;
    veListaDistributor = "0x040037d4c8cb2784d47a75Aa20e751CDB1E8971A";
  }
  const address = await deployProxy(
    hre,
    contractName,
    admin,
    bot,
    veListaDistributor
  );
  console.log(`veListaRewardsCourier deployed to: ${address}`);
  // verify contract
  await hre.run("verify:verify", {
    address,
  });
  console.log("----- DONE -----");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
