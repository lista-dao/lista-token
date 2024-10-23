import { deployProxy } from "../tasks";
import hre from "hardhat";


async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let manager = '';
  let borrowLisUSDListaDistributor = '';
  if (hre.network.name === "bsc") {
    manager = "0xB68443Ee3e828baD1526b3e0Bdf2Dfc6b1975ec4"; // interaction mainnet
    borrowLisUSDListaDistributor = "0x0AED860cA496600F6976219Cb1acEc435d7F4f3B";
  } else if (hre.network.name === "bscTestnet") {
    manager = "0x70C4880A3f022b32810a4E9B9F26218Ec026f279"; // testnet
    borrowLisUSDListaDistributor = "0xd94Bf442beD7eb23200B72F5e396AA6e4f0dE661";
  } else {
    console.log(`CollateralBorrowSnapshotRouter error, invalid network ${hre.network.name}`);
    return
  }

  const address = await deployProxy(
    hre,
    "CollateralBorrowSnapshotRouter",
    deployer,
    manager,
    borrowLisUSDListaDistributor,
    [],
    [],
  );

  console.log(`CollateralBorrowSnapshotRouter deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
