import { deployProxy } from "../tasks";
import hre from "hardhat";

const cake = "0x9a047D50eE066144770e793086f7fBA8b3615ff7";
const lpToken = "0x5eBFbF56048575d37C033843F2AC038885EBB636";

// 1. Proxy MockPancakeV2Wrapper deployed to: 0x57117D0226AEa1490F8d9D403c56Dbca1317dF8D
// 2. Proxy MockPancakeV2Wrapper deployed to: 0xa8b35D9f1521A786f4E8258151427E48211F9679 (new)
async function main() {
  await deployProxy(hre, "MockPancakeV2Wrapper", cake, lpToken);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
