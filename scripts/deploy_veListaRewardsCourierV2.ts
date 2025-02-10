import { deployProxy } from "./tasks";
import hre from "hardhat";
async function main() {
  const contractName = "VeListaRewardsCourierV2";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  let listaToken, admin, bot, distributor, veLista, veListaDistributor;

  if (hre.network.name === "bsc") {
    listaToken = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
    admin = "";
    bot = "";
    distributor = "";
    veLista = "0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3";
    veListaDistributor = "0x45aAc046Bc656991c52cf25E783c6942425ce40C";
  } else if (hre.network.name === "bscTestnet") {
    listaToken = "0x90b94D605E069569Adf33C0e73E26a83637c94B1"
    admin = deployer;
    bot = deployer;
    distributor = deployer;
    veLista = "0x79B3286c318bdf7511A59dcf9a2E88882064eCbA";
    veListaDistributor = "0x040037d4c8cb2784d47a75Aa20e751CDB1E8971A";
  }

  const address = await deployProxy(
    hre,
    contractName,
    listaToken,
    admin,
    bot,
    distributor,
    veLista,
    veListaDistributor,
  );
  console.log(`veListaRewardsCourierV2 deployed to: ${address}`);
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
