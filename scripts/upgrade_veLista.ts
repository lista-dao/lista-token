import { upgradeProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  // await deployDirect(hre, "ListaToken", owner);
  await upgradeProxy(
    hre,
    "VeLista",
    "0x51075B00313292db08f3450f91fCA53Db6Bd0D11"
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
