import { deployDirect, deployProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  const cake = "0xf71F939063502E6479c8f6F00E31FD03780C3488";
  await deployProxy(hre, "StakingVault", deployer, cake, deployer);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
