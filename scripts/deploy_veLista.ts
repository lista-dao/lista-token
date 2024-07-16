import { deployProxy, transferProxyAdminOwner } from "./tasks";
import hre from "hardhat";
import moment from "moment";

const multiSig = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";

async function main() {
  // await deployDirect(hre, "ListaToken", owner);
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  console.log(deployer);

  const startTime = moment.utc("2024-07-10", "YYYY-MM-DD");
  console.log("startTime", startTime.unix());
  const listaToken = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
  await deployProxy(hre, "VeLista", deployer, deployer, startTime.unix(), listaToken, multiSig);
  console.log("done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
