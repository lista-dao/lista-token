import { deployDirect, deployProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  const feeReceiver = "0x34B504A5CF0fF41F8A480580533b6Dda687fa3Da";

  const rewardToken = "0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11";
  await deployProxy(hre, "StakingVault", deployer, rewardToken, feeReceiver);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
