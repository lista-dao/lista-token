import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  const listaToken = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
  const veLista = "0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3";
  await deployProxy(hre, "ListaVault", admin, admin, listaToken, veLista);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
