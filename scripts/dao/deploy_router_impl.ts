import { deployDirect } from "../tasks";
import hre from "hardhat";

async function main() {
  let newImpl = 'contracts/dao/CollateralBorrowSnapshotRouter.sol:CollateralBorrowSnapshotRouter';

  await deployDirect(hre, newImpl);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
