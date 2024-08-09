import { deployProxy } from "./tasks";
import hre from "hardhat";
async function main() {
  const name = "ListaDao";
  const symbol = "Lista-Stake LisUSD ListaDAODistributor";
  let lpToken, listaVault, admin, manager;
  if (hre.network.name === "bsc") {
    admin = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
    manager = "0xB68443Ee3e828baD1526b3e0Bdf2Dfc6b1975ec4";
    listaVault = "";
    lpToken = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
  } else if (hre.network.name === "bscTestnet") {
    admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";
    manager = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";
    listaVault = "0x5C25A9FC1CFfda5D7E871C73929Dfca85ef6c92d";
    lpToken = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
  }
  await deployProxy(
    hre,
    "StakeLisUSDListaDistributor",
    name,
    symbol,
    admin,
    manager,
    listaVault,
    lpToken
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
