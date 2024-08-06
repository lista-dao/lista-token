import { deployProxy } from "./tasks";
import hre from "hardhat";
async function main() {
  const name = "ListaDao";
  const symbol = "Lista-Borrow LisUSD ListaDAODistributor";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let lpToken, listaVault, manager;
  if (hre.network.name === "bsc") {
    // todo
    listaVault = "";
    lpToken = "0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5";
    manager = "0xB68443Ee3e828baD1526b3e0Bdf2Dfc6b1975ec4";
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    lpToken = "0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB";
    manager = "";
  }
  const address = await deployProxy(
    hre,
    "BorrowLisUSDListaDistributor",
    name,
    symbol,
    deployer,
    manager,
    listaVault,
    lpToken
  );

  const contract = await hre.ethers.getContractAt("ListaVault", listaVault);

  await contract.registerDistributor(address);

  console.log(`BorrowLisUSDListaDistributor deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
