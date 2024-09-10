import { deployDirect, deployProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  await deployDirect(hre, "MockPancakeV2Wrapper");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
