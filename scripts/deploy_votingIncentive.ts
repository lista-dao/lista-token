import { deployProxyUUPS } from "./tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  console.log("admin", deployer);
  let vault, emissionVoting, admin, adminVoter;
  if (hre.network.name === "bsc") {
//    listaToken = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
//    veLista = "0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3";
  } else if (hre.network.name === "bscTestnet") {
    admin = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";
    adminVoter = "0xF45FB2567C2E081a2C866bba10d3dc543AFa2920";
    vault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    emissionVoting = "0x6B7B87F92354bEC0eC20Db0CB328e186cda950dd";
  }
  await deployProxyUUPS(hre, "VotingIncentive", vault, emissionVoting, adminVoter, admin);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
