import { deployProxy } from "../tasks";
import hre from "hardhat";

const collateralConfigs: any[] = [{
  symbol: 'sUSDX CollateralListaDAODistributor',
  lpToken: '0x7788A3538C5fc7F9c7C8A74EAC4c898fC8d87d92',
}]

async function main() {
  const name = "ListaDao";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let listaVault = '', manager;
  if (hre.network.name === "bsc") {
    listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
    manager = "0x74E17e6996f0DDAfdA9B500ab15a3AD7c2f69307"; // router address
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    manager = "0x227eeaf69495E97c1E72A48785B8A041664b5a28"; // router address

    collateralConfigs[0].lpToken = '0xdb66d7e8edF8a16aD5e802704D2cA4EFca9e8a46'
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
