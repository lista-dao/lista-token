import { deployDirect } from "../tasks";
import hre from "hardhat";

// CAKE: 0x63708EeD5Ee45D9F3f6fEb5D0F4a26F63FCC3AE0
async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  await deployDirect(hre, "MockERC20", deployer, "CAKE", "CAKE");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
