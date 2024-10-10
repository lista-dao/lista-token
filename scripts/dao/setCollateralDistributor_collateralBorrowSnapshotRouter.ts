import hre, { ethers } from "hardhat";

// TODO:
const collateralDistributors: string[] = [
  '',
  ''
]

// TODO: add contract address
const collateralBorrowSnapshotRouter = ""

async function main() {
  const network = hre.network.name;
  console.log("setCollateralDistributor enter, Network: ", network);

  const Contract = await hre.ethers.getContractFactory("CollateralBorrowSnapshotRouter");
  const contract = Contract.attach(collateralBorrowSnapshotRouter);

  for (let collateralDistributor of collateralDistributors) {
    const DistributorContract = await hre.ethers.getContractFactory("CollateralListaDistributor");
    const distributorContract = DistributorContract.attach(collateralDistributor);

    const token = await distributorContract.lpToken();
    console.log(`setCollateralDistributor query, ${collateralDistributor}, token: ${token}`);

    const tx = await contract.setCollateralDistributor(token, collateralDistributor);
    console.log(`setCollateralDistributor ok, ${token} > ${collateralDistributor}, tx: `, tx.hash);
    await tx.wait(3);
    console.log(`setCollateralDistributor done, ${token} > ${collateralDistributor}`);
  }
}


main()
  .then(() => {
    console.log("setCollateralDistributor done");
  })
  .catch(console.error);

