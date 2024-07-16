import { upgradeProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  // await deployDirect(hre, "ListaToken", owner);
  await upgradeProxy(
    hre,
    "VeListaDistributor",
    "0x836611FE256A8ACDBBB23306A0bc7C1654035fDE"
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
