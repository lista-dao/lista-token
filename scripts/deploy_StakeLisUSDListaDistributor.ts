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
    lpToken = "0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5";
  } else if (hre.network.name === "bscTestnet") {
    admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";
    manager = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";
    listaVault = "0xCfeb269242cf988b61833910E7aaC56554F09f7b";
    lpToken = "0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB";
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
