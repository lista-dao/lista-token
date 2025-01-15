import { deployProxy } from "../tasks";
import hre from "hardhat";

const collateralConfigs: any[] = [{
  symbol: 'mBTC CollateralListaDAODistributor',
  lpToken: '0x7c1cCA5b25Fa0bC9AF9275Fb53cBA89DC172b878',
}, {
  symbol: 'mCake CollateralListaDAODistributor',
  lpToken: '0x581FA684D0Ec11ccb46B1d92F1F24C8A3F95C0CA',
}, {
  symbol: 'mwBETH CollateralListaDAODistributor',
  lpToken: '0x7dC91cBD6CB5A3E6A95EED713Aa6bF1d987146c8',
}]

async function main() {
  const name = "ListaDao";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let listaVault = '', manager;
  if (hre.network.name === "bsc" || hre.network.name === "bscLocal") {
    listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
    manager = "0x74E17e6996f0DDAfdA9B500ab15a3AD7c2f69307"; // router address
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    manager = "0x227eeaf69495E97c1E72A48785B8A041664b5a28"; // router address

    collateralConfigs[0].lpToken = ''
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
    console.log(`CollateralListaDistributor loop done, ${collateralConfig.symbol} deployed to: ${address}`);
  }

  console.log(`CollateralListaDistributor all done`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
