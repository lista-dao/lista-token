import { deployProxy } from "./tasks";
import hre from "hardhat";
async function main() {
  const name = "ListaDao";
  const symbol = "Lista-Borrow LisUSD ListaDAODistributor";
  let lpToken, listaVault, admin, manager;
  if (hre.network.name === "bsc") {
    admin = "";
    manager = "";
    listaVault = "";
    lpToken = "";
  } else if (hre.network.name === "bscTestnet") {
    admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";
    manager = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";
    listaVault = "0xCfeb269242cf988b61833910E7aaC56554F09f7b";
    lpToken = "0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB";
  }
  await deployProxy(
    hre,
    "BorrowLisUSDListaDistributor",
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
