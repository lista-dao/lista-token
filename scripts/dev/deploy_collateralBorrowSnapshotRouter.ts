import { deployProxy } from "../tasks";
import hre from "hardhat";


async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let manager = '';
  let borrowLisUSDListaDistributor = '';
  if (hre.network.name === "bscTestnet") {
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
    ['0x49b1401B4406Fe0B32481613bF1bC9Fe4B9378aC', '0xB1E63330f4718772CF939128d222389b30C70cF2', '0x92D8c63E893685Cced567b23916a8726b0CEF3FE'],
    ['0x27B014734A6f6567bBD03f32E4904a0c9dC5d010', '0x3A2F04b043ec4817Dbc186ef96df0013d722aBbb', '0x938999C495E6EaCdAC12EF935BFDD0E9AA0332aC'],
  );

  console.log(`CollateralBorrowSnapshotRouter deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
