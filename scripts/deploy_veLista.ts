import { deployProxy, transferProxyAdminOwner } from "./tasks";
import hre from "hardhat";
import moment from "moment";

const admin = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
const manager = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
const newOwner = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";

async function main() {
  // await deployDirect(hre, "ListaToken", owner);

  const startTime = moment.utc("2024-07-03", "YYYY-MM-DD");
  console.log("startTime", startTime.unix());
  const listaToken = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
  const address = await deployProxy(hre, "VeLista", admin, manager, startTime.unix(), listaToken, manager);
  await transferProxyAdminOwner(hre, address, newOwner);
  console.log("done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
