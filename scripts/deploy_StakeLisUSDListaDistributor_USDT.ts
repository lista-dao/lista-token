import { deployProxy } from "./tasks";
import hre from "hardhat";
async function main() {
  const name = "ListaDao stake USDT";
  const symbol = "Lista-Stake USDT ListaDAODistributor";
  let lpToken, listaVault, lisUSDPool;
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  if (hre.network.name === "bsc") {
    listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
    lpToken = "0x55d398326f99059fF775485246999027B3197955";
    lisUSDPool = "";
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    lpToken = "0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB";
    lisUSDPool = "0xA23FC5Cd5a1bC0fa7BcC90A89bdd1487ac8e3970";
  }
  const address = await deployProxy(
    hre,
    "StakeLisUSDListaDistributor",
    name,
    symbol,
    deployer,
    lisUSDPool,
    listaVault,
    lpToken
  );

  console.log(`StakeLisUSDListaDistributor deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
