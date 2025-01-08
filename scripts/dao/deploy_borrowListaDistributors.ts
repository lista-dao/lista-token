import { deployProxy } from "../tasks";
import hre from "hardhat";

const collateralConfigs: any[] = [{
  symbol: 'ceABNBc BorrowListaDAODistributor',
  lpToken: '0x92D8c63E893685Cced567b23916a8726b0CEF3FE',
}, {
  symbol: 'slisBNB BorrowListaDAODistributor',
  lpToken: '0xCc752dC4ae72386986d011c2B485be0DAd98C744',
}, {
  symbol: 'cewBETH BorrowListaDAODistributor',
  lpToken: '0xf1Abbc41721D0970BEa2e84C5bC159F8D3Cac760',
}, {
  symbol: 'wBETH BorrowListaDAODistributor',
  lpToken: '0x34f8f72e3f14Ede08bbdA1A19a90B35a80f3E789',
}, {
  symbol: 'wstETH BorrowListaDAODistributor',
  lpToken: '0x41e3750FafC565f89c11DF06fEE257b93bB19A31',
}, {
  symbol: 'BTCB BorrowListaDAODistributor',
  lpToken: '0x4BB2f2AA54c6663BFFD37b54eCd88eD81bC8B3ec',
}, {
  symbol: 'USDT BorrowListaDAODistributor',
  lpToken: '0x49b1401B4406Fe0B32481613bF1bC9Fe4B9378aC',
}, {
  symbol: 'FDUSD BorrowListaDAODistributor',
  lpToken: '0xadbccCa89eC498F8B9B7F6A4B05206b113676861',
}, {
  symbol: 'STONE BorrowListaDAODistributor',
  lpToken: '0xb982479692b9f9D5d6582a36f49255205b18aE9e',
}, {
  symbol: 'solvBTC BorrowListaDAODistributor',
  lpToken: '0xB1E63330f4718772CF939128d222389b30C70cF2',
}, {
  symbol: 'SolvBTC.BBN BorrowListaDAODistributor',
  lpToken: '0x16D9A837e0D1AAC45937425caC26CcB729388C9A',
}, {
  symbol: 'sUSDX BorrowListaDAODistributor',
  lpToken: '0xdb66d7e8edF8a16aD5e802704D2cA4EFca9e8a46',
}, {
  symbol: 'cePumpBTC BorrowListaDAODistributor',
  lpToken: '0xF95144b8aeFeeD7cBea231D24Be53766223Ad5f0',
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
    manager = "0x227eeaf69495E97c1E72A48785B8A041664b5a28"; // router address
  }

  for (const collateralConfig of collateralConfigs) {
    console.log(`BorrowListaDistributor loop start, ${collateralConfig.symbol}`);

    const address = await deployProxy(
      hre,
      "BorrowListaDistributor",
      name,
      collateralConfig.symbol,
      deployer,
      manager,
      listaVault,
      collateralConfig.lpToken
    );
    console.log(`BorrowListaDistributor loop done, ${collateralConfig.symbol} deployed to: ${address}`);

    // const contract = await hre.ethers.getContractAt("ListaVault", listaVault);
    // await contract.registerDistributor(address);
  }

  console.log(`BorrowListaDistributor all done`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
