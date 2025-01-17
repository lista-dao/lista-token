import { deployProxy } from "./tasks";
import hre from "hardhat";
async function main() {
  const name = "ListaDao";
  const symbol = "Lista-Borrow ceMBTC ListaDAODistributor";
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let lpToken, listaVault, manager, admin;
  if (hre.network.name === "bsc") {
    listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
    lpToken = ""; // cemBTC
    manager = "0xB68443Ee3e828baD1526b3e0Bdf2Dfc6b1975ec4";
    admin = "0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253";
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x0fD548f448AAB6dE7489F8FD1a4be1efca009f1C";
    lpToken = "0x6F805B6548EaF0dC412fD4FA531183b8dD809145";
    manager = "0x227eeaf69495E97c1E72A48785B8A041664b5a28";
    admin = deployer;
  }
  const address = await deployProxy(
    hre,
    "BorrowLisUSDListaDistributor",
    name,
    symbol,
    admin,
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
