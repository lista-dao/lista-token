import { deployProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  const cake = "0xf71F939063502E6479c8f6F00E31FD03780C3488";
  const lpToken = "0x5eBFbF56048575d37C033843F2AC038885EBB636";
  await deployProxy(hre, "MockPancakeV2Wrapper", cake, lpToken);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
