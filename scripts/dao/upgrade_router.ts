import { upgradeProxy, validateUpgrade } from "../tasks";
import hre from "hardhat";

const proxyAddress = "0x227eeaf69495E97c1E72A48785B8A041664b5a28";

async function main() {
  let old = 'contracts/old/CollateralBorrowSnapshotRouter.sol:CollateralBorrowSnapshotRouter';
  let newImpl = 'contracts/dao/CollateralBorrowSnapshotRouter.sol:CollateralBorrowSnapshotRouter';
  validateUpgrade(hre, old, newImpl);
  console.log("Upgrade validated");
  const oldVeLista = await hre.ethers.getContractFactory(old);
  await hre.upgrades.forceImport(proxyAddress, oldVeLista);

  await upgradeProxy(
    hre,
    newImpl,
    proxyAddress
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
