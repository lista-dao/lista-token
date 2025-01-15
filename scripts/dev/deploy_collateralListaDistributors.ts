import { deployProxy } from "../tasks";
import hre from "hardhat";

const collateralConfigs: any[] = [
  // {
  //   symbol: 'mBTC CollateralListaDAODistributor',
  //   lpToken: '0x2deB430701DE0BB24ADD0c815C464e6DC6BB2634',
  // },
  // {
  //   symbol: 'mCake CollateralListaDAODistributor',
  //   lpToken: '0x70ad940d73415CDDAc47861e9691795AA7a119e1',
  // },
  {
  symbol: 'mwBETH CollateralListaDAODistributor',
  lpToken: '0x410E153F72Fa68D1e0A2aAF7e4be75CD0513E63E',
  }
]

async function main() {
  const name = "ListaDao";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let listaVault = '', manager;
  if (hre.network.name === "bscTestnet") {
    listaVault = "0x0fD548f448AAB6dE7489F8FD1a4be1efca009f1C";
    manager = "0x227eeaf69495E97c1E72A48785B8A041664b5a28";
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
