import { deployProxy } from "./tasks";
import hre from "hardhat";
async function main() {
  const name = "ListaDao";
  const symbol = "Lista-Stake LisUSD ListaDAODistributor";
  let lpToken, listaVault, manager;
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  if (hre.network.name === "bsc") {
    listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
    lpToken = "0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5";
    manager = "0x0a1Fd12F73432928C190CAF0810b3B767A59717e";
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    lpToken = "0xA528b0E61b72A0191515944cD8818a88d1D1D22b";
    manager = "0x371588eBFA6D6fA9E38637D9880CC3327b33f82F";
  }
  const address = await deployProxy(
    hre,
    "StakeLisUSDListaDistributor",
    name,
    symbol,
    deployer,
    manager,
    listaVault,
    lpToken
  );

  const contract = await hre.ethers.getContractAt("ListaVault", listaVault);

  await contract.registerDistributor(address);

  console.log(`StakeLisUSDListaDistributor deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
