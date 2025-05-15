import { deployProxy } from "../tasks";
import hre from "hardhat";

const collateralConfigs: any[] = [{
  symbol: 'USD1 CollateralListaDistributor',
  lpToken: '0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d',
}]

async function main() {
  const name = "ListaDao";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let listaVault = '', manager, admin;
  if (hre.network.name === "bsc") {
    listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
    manager = "0x74E17e6996f0DDAfdA9B500ab15a3AD7c2f69307"; // router address
    admin = "0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253"
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    manager = "0x227eeaf69495E97c1E72A48785B8A041664b5a28"; // router address
    admin = deployer
  }

  for (const collateralConfig of collateralConfigs) {
    console.log(`CollateralListaDistributor loop start, ${collateralConfig.symbol}`);

    const address = await deployProxy(
      hre,
      "CollateralListaDistributor",
      name,
      collateralConfig.symbol,
      admin,
      manager,
      listaVault,
      collateralConfig.lpToken
    );
    console.log(`CollateralListaDistributor loop done, ${collateralConfig.symbol} deployed to: ${address}`);

    if (hre.network.name === "bscTestnet") {
      const vaultContract = await hre.ethers.getContractAt("ListaVault", listaVault);
      await vaultContract.registerDistributor(address);
      console.log(`CollateralListaDistributor register to ListaVault done`);
    }
  }

  console.log(`CollateralListaDistributor all done`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
