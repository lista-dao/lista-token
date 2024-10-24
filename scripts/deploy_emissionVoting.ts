import { deployProxy } from "./tasks";
import hre from "hardhat";
import { ethers } from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  let adminRole = "";
  let adminVoter = "";
  let veLista = "0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3";
  let listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
  let pauser = "0xEEfebb1546d88EA0909435DF6f615084DD3c5Bd8";
  const adminVotePeriod = 86400;

  if (hre.network.name === "bscTestnet") {
    adminRole = deployer;
    adminVoter = deployer;
    veLista = "0x79B3286c318bdf7511A59dcf9a2E88882064eCbA";
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    pauser = deployer;
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

  // set pauser
  const emissionVoting = await ethers.getContractAt(
    "EmissionVoting",
    "0xaD2f3D7b233aF4fb7bdF676162148a6559Ae962B"
  );
  await emissionVoting.grantRole(
    "0x539440820030c4994db4e31b6b800deafd503688728f932addfe7a410515c14c", // PAUSER_ROLE
    pauser
  );

  console.log("done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
