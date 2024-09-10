import { deployDirect, deployProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  const pancakeVault = "0xF85376CAcB054953F20656277cc607170404A1F6";
  await deployProxy(hre, "PancakeStaking", deployer, pancakeVault);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
