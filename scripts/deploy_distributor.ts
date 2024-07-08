import { deployProxy, transferProxyAdminOwner } from "./tasks";
import hre from "hardhat";

const admin = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
const manager = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
const newOwner = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";

async function main() {
  const veLista = "0xA84345476c5F60DA60e080AF4EDE005eDbd0175d";
  const address = await deployProxy(hre, "VeListaDistributor", admin, manager, veLista);
  await transferProxyAdminOwner(hre, address, newOwner);
  console.log("done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
