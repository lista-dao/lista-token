import { deployProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  let adminRole = "";
  let adminVoter = "";
  let veLista = "0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3";
  let listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
  const adminVotePeriod = 86400;

  if (hre.network.name === "bscTestnet") {
    adminRole = deployer;
    adminVoter = deployer;
    veLista = "0x79B3286c318bdf7511A59dcf9a2E88882064eCbA";
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
  }

  const address = await deployProxy(
    hre,
    "EmissionVoting",
    adminRole,
    adminVoter,
    veLista,
    listaVault,
    adminVotePeriod
  );
  console.log("EmissionVoting deployed to:", address);

  await hre.run("verify:verify", {
    address,
  });
  console.log("done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
