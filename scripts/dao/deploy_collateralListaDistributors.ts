import { deployProxy } from "../tasks";
import hre from "hardhat";

const collateralConfigs: any[] = [{
  symbol: 'ceABNBc CollateralListaDAODistributor',
  lpToken: '0x563282106A5B0538f8673c787B3A16D3Cc1DbF1a',
}, {
  symbol: 'SnBNB CollateralListaDAODistributor',
  lpToken: '0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B',
}, {
  symbol: 'cewBETH CollateralListaDAODistributor',
  lpToken: '0x6C813D1d114d0caBf3F82f9E910BC29fE7f96451',
}, {
  symbol: 'wBETH CollateralListaDAODistributor',
  lpToken: '0xa2E3356610840701BDf5611a53974510Ae27E2e1',
}, {
  symbol: 'wstETH CollateralListaDAODistributor',
  lpToken: '0x26c5e01524d2e6280a48f2c50ff6de7e52e9611c',
}, {
  symbol: 'BTCB CollateralListaDAODistributor',
  lpToken: '0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c',
}, {
  symbol: 'USDT CollateralListaDAODistributor',
  lpToken: '0x55d398326f99059fF775485246999027B3197955',
}, {
  symbol: 'FDUSD CollateralListaDAODistributor',
  lpToken: '0xc5f0f7b66764f6ec8c8dff7ba683102295e16409',
}, {
  symbol: 'STONE CollateralListaDAODistributor',
  lpToken: '0x80137510979822322193FC997d400D5A6C747bf7',
}, {
  symbol: 'solvBTC CollateralListaDAODistributor',
  lpToken: '0x4aae823a6a0b376De6A78e74eCC5b079d38cBCf7',
}, {
  symbol: 'solvBTC.BBN CollateralListaDAODistributor',
  lpToken: '0x1346b618dc92810ec74163e4c27004c921d446a5',
}]

async function main() {
  const name = "ListaDao";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let listaVault = '', manager;
  if (hre.network.name === "bsc") {
    listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
    manager = ""; // router address
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    manager = ""; // router address
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

    // const contract = await hre.ethers.getContractAt("ListaVault", listaVault);
    // await contract.registerDistributor(address);
  }

  console.log(`CollateralListaDistributor all done`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
