import { deployProxy } from "../tasks";
import hre from "hardhat";

const collateralConfigs: any[] = [
{
  symbol: 'USDT CollateralListaDAODistributor',
  lpToken: '0x49b1401B4406Fe0B32481613bF1bC9Fe4B9378aC',
},
{
  symbol: 'solvBTC CollateralListaDAODistributor',
  lpToken: '0xB1E63330f4718772CF939128d222389b30C70cF2',
}, {
  symbol: 'ceABNBc CollateralListaDAODistributor',
  lpToken: '0x92D8c63E893685Cced567b23916a8726b0CEF3FE',
}]

async function main() {
  const name = "ListaDao";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let listaVault = '', manager;
  if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    manager = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";
  }

  for (const collateralConfig of collateralConfigs) {
    console.log(`CollateralListaDistributor loop start, ${collateralConfig.symbol}`);

    const address = await deployProxy(
      hre,
      "CollateralListaDistributor",
      name,
      collateralConfig.symbol,
      deployer,
      manager,
      listaVault,
      collateralConfig.lpToken
    );
    console.log(`CollateralListaDistributor loop deploy, ${collateralConfig.symbol} deployed to: ${address}`);

    const contract = await hre.ethers.getContractAt("ListaVault", listaVault);
    await contract.registerDistributor(address);
    console.log(`CollateralListaDistributor loop done, ${collateralConfig.symbol} registered`);
  }

  console.log(`CollateralListaDistributor all done`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
