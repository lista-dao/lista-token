import { deployProxy } from "../tasks";
import hre from "hardhat";

const cake = "0x9a047D50eE066144770e793086f7fBA8b3615ff7";
const lpToken = "0x7B9eF7b3a0A50E83dD3065595D70f456410d3463";

// 1. Proxy MockPancakeV2Wrapper deployed to: 0x57117D0226AEa1490F8d9D403c56Dbca1317dF8D
// 2. Proxy MockPancakeV2Wrapper deployed to: 0xa8b35D9f1521A786f4E8258151427E48211F9679 (deprecated)
// 3. Proxy MockPancakeV2Wrapper deployed to: 0xdEFF5D296D380385Be2a9A49259053d554AC1d4C (new)
// 0x0921d42D5B7511b586A6A522fFd041394E4879e8
async function main() {
  await deployProxy(hre, "MockPancakeV2Wrapper", cake, lpToken);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
